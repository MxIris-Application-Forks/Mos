//
//  ScrollAccumulatorTests.swift
//  MosTests
//
//  Created by Mx-Iris on 2026/9/1.
//

// ScrollAccumulator 与 Interpolator 直接编译进本 target, 因此不需要宿主应用:
// 跑测试不会启动 Mos, 也就不会去装事件拦截或请求辅助功能权限.
import Testing

@Suite("滚动距离累积器")
struct ScrollAccumulatorTests {

    /// 推进到收敛, 返回累计输出的距离与消耗的帧数
    private func drain(
        _ accumulator: inout ScrollAccumulator,
        transition: Double,
        precision: Double = 0.0001,
        frameLimit: Int = 10_000
    ) -> (distance: Double, frames: Int) {
        var distance = 0.0
        var frames = 0
        while frames < frameLimit {
            distance += accumulator.advance(transition: transition)
            frames += 1
            if accumulator.hasSettled(within: precision) { break }
        }
        return (distance, frames)
    }

    // MARK: - 起步

    @Test("从静止起步的首帧全额响应, 不被平滑削减")
    func startsAtFullSpeed() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        // 目标距离 100, 插值系数 0.2, 首帧理应滚满 20 —— 没有任何起步衰减
        #expect(accumulator.advance(transition: 0.2).isApproximately(20.0))
    }

    @Test("起步阶段严格贴合无平滑的理想插值曲线")
    func startupCurveMatchesIdealInterpolation() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        // 理想曲线是公比 (1 - 0.2) 的等比数列: 20, 16, 12.8, 10.24, 8.192
        let expectedCurve = [20.0, 16.0, 12.8, 10.24, 8.192]
        for expectedFrame in expectedCurve {
            #expect(accumulator.advance(transition: 0.2).isApproximately(expectedFrame))
        }
    }

    // MARK: - 滚动途中

    @Test("滚动途中的同向增量不会在一帧内全额生效", arguments: [1, 10])
    func midScrollIncrementIsSpreadAcrossFrames(gapFrames: Int) {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        for _ in 0..<gapFrames { _ = accumulator.advance(transition: 0.2) }
        // 分摊强度对所有同向输入一致, 不随两格之间隔了多久而变 ——
        // 让它随手速自适应会把速度纹波放回来, 滚起来一顿一顿的
        let fullInjectionFrame = (accumulator.buffer - accumulator.current + 100.0) * 0.2
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        #expect(accumulator.advance(transition: 0.2) < fullInjectionFrame)
    }

    @Test("滚动途中新增的距离最终一分不少地滚完", arguments: [1, 10])
    func midScrollIncrementIsFullyDelivered(gapFrames: Int) {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        var deliveredBeforeSecondInput = 0.0
        for _ in 0..<gapFrames { deliveredBeforeSecondInput += accumulator.advance(transition: 0.2) }
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        let result = drain(&accumulator, transition: 0.2)
        // 无论两格挨得多近, 累计输出都应当等于两次输入的总距离 200
        #expect((result.distance + deliveredBeforeSecondInput).isApproximately(200.0, tolerance: 0.01))
    }

    @Test("单次滚动的总位移等于输入距离")
    func totalDistanceIsConserved() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        let result = drain(&accumulator, transition: 0.2)
        #expect(result.distance.isApproximately(100.0, tolerance: 0.01))
    }

    // MARK: - 反向

    @Test("连续两格反向即确认换向, 与从静止起步拨出这两格表现一致")
    func confirmedReversalBehavesLikeFreshStart() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        _ = accumulator.advance(transition: 0.2)
        accumulator.accept(delta: -1.0, scaledBy: 100.0)
        accumulator.accept(delta: -1.0, scaledBy: 100.0)
        // 第一格反向按起步全额写入, 第二格进入待注入池并在本帧释放 25%: 0.2 × (100 + 25) = 25.
        // 不先减速再掉头, 也不吞掉被暂扣的第一格
        #expect(accumulator.advance(transition: 0.2).isApproximately(-25.0))
    }

    @Test("没有输入的轴传入 0 时, 暂扣的反向输入不会因此生效")
    func zeroInputDoesNotConfirmReversal() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        _ = accumulator.advance(transition: 0.2)
        accumulator.accept(delta: -1.0, scaledBy: 100.0)
        // ScrollPoster 每次都会更新两个轴, 只有另一轴有输入时本轴收到的就是 0, 这不是换向的证据
        accumulator.accept(delta: 0.0, scaledBy: 100.0)
        #expect(accumulator.advance(transition: 0.2) >= 0.0)
    }

    // MARK: - 滚轮回弹

    /// 实机录制的一段滚轮输入 (SteelSeries Rival 650, macOS 26.7, 60 Hz 显示器, 速度 3, 平滑时长 3.9)
    ///
    /// 数值是 ScrollCore 按步长 35 归一化之后交给累积器的增量, 符号取设备的原始方向 ——
    /// Mos 的反转选项只是整体翻转符号, 不改变累积器的行为. 录制方法与分析见提案 wheel-rebound-reversal.
    struct RecordedWheelInput: CustomTestStringConvertible, Sendable {
        enum Step: Sendable {
            /// 一格滚轮输入
            case tick(Double)
            /// 下一格输入到来之前 Mos 推进的帧数
            case frames(Int)
        }

        static let scale = 3.0
        static let transition = 0.134

        let testDescription: String
        /// 用户实际在拨的方向
        let scrollDirection: Double
        /// 只把朝 scrollDirection 的输入相加再乘以速度得到的距离, 夹杂的反向输入不计
        let intendedDistance: Double
        let steps: [Step]

        /// 拨到头时滚轮往回跳了一格, 被 macOS 的滚动加速放大到 -50, 之后停顿约 230 ms 才开始下一次拨动
        static let reboundAtEndOfFlick = RecordedWheelInput(
            testDescription: "拨到头时往回跳的一格",
            scrollDirection: 1.0,
            intendedDistance: (35 + 35 + 52 + 35 + 35 + 57 + 76) * 3,
            steps: [
                .tick(35), .tick(35), .frames(2), .tick(52), .frames(1), .tick(-50), .frames(14),
                .tick(35), .tick(35), .frames(1), .tick(57), .tick(76),
            ]
        )

        /// 一次拨动的中途夹进一格反向输入, 紧接着又回到原方向
        static let strayTickWithinFlick = RecordedWheelInput(
            testDescription: "拨动途中夹进的一格",
            scrollDirection: -1.0,
            intendedDistance: (35 + 35 + 55 + 56) * 3,
            steps: [
                .tick(-35), .frames(1), .tick(-35), .tick(59), .frames(1), .tick(-55), .tick(-56),
            ]
        )

        /// 连续两次拨动, 各夹进一格反向输入: 第一格在拨动途中, 第二格在上一次滑行还没停时的下一次拨动开头
        static let strayTicksAcrossFlicks = RecordedWheelInput(
            testDescription: "相邻两次拨动各夹进一格",
            scrollDirection: -1.0,
            intendedDistance: (35 + 60 + 59 + 91 + 99 + 103 + 56 + 57 + 87) * 3,
            steps: [
                .tick(-35), .frames(1), .tick(51), .frames(1), .tick(-60), .tick(-59), .tick(-91), .frames(1),
                .tick(-99), .frames(3), .tick(-103), .frames(11),
                .tick(35), .frames(1), .tick(-56), .tick(-57), .frames(1), .tick(-87),
            ]
        )
    }

    /// 按录制时的顺序把输入交给累积器, 再推进到收敛, 返回每一帧的输出
    private func replay(_ recording: RecordedWheelInput) -> [Double] {
        var accumulator = ScrollAccumulator()
        var frames: [Double] = []
        for step in recording.steps {
            switch step {
            case .tick(let delta):
                accumulator.accept(delta: delta, scaledBy: RecordedWheelInput.scale)
            case .frames(let frameCount):
                for _ in 0..<frameCount {
                    frames.append(accumulator.advance(transition: RecordedWheelInput.transition))
                }
            }
        }
        while frames.count < 10_000 {
            frames.append(accumulator.advance(transition: RecordedWheelInput.transition))
            if accumulator.hasSettled(within: 0.0001) { break }
        }
        return frames
    }

    @Test("滚动途中夹进的单格反向输入不会让画面往回滚", arguments: [
        RecordedWheelInput.reboundAtEndOfFlick,
        RecordedWheelInput.strayTickWithinFlick,
        RecordedWheelInput.strayTicksAcrossFlicks,
    ])
    func strayOppositeTickDoesNotScrollBackward(recording: RecordedWheelInput) {
        let backwardFrames = replay(recording).filter { $0 * recording.scrollDirection < 0 }
        #expect(backwardFrames == [])
    }

    @Test("被当作回弹丢弃的反向输入不会吃掉已经拨出的距离", arguments: [
        RecordedWheelInput.reboundAtEndOfFlick,
        RecordedWheelInput.strayTickWithinFlick,
        RecordedWheelInput.strayTicksAcrossFlicks,
    ])
    func strayOppositeTickDoesNotShortenScroll(recording: RecordedWheelInput) {
        let deliveredDistance = replay(recording).reduce(0.0, +) * recording.scrollDirection
        #expect(deliveredDistance.isApproximately(recording.intendedDistance, tolerance: 0.01))
    }

    // MARK: - 收敛与中止

    @Test("待注入距离未释放完时不算收敛")
    func doesNotSettleWhilePendingInjectionRemains() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        let result = drain(&accumulator, transition: 0.2, precision: 1.0)
        #expect(accumulator.hasSettled(within: 1.0))
        // 收敛后再来一次同向输入, 待注入池重新填上, 收敛状态必须随之解除
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        #expect(!accumulator.hasSettled(within: 1.0))
        #expect(result.frames > 0)
    }

    @Test("刹车后立即停止且不再输出距离")
    func brakeStopsImmediately() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        _ = accumulator.advance(transition: 0.2)
        accumulator.brake()
        #expect(accumulator.advance(transition: 0.2).isApproximately(0.0))
        #expect(accumulator.hasSettled(within: 0.0001))
    }

    @Test("重置后表现得与全新的累积器一致")
    func resetRestoresStartupBehaviour() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        _ = accumulator.advance(transition: 0.2)
        accumulator.reset()
        // 重置清空了方向记录, 因此同向的下一次输入仍按起步处理, 首帧全额响应
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        #expect(accumulator.advance(transition: 0.2).isApproximately(20.0))
    }

    // MARK: - 注入速率

    @Test("注入速率越低, 孤立输入抬升得越平缓", arguments: [0.2, 0.25, 0.4, 1.0])
    func lowerInjectionRateRisesMoreGently(injectionRate: Double) {
        var accumulator = ScrollAccumulator(injectionRate: injectionRate)
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        for _ in 0..<10 { _ = accumulator.advance(transition: 0.2) }
        let fullInjectionFrame = (accumulator.buffer - accumulator.current + 100.0) * 0.2
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        let frame = accumulator.advance(transition: 0.2)
        // 速率 1.0 等于不分摊, 任何低于它的速率都必须更平缓
        if injectionRate < 1.0 {
            #expect(frame < fullInjectionFrame)
        } else {
            #expect(frame.isApproximately(fullInjectionFrame))
        }
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.000001) -> Bool {
        return (self - other).magnitude <= tolerance
    }
}
