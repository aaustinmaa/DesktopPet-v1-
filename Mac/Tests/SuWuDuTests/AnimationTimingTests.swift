import Foundation
import Testing
@testable import SuWuDu

struct AnimationTimingTests {
    @Test func discreteTimelinePreservesEveryHoldIncludingTheLastFrame() throws {
        let spec = AnimationSpec(frames: ["rest", "closed", "open"], interval: 0.32,
                                 frameDurations: [16, 0.08, 0.32])
        let times = try #require(spec.keyTimes)
        let holds = try #require(spec.frameDurations)
        #expect(times.count == spec.frames.count + 1)
        #expect(times.first == 0)
        #expect(times.last == 1)
        for index in holds.indices {
            #expect(abs((times[index + 1] - times[index]) * spec.duration - holds[index]) < 0.000001)
        }
    }

    @Test func quietLoopsKeepBriefBlinksAndSpendMostTimeResting() throws {
        for state in [PetState.idle, .working] {
            let spec = AnimationSpec.make(state, skin: "shenqing")
            let holds = try #require(spec.frameDurations)
            #expect(holds.count == spec.frames.count)
            #expect(holds.allSatisfy { $0 > 0 })
            #expect(holds[0] > spec.duration / 2)
            let closedIndices = state == .idle ? [6, 7] : [3, 4]
            #expect(closedIndices.reduce(0) { $0 + holds[$1] } < 0.2)
        }
        let working = AnimationSpec.make(.working, skin: "shenqing")
        #expect(!working.frames.contains("shenqing-working-15.png"))
        #expect(working.frames.last == "shenqing-working-16.png")
        #expect(working.duration > AnimationSpec.make(.idle, skin: "shenqing").duration)
    }

    @Test func standaloneBlinkRetainsItsOriginalOnceOnlyCadence() {
        let blink = AnimationSpec.make(.blink, skin: "shenqing")
        #expect(blink.once)
        #expect(blink.frameDurations == nil)
        #expect(blink.interval == 0.08)
        #expect(abs(blink.duration - 1.28) < 0.000001)
    }
}
