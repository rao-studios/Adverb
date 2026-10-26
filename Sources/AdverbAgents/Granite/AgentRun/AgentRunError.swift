import Foundation

public enum AgentRunError: Error, CustomStringConvertible {
    /// `send` before `attach`: nothing to compute with.
    case noCompute(String)
    public var description: String {
        switch self {
        case .noCompute(let agent): return "\(agent) has no compute attached: call `$agent.attach { input in … }` from the composition root"
        }
    }
}
