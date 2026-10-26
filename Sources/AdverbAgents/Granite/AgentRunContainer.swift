import Combine
import Foundation
import Granite

/// The compiled half of `@Agent`: what the hosting command keeps. Starts runs, applies the
/// concurrency policy, queues each run's frames and drains them on main into one commit, drops
/// the frames of a run that was superseded, and feeds the taps the CLI and the traces read.
///
/// PIN: every entry here is on main — `start`, `cancel`, `drain` — the way a Granite send is;
/// `AgentExecutable` hops before calling. The run's task only ever enqueues.
final class AgentRunContainer<A: GraniteAgent>: GraniteEventContainer, @unchecked Sendable {
    let id = UUID()
    let label: String
    let reducerType: AnyGraniteReducer.Type? = nil

    private let host: GraniteEventHost
    private let agent = A()
    private var lifecycleSubscription: AnyCancellable?
    private let lock = NSLock()
    private var runs: [String: Live] = [:]
    private var waiting: [(key: String, input: A.Input)] = []
    private var frames: [String: [Frame]] = [:]
    private var drains: Set<String> = []
    private var taps: [String: [AsyncStream<A.Event>.Continuation]] = [:]
    private var counter = 0
    var resolver: (@Sendable (A.Input) async throws -> A.Compute)?

    private enum Frame { case event(A.Event), lifecycle(AgentLifecycle) }

    private final class Live {
        let id: AgentRunID
        var task: Task<Void, Never>?
        var context: A.Context?
        init(id: AgentRunID) { self.id = id }
    }

    init(host: GraniteEventHost, label: String, signal: GraniteSignal.Payload<GranitePayload?>) {
        self.host = host
        self.label = label
        // The host's lifecycle (`@Agent(.onTask)`) sends on the wrapper's signal.
        lifecycleSubscription = signal.publisher.sink { [weak self] payload in self?.fire(payload) }
    }

    /// Granite's own entry: a lifecycle send, or `dispatch` by reducer type.
    func fire(_ payload: GranitePayload?) {
        guard let input = A.lifecycleInput else { return }
        onMain { self.start(input) }
    }

    func onMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Runs (main)

    func isLive(key: String) -> Bool { lock.withLock { runs[key] != nil } }

    func liveKeys() -> [String] { lock.withLock { Array(runs.keys) + waiting.map(\.key) } }

    /// Main. Live runs commit `.cancelled`, and so do runs still waiting for a lane.
    ///
    /// PIN: a run asked for and dropped before it started ends as one stopped live would. It used to go
    /// without a lifecycle: whoever announced it kept a card that never closed, and its taps never ended.
    func cancel(prefix: String) {
        let (live, dropped): ([String], [String]) = lock.withLock {
            let dropped = waiting.filter { $0.key.hasPrefix(prefix) }.map(\.key)
            waiting.removeAll { $0.key.hasPrefix(prefix) }
            return (runs.keys.filter { $0.hasPrefix(prefix) }, dropped)
        }
        for key in dropped {
            let run: AgentRunID = lock.withLock {
                counter += 1
                return AgentRunID(raw: "\(label)-\(counter)", key: key)
            }
            commit(lifecycle: .cancelled, run: run)
            closeTaps(key: key)
        }
        for key in live { cancel(key: key) }
    }

    func start(_ input: A.Input) {
        let key = A.key(input)
        if let live = lock.withLock({ runs[key] }) {
            switch A.concurrency {
            case .supersede:
                cancel(key: key)
            case .drop:
                return
            case .merge:
                guard let context = live.context else { return }
                let agent = self.agent
                let run = live.id
                Task { await agent.merge(input, into: run, context: context) }
                return
            case .parallel:
                // The same key twice is the same run asked for again: the newer one replaces it.
                cancel(key: key)
            }
        }
        if case .parallel(let max) = A.concurrency, let max, lock.withLock({ runs.count }) >= max {
            lock.withLock { waiting.append((key, input)) }
            return
        }
        launch(input, key: key)
    }

    func cancel(key: String) {
        guard let live = lock.withLock({ runs.removeValue(forKey: key) }) else { return }
        live.task?.cancel()
        // Said now, on main, before any late frame could: the run is over for the state and
        // for whoever was listening. Frames it still enqueues are dropped (`drain` checks).
        lock.withLock { frames.removeValue(forKey: live.id.raw) }
        commit(lifecycle: .cancelled, run: live.id)
        closeTaps(key: key)
        startWaiting()
    }

    private func launch(_ input: A.Input, key: String) {
        let runID: AgentRunID = lock.withLock {
            counter += 1
            return AgentRunID(raw: "\(label)-\(counter)", key: key)
        }
        let live = Live(id: runID)
        lock.withLock { runs[key] = live }
        commit(lifecycle: .started, run: runID)
        let resolver = self.resolver
        let agent = self.agent
        let deliver: @Sendable (A.Event) -> Void = { [weak self] event in self?.enqueue(.event(event), run: runID) }
        live.task = Task(priority: .userInitiated) { [weak self] in
            let outcome: AgentLifecycle
            do {
                guard let resolver else { throw AgentRunError.noCompute(String(describing: A.self)) }
                let compute = try await resolver(input)
                let context = A.Context(run: runID, compute: compute, isCancelled: { Task.isCancelled }, deliver: deliver)
                self?.lock.withLock { live.context = context }
                var ended: AgentLifecycle = .finished
                for try await event in agent.run(input, context: context) {
                    if Task.isCancelled { ended = .cancelled; break }
                    deliver(event)
                }
                outcome = Task.isCancelled ? .cancelled : ended
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = Task.isCancelled ? .cancelled : .failed("\(error)")
            }
            self?.enqueue(.lifecycle(outcome), run: runID)
        }
    }

    private func startWaiting() {
        guard case .parallel(let max) = A.concurrency else { return }
        let next: (key: String, input: A.Input)? = lock.withLock {
            guard max.map({ runs.count < $0 }) ?? true, !waiting.isEmpty else { return nil }
            return waiting.removeFirst()
        }
        if let next { launch(next.input, key: next.key) }
    }

    // MARK: - Frames (any thread in, main out)

    private func enqueue(_ frame: Frame, run: AgentRunID) {
        let schedule: Bool = lock.withLock {
            frames[run.raw, default: []].append(frame)
            return drains.insert(run.raw).inserted
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in self?.drain(run) }
    }

    private func drain(_ run: AgentRunID) {
        let pending: [Frame] = lock.withLock {
            drains.remove(run.raw)
            return frames.removeValue(forKey: run.raw) ?? []
        }
        guard !pending.isEmpty else { return }
        // A frame of a run that was superseded or cancelled is dropped: its state is gone.
        guard lock.withLock({ runs[run.key]?.id == run }) else { return }
        var events: [A.Event] = []
        var ended: AgentLifecycle?
        for frame in pending {
            switch frame {
            case .event(let event):
                if let last = events.last, let one = A.coalesce(last, event) { events[events.count - 1] = one } else { events.append(event) }
            case .lifecycle(let lifecycle):
                ended = lifecycle
            }
        }
        let taps = lock.withLock { self.taps[run.key] ?? [] }
        for event in events { for tap in taps { tap.yield(event) } }
        if var state = host.state() as? A.Center.GenericGraniteState {
            for event in events { agent.reduce(state: &state, event: event, run: run) }
            if let ended { agent.reduce(state: &state, lifecycle: ended, run: run) }
            host.commit(state)
        }
        if ended != nil {
            lock.withLock { if runs[run.key]?.id == run { runs.removeValue(forKey: run.key) } }
            closeTaps(key: run.key)
            startWaiting()
        }
    }

    private func commit(lifecycle: AgentLifecycle, run: AgentRunID) {
        guard var state = host.state() as? A.Center.GenericGraniteState else { return }
        agent.reduce(state: &state, lifecycle: lifecycle, run: run)
        host.commit(state)
    }

    // MARK: - Taps

    /// Every event of the run with `key`, before it is reduced, until the run ends.
    func events(key: String) -> AsyncStream<A.Event> {
        AsyncStream { continuation in
            lock.withLock { taps[key, default: []].append(continuation) }
        }
    }

    private func closeTaps(key: String) {
        let open = lock.withLock { taps.removeValue(forKey: key) ?? [] }
        for tap in open { tap.finish() }
    }
}
