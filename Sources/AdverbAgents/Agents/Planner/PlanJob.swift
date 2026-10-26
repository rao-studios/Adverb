//
//  PlanJob.swift
//  AdverbAgents
//
//  WHAT: Plans a campaign's month: the project's digest (frozen for the campaign), the brief,
//        Claude with the skill, the plan checked against the brief (one round of fixes), the days
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
        let log = RunLog(paths: paths, campaignID: campaignID, kind: .plan, model: compute.settings.model)
        do {
            emit(.step("Reading \(project.name)"))
            log.step("Reading the project at \(project.contextPath)")
            let digest = try compute.digest(project, paths: paths, refresh: !campaign.isPlanned)
            log.line("digest: \(digest.text.count) characters, sha \(digest.hash.prefix(12))")

            emit(.step("Planning the month"))
            log.step("Planning \(campaign.brief.postDates.count) days with \(compute.settings.model)")
            let messages = compute.prompts.plan(digest: digest.text, brief: campaign.brief, project: project, campaignName: campaign.name)
            var request = ClaudeRequest(system: compute.prompts.system, messages: messages, schema: Schemas.plan,
                                        tools: compute.tools(for: project), maxTokens: 64_000)
            var (plan, message) = try await ClaudeCall.structured(PlanResponse.self, client: compute.client, request: request, log: log, emit: emit)
            var problems = PlanValidator.problems(plan, brief: campaign.brief)
            if !problems.isEmpty {
                emit(.step("Fixing the plan"))
                log.step("Fixing: \(problems.joined(separator: " | "))")
                request.messages = compute.prompts.planFix(previous: messages, answer: message.text, problems: problems)
                request.tools = []
                (plan, message) = try await ClaudeCall.structured(PlanResponse.self, client: compute.client, request: request, log: log, emit: emit)
                problems = PlanValidator.problems(plan, brief: campaign.brief)
            }
            guard problems.isEmpty else { throw ClaudeError.invalid("The plan still does not fit the brief: " + problems.joined(separator: " ")) }

            let final = plan
            let days = PlanValidator.days(final, brief: campaign.brief)
            let model = message.model.isEmpty ? compute.settings.model : message.model
            campaign = try await CampaignLedger.shared.update(paths) { c in
                c.plan = CampaignPlan(summary: final.summary, arc: final.arc, sources: final.sources, cautions: final.cautions, model: model)
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
