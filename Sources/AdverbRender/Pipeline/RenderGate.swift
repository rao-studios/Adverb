//
//  RenderGate.swift
//  AdverbRender
//
//  WHAT: One render at a time. Builders write pages with Claude side by side, but rendering is
//        CPU-bound: two at once take as long as two in a row and make both late. Stills and
//        probes skip the gate; they are quick.
//

import Foundation

public actor RenderGate {
    public static let shared = RenderGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await work()
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}
