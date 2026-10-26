//
//  APIKeyStore.swift
//  AdverbCore
//
//  WHAT: Where Adverb finds the Claude API key, in order: its own Keychain item (service
//        nyc.rao.adverb, account ANTHROPIC_API_KEY), then ANTHROPIC_API_KEY in the environment.
//        The environment is read, never written; "Forget" removes only the Keychain item.
//  PIN:  The item is written and read through /usr/bin/security, so it trusts that tool rather
//        than this binary's changing ad-hoc signature and survives rebuilds (Bless's playground,
//        Leviathan's recipe). The key reaches `security` on stdin as hex, never in arguments, so it
//        is not in the process list. A Secret prints as Secret(••••). Every call spawns a
//        process: call these off the main actor.
//

import Foundation

/// An API key that never prints.
public struct Secret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: String

    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }

    public var description: String { "Secret(••••)" }
    public var debugDescription: String { "Secret(••••)" }
    /// "sk-ant-…a1B2": enough to recognise it, not enough to use it.
    public var masked: String { value.count > 12 ? "\(value.prefix(7))…\(value.suffix(4))" : "••••" }
}

public enum KeySource: Sendable, Equatable {
    case keychain
    case environment

    public var label: String {
        switch self {
        case .keychain: "Adverb's Keychain item"
        case .environment: "ANTHROPIC_API_KEY in the environment"
        }
    }
}

public struct ResolvedKey: Sendable, Equatable {
    public let secret: Secret
    public let source: KeySource
    public init(secret: Secret, source: KeySource) { self.secret = secret; self.source = source }
}

public enum KeyStoreError: Error, Equatable, CustomStringConvertible {
    case toolUnavailable
    case notSaved(hint: String?)
    case notRemoved(hint: String?)

    public var description: String {
        switch self {
        case .toolUnavailable: "/usr/bin/security could not be run"
        case .notSaved(let hint): "the key was not saved to the Keychain" + (hint.map { ": \($0)" } ?? "")
        case .notRemoved(let hint): "the key was not removed from the Keychain" + (hint.map { ": \($0)" } ?? "")
        }
    }
}

public protocol KeyStore: Sendable {
    func read() throws -> Secret?
    func write(_ secret: Secret) throws
    func forget() throws
}

public struct KeychainKeyStore: KeyStore {
    public static let service = "nyc.rao.adverb"
    public static let account = "ANTHROPIC_API_KEY"

    public init() {}

    public func read() throws -> Secret? {
        let found = Self.run(["find-generic-password", "-s", Self.service, "-a", Self.account, "-w"])
        if found.status == -1 { throw KeyStoreError.toolUnavailable }
        guard found.status == 0 else { return nil }  // 44: no such item
        return Secret(String(decoding: found.output, as: UTF8.self))
    }

    public func write(_ secret: Secret) throws {
        let saved = Self.run(["-i"], input: Data(Self.addCommand(service: Self.service, account: Self.account, secret: secret).utf8))
        if saved.status == -1 { throw KeyStoreError.toolUnavailable }
        // `security -i` exits 0 even when a command inside it fails: confirm by reading back.
        guard saved.status == 0, try read() == secret else { throw KeyStoreError.notSaved(hint: Self.clip(saved.error)) }
    }

    public func forget() throws {
        let removed = Self.run(["delete-generic-password", "-s", Self.service, "-a", Self.account])
        guard removed.status == 0 || removed.status == 44 else { throw KeyStoreError.notRemoved(hint: Self.clip(removed.error)) }
    }

    /// The line `security -i` reads: the secret as hex, so no quoting can break it.
    static func addCommand(service: String, account: String, secret: Secret) -> String {
        let hex = Data(secret.value.utf8).map { String(format: "%02x", $0) }.joined()
        return "add-generic-password -U -s \(service) -a \(account) -l \(service).\(account) -X \(hex)\n"
    }

    static func run(_ arguments: [String], input: Data? = nil) -> (status: Int32, output: Data, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe(), error = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = stdin
        do { try process.run() } catch { return (-1, Data(), "\(error)") }
        if let input { stdin.fileHandleForWriting.write(input) }
        try? stdin.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, out, String(decoding: err, as: UTF8.self))
    }

    static func clip(_ text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : String(line.prefix(200))
    }
}

/// A key store in memory, for tests.
public final class MemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: Secret?

    public init(_ secret: Secret? = nil) { self.secret = secret }
    public func read() throws -> Secret? { lock.withLock { secret } }
    public func write(_ value: Secret) throws { lock.withLock { secret = value } }
    public func forget() throws { lock.withLock { secret = nil } }
}

public struct KeyResolver: Sendable {
    public let store: any KeyStore
    public let environment: [String: String]

    public init(store: any KeyStore, environment: [String: String]) {
        self.store = store; self.environment = environment
    }

    public static func live() -> KeyResolver {
        KeyResolver(store: KeychainKeyStore(), environment: ProcessInfo.processInfo.environment)
    }

    public func resolve() -> ResolvedKey? {
        if let secret = try? store.read() { return ResolvedKey(secret: secret, source: .keychain) }
        if let secret = environment["ANTHROPIC_API_KEY"].flatMap(Secret.init) { return ResolvedKey(secret: secret, source: .environment) }
        return nil
    }
}
