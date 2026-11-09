//
//  AdverbRuntimeRoot+Campaigns.swift
//  AdverbRuntime
//
//  WHAT: Campaigns: create a draft, plan it, write its days to contact sheets, approve or redo each
//        sheet, render the approved days, go live, mark days posted, export the month, remove. Runs
//        go through the generation agents; their taps read the campaign again each time a day is
//        written or a sheet drawn.
//  PIN:  The sheet gate (Settings): on, a day stops at its sheet until it is approved; off, a day
//        whose sheet passed its checks renders in the same run.
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

    /// Writes every day that has no sheet yet (or every day) to its contact sheet.
    public func writeSheets(_ slug: String, _ id: UUID, onlyMissing: Bool = true) {
        guard let campaign = campaigns.state.campaign(id) else { return }
        let days = campaign.days.filter { day in
            guard day.status != .posted, day.status != .skipped else { return false }
            return !onlyMissing || day.asset?.sheetPath == nil
        }.filter { generation.state.dayRun(id, $0.index)?.phase != .running }
        guard !days.isEmpty else { config.set(.notice("Every day has its sheet.")); return }
        queue(days.map(\.index), slug: slug, id: id)
    }

    /// One day written (again): with a note, the page it has is changed to do what the note asks.
    public func write(_ slug: String, _ id: UUID, day: Int, note: String? = nil) {
        let key = RunKey.build(id, day)
        watch(generation.center.$drafter.events(key: key), slug: slug, id: id)
        generation.center.drafter.send(Drafter.Input(projectSlug: slug, campaignID: id, dayIndex: day, note: note))
    }

    /// Kept for the menu's "Build the month": the sheets, and with the gate off, the videos.
    public func buildAll(_ slug: String, _ id: UUID, onlyMissing: Bool = true) {
        writeSheets(slug, id, onlyMissing: onlyMissing)
    }

    /// Two at a time is the agent's own limit; one at a time (Settings) queues them here.
    func queue(_ days: [Int], slug: String, id: UUID) {
        guard settings.buildConcurrency <= 1 else {
            for day in days { write(slug, id, day: day) }
            return
        }
        buildQueues[id]?.task.cancel()
        let token = UUID()
        let task = Task { @MainActor in
            defer { if self.buildQueues[id]?.token == token { self.buildQueues[id] = nil } }
            for day in days {
                let key = RunKey.build(id, day)
                let tap = generation.center.$drafter.events(key: key)
                watch(generation.center.$drafter.events(key: key), slug: slug, id: id)
                generation.center.drafter.send(Drafter.Input(projectSlug: slug, campaignID: id, dayIndex: day))
                for await _ in tap { if Task.isCancelled { break } }
                if Task.isCancelled { return }
            }
        }
        buildQueues[id] = (token, task)
    }

    /// The person looked at a day's sheet and it is right: ready to render.
    public func approve(_ slug: String, _ id: UUID, day: Int, render now: Bool = false) async {
        guard let paths = paths(slug, id) else { return }
        do {
            let campaign = try await CampaignLedger.shared.updateDay(paths, index: day) { d in
                guard d.asset?.sheetPath != nil else { return }
                d.approvedAt = Date()
                if d.status == .sheeted || d.status == .planned { d.status = .approved }
            }
            campaigns.set(.updated(slug: slug, campaign))
            if now { render(slug, id, day: day) }
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    /// Every day waiting at its sheet, approved.
    public func approveAll(_ slug: String, _ id: UUID) async {
        guard let campaign = campaigns.state.campaign(id) else { return }
        let waiting = campaign.days.filter { $0.status == .sheeted }.map(\.index)
        guard !waiting.isEmpty else { config.set(.notice("No sheet is waiting.")); return }
        for day in waiting { await approve(slug, id, day: day) }
        config.set(.notice("Approved \(waiting.count) \(waiting.count == 1 ? "sheet" : "sheets")."))
    }

    /// One day rendered from its sheet.
    public func render(_ slug: String, _ id: UUID, day: Int) {
        let key = RunKey.render(id, day)
        watch(generation.center.$renderer.events(key: key), slug: slug, id: id)
        generation.center.renderer.send(Renderer.Input(projectSlug: slug, campaignID: id, dayIndex: day))
    }

    /// Every approved day rendered, two at a time.
    public func renderApproved(_ slug: String, _ id: UUID) {
        guard let campaign = campaigns.state.campaign(id) else { return }
        let days = campaign.days.filter { $0.status == .approved && $0.asset?.sheetPath != nil }
            .filter { generation.state.dayRun(id, $0.index)?.phase != .running }
        guard !days.isEmpty else { config.set(.notice("No approved day is waiting to render.")); return }
        for day in days { render(slug, id, day: day.index) }
        config.set(.notice("Rendering \(days.count) \(days.count == 1 ? "day" : "days"), two at a time."))
    }

    public func cancelRuns(_ id: UUID) {
        buildQueues[id]?.task.cancel()
        buildQueues[id] = nil
        generation.center.$planner.cancel(key: RunKey.plan(id))
        generation.center.$drafter.cancel(prefix: "\(id.uuidString)/")
        generation.center.$renderer.cancel(prefix: "render/\(id.uuidString)/")
        generation.center.$retimer.cancel(prefix: "beat/\(id.uuidString)/")
        generation.center.$voicer.cancel(prefix: RunKey.voicePrefix(id))
    }

    public func cancelRun(_ key: String) {
        switch RunKey.parse(key).kind {
        case "Plan": generation.center.$planner.cancel(key: key)
        case "Beatmap": generation.center.$retimer.cancel(key: key)
        case "Voice": generation.center.$voicer.cancel(key: key)
        case "Render": generation.center.$renderer.cancel(key: key)
        default: generation.center.$drafter.cancel(key: key)
        }
    }

    /// Reads the campaign again while a run writes it, and once more when it ends; regenerates the
    /// overview and the exports after the last build of a campaign finishes.
    func watch(_ events: AsyncStream<GenerationEvent>, slug: String, id: UUID) {
        Task { @MainActor in
            for await event in events {
                switch event {
                case .dayDone, .planned, .sheet: await self.reloadCampaign(slug, id)
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
            if asset.renders.isEmpty {
                // A day at its sheet: its middle stills stand in for the videos.
                for o in [Orientation.portrait, .landscape] {
                    let stills = asset.stills(o).sorted { $0.time < $1.time }
                    if let still = stills.dropFirst().first ?? stills.first {
                        files.append((name: "\(day.stem)-\(o.rawValue) · sheet", url: paths.url(still.path)))
                    }
                }
                continue
            }
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
                    // Back from posted or skipped: to where the day's files say it is.
                    if status == .planned, let asset = d.asset {
                        d.status = !asset.renders.isEmpty ? .rendered : d.approvedAt != nil ? .approved : asset.sheetPath != nil ? .sheeted : .planned
                    }
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
