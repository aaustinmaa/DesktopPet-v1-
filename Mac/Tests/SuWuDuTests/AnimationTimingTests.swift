import AppKit
import Foundation
import QuartzCore
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
        for (state, interval) in [(PetState.idle, 0.170), (.working, 0.120)] {
            let spec = AnimationSpec.make(state, skin: "shenqing")
            #expect(spec.frameDurations == nil)
            #expect(spec.frames.count == 16)
            #expect(Set(spec.frames).count == 16)
            #expect(spec.interval == interval)
            #expect(!spec.once)
        }
        let working = AnimationSpec.make(.working, skin: "shenqing")
        #expect(working.frames.contains("shenqing-working-15.png"))
        #expect(working.frames.last == "shenqing-working-16.png")
    }

    @Test func waveUsesEveryFrameOncePerLoopWithoutFrozenHolds() {
        let spec = AnimationSpec.make(.waving, skin: "shenqing")
        #expect(spec.frames == (1...16).map { String(format: "shenqing-wave-%02d.png", $0) })
        #expect(Set(spec.frames).count == 16)
        #expect(spec.frameDurations == nil)
        #expect(spec.interval == 0.120)
        #expect(abs(spec.duration - 1.92) < 0.000001)
        #expect(!spec.once)
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

    @Test func sleepingKeepsOneStillBasePose() {
        let spec = AnimationSpec.make(.sleeping, skin: "shenqing")
        #expect(spec.frames == ["shenqing-sleeping-base.png"])
        #expect(spec.frameDurations == nil)
        #expect(!spec.once)
    }

    @Test @MainActor func sleepGlyphsOffsetMirroredPositionsAndKeepMirroredMotionForShenQing() throws {
        let original = PetView(frame: NSRect(x: 0, y: 0, width: 362, height: 362))
        let mirrored = PetView(frame: original.frame)
        for (view, skin) in [(original, "suwudu"), (mirrored, "shenqing")] {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            view.play(.sleeping, skin: skin)
            view.layoutSubtreeIfNeeded()
        }
        let originalGlyphs = try #require(original.layer?.sublayers)
            .filter { $0.animation(forKey: "sleep") != nil }
        let mirroredGlyphs = try #require(mirrored.layer?.sublayers)
            .filter { $0.animation(forKey: "sleep") != nil }
        #expect(originalGlyphs.count == 3)
        #expect(mirroredGlyphs.count == 3)
        for (right, left) in zip(originalGlyphs, mirroredGlyphs) {
            #expect(abs(left.frame.minX - (362 - right.frame.maxX - 20)) < 0.000001)
            #expect(left.frame.minY == right.frame.minY - 30)
            #expect(left.frame.size == right.frame.size)
            let rightGroup = try #require(right.animation(forKey: "sleep") as? CAAnimationGroup)
            let leftGroup = try #require(left.animation(forKey: "sleep") as? CAAnimationGroup)
            #expect(leftGroup.duration == 10)
            #expect(leftGroup.duration == rightGroup.duration)
            #expect(leftGroup.repeatCount == .infinity)
            let rightX = try #require(rightGroup.animations?.compactMap { $0 as? CAKeyframeAnimation }
                .first { $0.keyPath == "transform.translation.x" })
            let leftX = try #require(leftGroup.animations?.compactMap { $0 as? CAKeyframeAnimation }
                .first { $0.keyPath == "transform.translation.x" })
            #expect(leftX.keyTimes == rightX.keyTimes)
            let rightValues = try #require(rightX.values as? [NSNumber])
            let leftValues = try #require(leftX.values as? [NSNumber])
            #expect(leftValues.count == rightValues.count)
            for (rightValue, leftValue) in zip(rightValues, leftValues) {
                #expect(abs(leftValue.doubleValue + rightValue.doubleValue) < 0.000001)
            }
        }
        mirrored.play(.sleeping, skin: "suwudu")
        for (originalGlyph, restoredGlyph) in zip(originalGlyphs, mirroredGlyphs) {
            #expect(restoredGlyph.frame == originalGlyph.frame)
        }
        mirrored.play(.idle, skin: "shenqing")
        #expect(mirroredGlyphs.allSatisfy { $0.animation(forKey: "sleep") == nil })
    }

    @Test func standaloneBlinkRetainsItsOriginalOnceOnlyCadence() {
        let blink = AnimationSpec.make(.blink, skin: "shenqing")
        #expect(blink.once)
        #expect(blink.frameDurations == nil)
        #expect(blink.interval == 0.08)
        #expect(abs(blink.duration - 1.28) < 0.000001)
    }
}
