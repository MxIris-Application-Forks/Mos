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

    @Test("滚动途中反向时首帧立即掉头")
    func reversalRespondsImmediately() {
        var accumulator = ScrollAccumulator()
        accumulator.accept(delta: 1.0, scaledBy: 100.0)
        _ = accumulator.advance(transition: 0.2)
        _ = accumulator.advance(transition: 0.2)
        accumulator.accept(delta: -1.0, scaledBy: 100.0)
        // 反向等同于重新起步: 首帧就应当是完整的 -20, 而不是先减速再掉头
        #expect(accumulator.advance(transition: 0.2).isApproximately(-20.0))
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
