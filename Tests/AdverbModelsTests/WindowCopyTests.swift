import Foundation
import Testing
import FrigateParallel
import MLX
import MLXLMCommon
@testable import AdverbModels

/// A sliding-window layer that has wrapped cannot be trimmed: a rewind to the pin restores the copy
/// taken there, and the cache then reads on exactly as one that never went past the pin.
@Suite struct WindowCopyTests {
    static func tokens(_ count: Int, from start: Int) -> (MLXArray, MLXArray) {
        let k = (MLXArray(start ..< (start + count)).asType(.float32).reshaped([1, 1, count, 1]) * MLXArray.ones([1, 2, 1, 4]))
        return (k, k + 1000)
    }

    static func feed(_ layers: [KVCache], _ count: Int, from start: Int) {
        let (k, v) = tokens(count, from: start)
        for layer in layers { _ = layer.update(keys: k, values: v) }
        eval(layers.flatMap(\.state))
    }

    @Test func aRewindPastTheWindowRestoresThePin() {
        let window = RotatingKVCache(maxSize: 8, keep: 0)
        let cache = CheckpointedCache(layers: [window, KVCacheSimple()])
        Self.feed(cache.layers, 12, from: 0)                     // past the window: it has wrapped
        let copy = try! #require(WindowCopy.take(cache.layers, at: 12))
        let pinned = window.state.map { $0 * 1 }; eval(pinned)
        let pinnedMeta = window.metaState

        Self.feed(cache.layers, 5, from: 12)                      // the next request
        for t in 17 ..< 20 { Self.feed(cache.layers, 1, from: t) } // and its answer
        #expect(cache.position == 20)

        #expect(cache.rewind(toAtMost: 12) == 12)
        copy.restore(into: cache.layers)
        #expect(window.metaState == pinnedMeta)
        #expect(zip(window.state, pinned).allSatisfy { arrayEqual($0, $1).item(Bool.self) })

        // Read on from the pin, beside a cache that stopped there: the same keys come back.
        let reference = RotatingKVCache(maxSize: 8, keep: 0)
        Self.feed([reference], 12, from: 0)
        let (k, v) = Self.tokens(6, from: 40)
        let (rk, _) = reference.update(keys: k, values: v)
        let (wk, _) = window.update(keys: k, values: v)
        #expect(arrayEqual(rk, wk).item(Bool.self))
        #expect(window.metaState == reference.metaState)

        // The copy is still good for the next rewind.
        Self.feed(cache.layers, 3, from: 46)
        #expect(cache.rewind(toAtMost: 12) == 12)
        copy.restore(into: cache.layers)
        #expect(window.metaState == pinnedMeta)
        #expect(zip(window.state, pinned).allSatisfy { arrayEqual($0, $1).item(Bool.self) })
    }

    /// A pin exactly at the window: the next one-token step writes into the array it holds, which
    /// must not be the copy's.
    @Test func aStepAfterARestoreLeavesTheCopyAlone() {
        let window = RotatingKVCache(maxSize: 8, keep: 0)
        let cache = CheckpointedCache(layers: [window])
        Self.feed(cache.layers, 4, from: 0)
        Self.feed(cache.layers, 4, from: 4)
        let copy = try! #require(WindowCopy.take(cache.layers, at: 8))
        let pinned = window.state.map { $0 * 1 }; eval(pinned)
        for round in 0 ..< 2 {
            Self.feed(cache.layers, 1, from: 100 + round)       // written in place, over token 0
            #expect(cache.rewind(toAtMost: 8) == 8)
            copy.restore(into: cache.layers)
            #expect(zip(window.state, pinned).allSatisfy { arrayEqual($0, $1).item(Bool.self) })
        }
    }

    @Test func aCacheWithoutWindowsTakesNoCopy() {
        let layers: [KVCache] = [KVCacheSimple(), KVCacheSimple()]
        Self.feed(layers, 4, from: 0)
        #expect(WindowCopy.take(layers, at: 4) == nil)
        #expect(!WindowCopy.hasWindows(layers))
    }
}
