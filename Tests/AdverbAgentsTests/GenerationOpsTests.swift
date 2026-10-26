import Foundation
import Testing
@testable import AdverbAgents
@testable import AdverbCore

@Suite struct GenerationOpsTests {
    @Test func runKeysRoundTrip() {
        let id = UUID()
        #expect(RunKey.parse(RunKey.plan(id)).campaign == id)
        #expect(RunKey.parse(RunKey.build(id, 7)).day == 7)
        #expect(RunKey.parse(RunKey.beat(id, 3)).kind == "Beatmap")
    }

    @Test func eventsFoldIntoARun() {
        var state = GenerationService.Center.State()
        let id = UUID()
        let key = RunKey.build(id, 2)
        GenerationOps.lifecycle(.running, message: nil, key: key, to: &state)
        GenerationOps.event(.step("Writing the page"), key: key, to: &state)
        GenerationOps.event(.activity("Thinking about "), key: key, to: &state)
        GenerationOps.event(.activity("the fog."), key: key, to: &state)
        GenerationOps.event(.progress(0.4), key: key, to: &state)
        #expect(state.runs[key]?.step == "Writing the page")
        #expect(state.runs[key]?.activity == "Thinking about the fog.")
        #expect(state.isBusy(id))
        GenerationOps.event(.dayDone(2), key: key, to: &state)
        #expect(state.revisions[id] == 1)
        GenerationOps.lifecycle(.failed, message: "boom", key: key, to: &state)
        #expect(state.runs[key]?.phase == .failed)
        #expect(state.runs[key]?.message == "boom")
        #expect(!state.isBusy(id))
        GenerationOps.apply(.clearEnded, to: &state)
        #expect(state.runs.isEmpty)
    }

    @Test func coalescingFoldsActivity() {
        #expect(AgentStream.coalesce(.activity("a"), .activity("b")) == .activity("ab"))
        #expect(AgentStream.coalesce(.progress(0.1), .progress(0.2)) == .progress(0.2))
        #expect(AgentStream.coalesce(.step("a"), .step("b")) == nil)
    }

    @Test func gridAdjustments() {
        let grid = BeatGrid(bpm: 120, confidence: 1, beats: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4], downbeats: [0, 2, 4], duration: 4)
        let double = grid.adjusted(octave: 2, phaseNudge: 0)
        #expect(double.bpm == 240)
        #expect(double.beats.count == 17)
        let half = grid.adjusted(octave: 0.5, phaseNudge: 0)
        #expect(half.beats == [0, 1, 2, 3, 4])
        let nudged = grid.adjusted(octave: 1, phaseNudge: 1)
        #expect(nudged.downbeats == [0.5, 2.5])
    }
}
