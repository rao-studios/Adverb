//
//  PlanJob.swift
//  AdverbAgents
//
//  WHAT: Plans a campaign's month: the project's digest (frozen for the campaign), the brief, the
//        writer with the skill, the plan checked against the brief (one round of fixes), the days
//        written to campaign.json.
//

import AdverbCore
import Foundation

public enum PlanJob {
    public static func run(projectSlug: String, campaignID: UUID, compute: AdverbCompute,
                           emit: @escaping @Sendable (GenerationEvent) -> Void) async throws {
        let project = try compute.project(projectSlug)
        let paths = compute.paths(project, campaignID)
        var campaign = try await CampaignLedger.shared.read(paths)
        let model = compute.text
        let log = RunLog(paths: paths, campaignID: campaignID, kind: .plan, model: model.info.id)
        do {
            emit(.step("Reading \(project.name)"))
            log.step("Reading the project at \(project.contextPath)")
            let digest = try compute.digest(project, paths: paths, refresh: !campaign.isPlanned)
            log.line("digest: \(digest.text.count) characters, sha \(digest.hash.prefix(12))")

            emit(.step("Planning the month"))
            log.step("Planning \(campaign.brief.postDates.count) days with \(model.info.title)")
            let turns = compute.prompts.plan(digest: digest.text, brief: campaign.brief, project: project, campaignName: campaign.name)
            // A day of the plan is about 400 tokens; thirty of them, the summary and the thinking.
            let maxTokens = 6_000 + campaign.brief.postDates.count * 600 + (compute.thinking == .off ? 0 : compute.settings.thinkingBudget)
            var request = ModelRequest(system: compute.prompts.system, turns: turns, format: Schemas.planFormat, maxTokens: maxTokens,
                                       thinking: compute.thinking, label: "plan")
            var (plan, answer) = try await ModelCall.structured(PlanResponse.self, model: model, request: request, log: log, emit: emit)
            var problems = PlanValidator.problems(plan, brief: campaign.brief)
            if !problems.isEmpty {
                emit(.step("Fixing the plan"))
                log.step("Fixing: \(problems.joined(separator: " | "))")
                request.turns = compute.prompts.planFix(previous: turns, answer: answer.text, problems: problems)
                request.thinking = .off
                (plan, answer) = try await ModelCall.structured(PlanResponse.self, model: model, request: request, log: log, emit: emit)
                problems = PlanValidator.problems(plan, brief: campaign.brief)
            }
            guard problems.isEmpty else { throw ModelError.invalid("The plan still does not fit the brief: " + problems.joined(separator: " ")) }

            let final = plan
            let days = PlanValidator.days(final, brief: campaign.brief)
            let modelName = answer.model.isEmpty ? model.info.id : answer.model
            campaign = try await CampaignLedger.shared.update(paths) { c in
                c.plan = CampaignPlan(summary: final.summary, arc: final.arc, sources: final.sources, cautions: final.cautions, model: modelName)
                c.days = days
                c.contextDigestHash = digest.hash
                c.lastRunID = log.id
            }
            log.line("planned \(days.count) days: \(days.map(\.topic.slug).joined(separator: ", "))")
            emit(.planned(days.count))
            log.finish(.succeeded)
        } catch is CancellationError {
            log.finish(.cancelled); throw CancellationError()
        } catch {
            log.finish(.failed("\(error)")); throw error
        }
    }
}
