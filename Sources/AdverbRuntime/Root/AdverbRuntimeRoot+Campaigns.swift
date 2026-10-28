//
//  AdverbRuntimeRoot+Campaigns.swift
//  AdverbRuntime
//
//  WHAT: Campaigns: create a draft, plan it, build its days, go live, mark days posted, export
//        the month, remove. Runs go through the generation agents; their taps read the campaign
//        again each time a day is written.
//

import AdverbAgents
import AdverbCore
import AdverbRender
import Foundation

extension AdverbRuntimeRoot {
    func store(_ slug: String) -> CampaignStore? {
        guard let workspace, let project = project(slug) else { return nil }
        return CampaignStore(workspace: workspace, project: project)
    }

    /// The project, from the service, else from its project.json (the service may not have it yet:
    /// its reducer runs after `set` returns).
    public func project(_ slug: String) -> Project? {
        if let p = projects.state.project(slug) { return p }
        guard let workspace else { return nil }
        return try? JSONCoding.read(Project.self, from: workspace.projectFile(slug))
    }

    public func paths(_ slug: String, _ id: UUID) -> CampaignPaths? {
        guard let workspace else { return nil }
        return CampaignPaths(workspace: workspace, projectSlug: slug, campaignID: id)
    }

    public func reloadCampaigns(_ slug: String) async {
        guard let store = store(slug) else { return }
        let list = await Task.detached { store.list() }.value
        campaigns.set(.loaded(slug: slug, list))
    }

    public func reloadCampaign(_ slug: String, _ id: UUID) async {
        guard let store = store(slug) else { return }
        if let campaign = try? await Task.detached(operation: { try store.load(id) }).value {
            campaigns.set(.updated(slug: slug, campaign))
        }
    }

    @discardableResult
    public func createCampaign(_ slug: String, name: String, brief: CampaignBrief, planNow: Bool = true) async -> Campaign? {
        guard let store = store(slug) else { return nil }
        do {
            let campaign = try await Task.detached { try store.create(name: name, brief: brief) }.value
            campaigns.set(.updated(slug: slug, campaign))
            if planNow { plan(slug, campaign.id) }
            return campaign
        } catch {
            config.set(.problem("\(error)"))
            return nil
        }
    }

    public func plan(_ slug: String, _ id: UUID) {
        let key = RunKey.plan(id)
        watch(generation.center.$planner.events(key: key), slug: slug, id: id)
        generation.center.planner.send(Planner.Input(projectSlug: slug, campaignID: id))
    }

    /// Builds every day (or only those without an asset).
    public func buildAll(_ slug: String, _ id: UUID, onlyMissing: Bool = true) {
        guard let campaign = campaigns.state.campaign(id) else { return }
        let days = campaign.days.filter { !onlyMissing || $0.asset == nil }
        guard !days.isEmpty else { config.set(.notice("Every day is built.")); return }
        // Two at a time is the agent's own limit; one at a time (Settings) queues them here.
        guard settings.buildConcurrency <= 1 else {
            for day in days { build(slug, id, day: day.index) }
            return
        }
        buildQueues[id]?.task.cancel()
        let token = UUID()
        let task = Task { @MainActor in
            defer { if self.buildQueues[id]?.token == token { self.buildQueues[id] = nil } }
            for day in days {
                let key = RunKey.build(id, day.index)
                let tap = generation.center.$builder.events(key: key)
                watch(generation.center.$builder.events(key: key), slug: slug, id: id)
                generation.center.builder.send(Builder.Input(projectSlug: slug, campaignID: id, dayIndex: day.index))
                for await _ in tap { if Task.isCancelled { break } }
                if Task.isCancelled { return }
            }
        }
        buildQueues[id] = (token, task)
    }

    public func build(_ slug: String, _ id: UUID, day: Int) {
        let key = RunKey.build(id, day)
        watch(generation.center.$builder.events(key: key), slug: slug, id: id)
        generation.center.builder.send(Builder.Input(projectSlug: slug, campaignID: id, dayIndex: day))
    }

    public func cancelRuns(_ id: UUID) {
        buildQueues[id]?.task.cancel()
        buildQueues[id] = nil
        generation.center.$planner.cancel(key: RunKey.plan(id))
        generation.center.$builder.cancel(prefix: "\(id.uuidString)/")
        generation.center.$retimer.cancel(prefix: "beat/\(id.uuidString)/")
        generation.center.$voicer.cancel(prefix: RunKey.voicePrefix(id))
    }

    public func cancelRun(_ key: String) {
        switch RunKey.parse(key).kind {
        case "Plan": generation.center.$planner.cancel(key: key)
        case "Beatmap": generation.center.$retimer.cancel(key: key)
        case "Voice": generation.center.$voicer.cancel(key: key)
        default: generation.center.$builder.cancel(key: key)
        }
    }

    /// Reads the campaign again while a run writes it, and once more when it ends; regenerates the
    /// overview and the exports after the last build of a campaign finishes.
    func watch(_ events: AsyncStream<GenerationEvent>, slug: String, id: UUID) {
        Task { @MainActor in
            for await event in events {
                switch event {
                case .dayDone, .planned: await self.reloadCampaign(slug, id)
                default: break
                }
            }
            await self.reloadCampaign(slug, id)
            if !self.generation.state.isBusy(id) { await self.afterRuns(slug, id) }
        }
    }

    func afterRuns(_ slug: String, _ id: UUID) async {
        guard let campaign = campaigns.state.campaign(id), let paths = paths(slug, id), let project = project(slug) else { return }
        var files: [(name: String, url: URL)] = []
        for day in campaign.days {
            guard let asset = day.asset else { continue }
            for render in asset.renders.sorted(by: { $0.orientation.rawValue > $1.orientation.rawValue }) {
                files.append((name: "\(day.stem)-\(render.orientation.rawValue)", url: paths.url(render.path)))
            }
        }
        if !files.isEmpty { try? await ContactSheet.overview(files: files, to: paths.overview) }
        _ = try? Exports.writeAll(campaign, project: project, paths: paths)
    }

    public func setState(_ slug: String, _ id: UUID, to state: CampaignState, archivingOthers: Bool = false) async -> Bool {
        guard let store = store(slug) else { return false }
        do {
            if archivingOthers, state == .live {
                for other in campaigns.state.campaigns(slug) where other.state == .live && other.id != id {
                    let archived = try await Task.detached { try store.setState(other.id, to: .archived) }.value
                    campaigns.set(.updated(slug: slug, archived))
                }
            }
            let updated = try await Task.detached { try store.setState(id, to: state) }.value
            campaigns.set(.updated(slug: slug, updated))
            if state == .live { _ = await export(slug, id) }
            return true
        } catch {
            config.set(.problem("\(error)"))
            return false
        }
    }

    public func setStatus(_ slug: String, _ id: UUID, day: Int, _ status: PostStatus, platform: Platform? = nil, url: String? = nil) async {
        guard let paths = paths(slug, id) else { return }
        do {
            let campaign = try await CampaignLedger.shared.updateDay(paths, index: day) { d in
                d.status = status
                if status == .posted {
                    for i in d.targets.indices where platform == nil || d.targets[i].platform == platform {
                        d.targets[i].postedAt = d.targets[i].postedAt ?? Date()
                        if let url, !url.isEmpty { d.targets[i].postURL = url }
                    }
                } else if status == .planned || status == .rendered {
                    for i in d.targets.indices { d.targets[i].postedAt = nil }
                    if status == .planned, d.asset != nil { d.status = .rendered }
                }
            }
            campaigns.set(.updated(slug: slug, campaign))
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    /// Edits to a day's post (caption, hashtags, time) the person makes by hand.
    public func editDay(_ slug: String, _ id: UUID, day: Int, _ change: @escaping @Sendable (inout CampaignDay) -> Void) async {
        guard let paths = paths(slug, id) else { return }
        do {
            let campaign = try await CampaignLedger.shared.updateDay(paths, index: day, change)
            campaigns.set(.updated(slug: slug, campaign))
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    public func export(_ slug: String, _ id: UUID) async -> [URL] {
        guard let campaign = campaigns.state.campaign(id), let paths = paths(slug, id), let project = project(slug) else { return [] }
        do {
            let urls = try Exports.writeAll(campaign, project: project, paths: paths)
            config.set(.notice("Exported the month to \(paths.exports.path)."))
            return urls
        } catch {
            config.set(.problem("\(error)"))
            return []
        }
    }

    public func removeCampaign(_ slug: String, _ id: UUID) async {
        guard let store = store(slug) else { return }
        cancelRuns(id)
        do {
            try await Task.detached { try store.remove(id) }.value
            campaigns.set(.removed(slug: slug, id))
        } catch {
            config.set(.problem("\(error)"))
        }
    }
}
