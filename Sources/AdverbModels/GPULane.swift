//
//  GPULane.swift
//  AdverbModels
//
//  WHAT: One generation at a time on this Mac's GPU, process-wide: two days written side by side
//        take turns on the model (decoding beside another only splits the bandwidth), while their
//        stills, sheets and renders overlap.
//

import Foundation

public actor GPULane {
    public static let shared = GPULane()

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await body()
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}
