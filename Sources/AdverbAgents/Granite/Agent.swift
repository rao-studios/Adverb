import Foundation
import Granite

/// An agent, declared in a center the way an event is:
///
///     @Agent var coder: Coder.Agent
///     @Agent(.parallel(max: 4)) var worker: Worker.Agent
///     @Agent(.onTask) var watcher: Watcher.Agent
///
/// Compiled by the center's own pass through `GraniteCustomEvent` (the one Granite hook Craft
/// needed), so a send reaches a run the same way a send reaches a reducer. The wrapped and the
/// projected value are the same handle: `coder.send(…)`, `$coder.cancel()`, `$coder.events()`,
/// `$coder.attach { … }`.
@propertyWrapper
public struct Agent<A: GraniteAgent>: GraniteCustomEvent {
    public let forwarding: Forwarding = .none
    public let lifecycle: Lifecycle
    public let intermediateSignal = GraniteSignal.Payload<GranitePayload?>()
    public let executable: AgentExecutable<A>
    /// Set at declaration, beside the agent's own default (`GraniteAgent.concurrency`).
    public let concurrency: AgentConcurrency?

    public var signal: GraniteSignal.Payload<GranitePayload?> { executable.signal }
    public var wrappedValue: AgentExecutable<A> { executable }
    public var projectedValue: AgentExecutable<A> { executable }

    public init(_ lifecycle: Lifecycle = .none) {
        self.lifecycle = lifecycle
        self.concurrency = nil
        self.executable = AgentExecutable<A>()
    }

    public init(_ concurrency: AgentConcurrency, _ lifecycle: Lifecycle = .none) {
        self.lifecycle = lifecycle
        self.concurrency = concurrency
        self.executable = AgentExecutable<A>()
    }

    public func compile(with host: GraniteEventHost) -> [any GraniteEventContainer] {
        [executable.compile(with: host)]
    }
}
