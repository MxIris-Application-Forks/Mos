//
//  ScrollAccumulator.swift
//  Mos
//  单轴滚动距离累积器, 把离散的滚轮输入转换为逐帧的平滑位移
//  Created by Mx-Iris on 2026/9/1.
//

import Foundation

/// 单轴的滚动距离累积器
///
/// 滚轮输入是离散事件, 每次 tick 都会让待滚动的距离突然增加, 直接并入缓冲区会让插值输出出现速度台阶.
/// 这里按输入的来源区分处理:
///
/// - 从静止起步, 或滚动途中反向: 增量全额写入缓冲区, 首帧即刻全额响应, 不做任何平滑.
/// - 同向的后续增量: 先存入待注入池, 再逐帧按固定比例释放进缓冲区, 把台阶抹成斜坡.
///
/// 这样起步跟手与滚动平滑不再互相牺牲 —— 平滑只作用在滚动途中的跳变上, 而不像在输出侧做滤波那样,
/// 把起步的阶跃当成噪声一并磨掉.
///
/// 分摊强度对所有同向输入一视同仁, 不随手速变化. 曾经试过让它随输入密集程度自适应 (滚得越急越少分摊),
/// 起步阻力确实更小, 但滚动会变得一顿一顿 —— 密集输入少分摊等于把速度纹波放了回来.
/// 详见提案 scroll-startup-resistance 的决策日志.
struct ScrollAccumulator {

    /// 每帧从待注入池释放进缓冲区的比例
    ///
    /// 取值越小纹波越低, 但滚动途中加速的响应越钝. 0.25 在实测中让三档滚动速度的纹波
    /// (快 4.0% / 中 6.1% / 慢 18.5%) 全面低于原先的输出侧滤波, 同时把途中 tick 的响应
    /// 控制在 4 帧以内.
    static let defaultInjectionRate = 0.25

    /// 本次滚动的目标距离
    private(set) var buffer = 0.0
    /// 已经输出的距离
    private(set) var current = 0.0
    /// 等待逐帧释放进缓冲区的距离
    private(set) var pendingInjection = 0.0
    /// 最近一帧输出的距离, 用于收敛判断
    private(set) var mostRecentFrame = 0.0

    /// 上一次输入的方向, 用于判断本次输入是否与当前滚动同向
    private var previousDelta = 0.0
    private let injectionRate: Double

    init(injectionRate: Double = ScrollAccumulator.defaultInjectionRate) {
        self.injectionRate = injectionRate
    }
}

// MARK: - 输入
extension ScrollAccumulator {
    /// 接收一次滚轮输入
    /// - Parameters:
    ///   - delta: 滚轮原始增量, 其符号决定滚动方向
    ///   - scale: 作用在增量上的倍率, 即滚动速度与加速倍数的乘积
    mutating func accept(delta: Double, scaledBy scale: Double) {
        let distance = delta * scale
        if delta * previousDelta > 0 {
            // 同向滚动: 交给待注入池逐帧释放, 避免缓冲区跳变造成速度台阶
            pendingInjection += distance
        } else {
            // 从静止起步或反向滚动: 全额写入, 保证首帧即刻响应
            buffer = distance
            current = 0.0
            pendingInjection = 0.0
        }
        previousDelta = delta
    }
}

// MARK: - 推进
extension ScrollAccumulator {
    /// 推进一帧, 返回本帧应当输出的滚动距离
    /// - Parameter transition: 线性插值系数, 由滚动时长换算而来
    mutating func advance(transition: Double) -> Double {
        // 先释放一部分待注入距离, 再插值, 使途中的 tick 表现为缓慢抬升而非瞬时台阶
        let injection = pendingInjection * injectionRate
        buffer += injection
        pendingInjection -= injection
        let frame = Interpolator.lerp(src: current, dest: buffer, trans: transition)
        current += frame
        mostRecentFrame = frame
        return frame
    }

    /// 本轴是否已经收敛到可以停止
    ///
    /// 待注入池必须一并纳入判断, 否则尚未释放的距离会随停止被丢弃, 表现为滚动比预期短.
    func hasSettled(within precision: Double) -> Bool {
        return mostRecentFrame.magnitude <= precision && pendingInjection.magnitude <= precision
    }
}

// MARK: - 中止
extension ScrollAccumulator {
    /// 刹车: 放弃剩余距离, 停在当前位置
    mutating func brake() {
        buffer = current
        pendingInjection = 0.0
    }

    /// 重置到静止状态
    mutating func reset() {
        buffer = 0.0
        current = 0.0
        pendingInjection = 0.0
        mostRecentFrame = 0.0
        previousDelta = 0.0
    }
}
