import Foundation
import Granite

/// What `@Agent var coder: Coder.Agent` holds and `$coder` projects: the handle a view, a boot or
/// the CLI sends through, cancels through, taps, and attaches compute to.
public final class AgentExecutable<A: GraniteAgent>: @unchecked Sendable {
    /// Granite's lifecycle sends here (`@Agent(.onTask)`).
    public let signal = GraniteSignal.Payload<GranitePayload?>()
    private let lock = NSLock()
    private var container: AgentRunContainer<A>?
    private var resolver: (@Sendable (A.Input) async throws -> A.Compute)?

    public init() {}

    /// The composition root supplies what a run computes with, from its input.
    public func attach(_ resolve: @escaping @Sendable (A.Input) async throws -> A.Compute) {
        lock.withLock {
            resolver = resolve
            container?.resolver = resolve
        }
    }

    /// Starts a run (or merges, drops, queues — `GraniteAgent.concurrency`). Main-only; an
    /// off-main send hops to main first, as Ambient's reducers do.
    public func send(_ input: A.Input) {
        guard let container = lock.withLock({ container }) else {
            FileHandle.standardError.write(Data("\(String(describing: A.self)) sent before its center compiled; dropped\n".utf8))
            return
        }
        container.onMain { container.start(input) }
    }

    /// Cancels the live run with `key`, committing `.cancelled` at once.
    public func cancel(key: String = AgentRunID.defaultKey) {
        guard let container = lock.withLock({ container }) else { return }
        container.onMain { container.cancel(key: key) }
    }

    public func isLive(key: String = AgentRunID.defaultKey) -> Bool {
        lock.withLock { container }?.isLive(key: key) ?? false
    }

    /// The keys of every run that is live or waiting for a lane.
    public func liveKeys() -> [String] {
        lock.withLock { container }?.liveKeys() ?? []
    }

    /// Cancels every run whose key starts with `prefix`, and drops those still waiting: everything one
    /// session started, when its key is `session/…`.
    public func cancel(prefix: String) {
        guard let container = lock.withLock({ container }) else { return }
        container.onMain { container.cancel(prefix: prefix) }
    }

    /// Every event of the run with `key`, as it streams and before it is reduced, until the run
    /// ends: what the CLI renders and the traces record.
    public func events(key: String = AgentRunID.defaultKey) -> AsyncStream<A.Event> {
        guard let container = lock.withLock({ container }) else { return AsyncStream { $0.finish() } }
        return container.events(key: key)
    }

    func compile(with host: GraniteEventHost) -> AgentRunContainer<A> {
        lock.withLock {
            if let container { return container }
            let made = AgentRunContainer<A>(host: host, label: String(describing: A.self), signal: signal)
            made.resolver = resolver
            container = made
            return made
        }
    }
}
