import Foundation
import Testing
@testable import SuWuDu

struct AnimationTimingTests {
    @Test func discreteTimelinePreservesEveryHoldIncludingTheLastFrame() throws {
        let spec = AnimationSpec(frames: ["rest", "closed", "open"], interval: 0.06,
                                 frameDurations: [0.06, 0.15, 0.08])
        let times = try #require(spec.keyTimes)
        let holds = try #require(spec.frameDurations)
        #expect(times.count == spec.frames.count + 1)
        #expect(times.first == 0)
        #expect(times.last == 1)
        for index in holds.indices {
            #expect(abs((times[index + 1] - times[index]) * spec.duration - holds[index]) < 0.000001)
        }
    }

    @Test func smallIdleAndWorkingMovementsPlayContinuouslyWithoutFrozenHolds() {
        for state in [PetState.idle, .working] {
            let spec = AnimationSpec.make(state, skin: "shenqing")
            #expect(spec.frameDurations == nil)
            #expect(spec.frames.count == 16)
            #expect(spec.interval > 0 && spec.interval <= 0.16)
            #expect(!spec.once)
        }
        let working = AnimationSpec.make(.working, skin: "shenqing")
        #expect(working.frames.contains("shenqing-working-15.png"))
        #expect(working.frames.last == "shenqing-working-16.png")
    }

    @Test func hitRaisesTheHeartBeforeHammerImpactAndClosesEyesOnlyOnce() throws {
        let spec = AnimationSpec.make(.hit, skin: "shenqing")
        let holds = try #require(spec.frameDurations)
        let poses = spec.frames.map { Int($0.split(separator: "-").last!.prefix(2))! }
        #expect(spec.once)
        #expect(spec.duration < 1.2)
        #expect(holds.count == poses.count)
        let raised = try #require(poses.firstIndex(of: 5))
        #expect(holds.prefix(raised).reduce(0, +) <= 0.25)
        var elapsed = 0.0
        var closedEpisodes = 0
        var wasClosed = false
        for (index, pose) in poses.enumerated() {
            let closed = (3...7).contains(pose)
            if closed && !wasClosed { closedEpisodes += 1 }
            wasClosed = closed
            if elapsed <= 0.43 && elapsed + holds[index] > 0.43 {
                #expect((5...7).contains(pose))
            }
            elapsed += holds[index]
        }
        #expect(closedEpisodes == 1)
        #expect(!poses.contains { (8...15).contains($0) })
        #expect(poses.last == 16)
    }

    @Test func standaloneBlinkRetainsItsOriginalOnceOnlyCadence() {
        let blink = AnimationSpec.make(.blink, skin: "shenqing")
        #expect(blink.once)
        #expect(blink.frameDurations == nil)
        #expect(blink.interval == 0.08)
        #expect(abs(blink.duration - 1.28) < 0.000001)
    }
}
