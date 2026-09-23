//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa
import os

class ScrollPoster {

    // 单例
    static let shared = ScrollPoster()
    init() { NSLog("Module initialized: ScrollPoster") }

    // 发送器
    private var poster: CVDisplayLink?
    // 滚动数据
    private var verticalAccumulator = ScrollAccumulator()
    private var horizontalAccumulator = ScrollAccumulator()
    // 滚动配置
    private var shifting = false
    private var duration = Options.shared.scrollAdvanced.durationTransition
    // 外部依赖 (主事件 Tap 线程写入, CVDisplayLink IO 线程读取, 必须加锁防止跨线程 CGEvent 释放与 retain 的竞争)
    private let refLock = OSAllocatedUnfairLock<(event: CGEvent?, proxy: CGEventTapProxy?)>(initialState: (event: nil, proxy: nil))
    private func snapshotRef() -> (event: CGEvent?, proxy: CGEventTapProxy?) {
        refLock.withLock { $0 }
    }
    private func setRef(_ newValue: (event: CGEvent?, proxy: CGEventTapProxy?)) {
        refLock.withLock { $0 = newValue }
    }
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, proxy: CGEventTapProxy, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        // 更新依赖数据
        setRef((event: event, proxy: proxy))
        // 更新滚动配置
        self.duration = duration
        // 更新滚动数据
        let scale = speed * amplification
        verticalAccumulator.accept(delta: y, scaledBy: scale)
        horizontalAccumulator.accept(delta: x, scaledBy: scale)
        return self
    }
    func updateShifting(enable: Bool) {
        shifting = enable
    }
    func shift(with nextValue: ( y: Double, x: Double )) -> (y: Double, x: Double) {
        // 如果按下 Shift, 则始终将滚动转为横向
        if shifting {
            // 判断哪个轴有值, 有值则赋给 X
            // 某些鼠标 (MXMaster/MXAnywhere), 按下 Shift 后会显式转换方向为横向, 此处针对这类转换进行归一化处理
            if nextValue.y != 0.0 && nextValue.x == 0.0 {
                return (y: nextValue.x, x: nextValue.y)
            } else {
                return (y: nextValue.y, x: nextValue.x)
            }
        } else {
            return (y: nextValue.y, x: nextValue.x)
        }
    }
    func brake() {
        verticalAccumulator.brake()
        horizontalAccumulator.brake()
    }
    func reset() {
        // 重置数值
        setRef((event: nil, proxy: nil))
        verticalAccumulator.reset()
        horizontalAccumulator.reset()
    }
}

// MARK: - 插值数据发送控制
extension ScrollPoster {
    // 初始化 CVDisplayLink
    func create() {
        // 新建一个 CVDisplayLinkSetOutputCallback 来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&poster)
        if let validPoster = poster {
            CVDisplayLinkSetOutputCallback(validPoster, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
                ScrollPoster.shared.processing()
                return kCVReturnSuccess
            }, nil)
        }
    }
    // 启动事件发送器
    func tryStart() {
        if let validPoster = poster {
            if !CVDisplayLinkIsRunning(validPoster) {
                CVDisplayLinkStart(validPoster)
            }
        }
    }
    // 停止事件发送器
    func stop(_ phase: Phase = Phase.PauseManual) {
        // 停止循环
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
        }
        // 先设置阶段为停止
        ScrollPhase.shared.stop(phase)
        // 对于 Phase.PauseAuto, 我们在结束前额外发送一个事件来重置 Chrome 的滚动缓冲区
        let snapshot = snapshotRef()
        if let validEvent = snapshot.event, ScrollUtils.shared.isEventTargetingChrome(validEvent) {
            // 需要附加特定的阶段数据, 只有 Phase.PauseManual 对应的 [4.0, 0.0] 可以正确使 Chrome 恢复
            validEvent.setDoubleValueField(.scrollWheelEventScrollPhase, value: PhaseValueMapping[Phase.PauseManual]![PhaseItem.Scroll]!)
            validEvent.setDoubleValueField(.scrollWheelEventMomentumPhase, value: PhaseValueMapping[Phase.PauseManual]![PhaseItem.Momentum]!)
            post(snapshot, (y: 0.0, x: 0.0))
        }
        // 重置参数
        reset()
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
    // 处理滚动事件
    func processing() {
        // 推进一帧, 累积器内部完成待注入距离的释放与插值
        let frame = (
            y: verticalAccumulator.advance(transition: duration),
            x: horizontalAccumulator.advance(transition: duration)
        )
        // 变换滚动结果
        let shiftedValue = shift(with: frame)
        // 发送滚动结果 (使用快照, 避免与主线程的 update/reset 竞争)
        post(snapshotRef(), shiftedValue)
        // 如果两轴都已收敛到精确度门限内则暂停滚动
        let precision = Options.shared.scrollAdvanced.precision
        if (
            verticalAccumulator.hasSettled(within: precision) &&
            horizontalAccumulator.hasSettled(within: precision)
        ) {
            stop(Phase.PauseAuto)
        }
    }
    func post(_ r: (event: CGEvent?, proxy: CGEventTapProxy?), _ v: (y: Double, x: Double)) {
        if let proxy = r.proxy, let eventClone = r.event?.copy() {
            // 设置阶段数据
            ScrollPhase.shared.transfrom()
            // 设置滚动数据
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            // EventTapProxy 标识了 EventTapCallback 在事件流中接收到事件的特定位置, 其粒度小于 tap 本身
            // 使用 tapPostEvent 可以将自定义的事件发布到 proxy 标识的位置, 避免被 EventTapCallback 本身重复接收或处理
            // 新发布的事件将早于 EventTapCallback 所处理的事件进入系统, 也如同 EventTapCallback 所处理的事件, 会被所有后续的 EventTap 接收
            eventClone.tapPostEvent(proxy)
        }
    }
}
