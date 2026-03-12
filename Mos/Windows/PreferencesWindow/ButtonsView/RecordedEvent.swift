//
//  RecordedEvent.swift
//  Mos
//  按钮绑定数据结构, 包含三部分
//  - EventType: 事件类型枚举 (键盘/鼠标), 供 RecordedEvent 和 ScrollHotkey 共用
//  - ScrollHotkey: 滚动热键绑定, 仅存储类型和按键码
//  - RecordedEvent: 录制后的 CGEvent 事件的完整信息, 包含修饰键和展示组件
//  - ButtonBinding: 用于存储 RecordedEvent - SystemShortcut 的绑定关系
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - EventType
/// 事件类型枚举 - 键盘或鼠标
enum EventType: String, Codable {
    case keyboard = "keyboard"
    case mouse = "mouse"
}

// MARK: - ScrollHotkey
/// 滚动热键绑定 - 轻量结构，仅存储类型和按键码
/// 用于 ScrollingView 的 dash/toggle/block 热键配置
struct ScrollHotkey: Codable, Equatable {

    // MARK: - 数据字段
    let type: EventType
    let code: UInt16

    // MARK: - 初始化
    init(type: EventType, code: UInt16) {
        self.type = type
        self.code = code
    }

    init(from event: CGEvent) {
        // 键盘事件 (keyDown/keyUp) 或修饰键事件 (flagsChanged)
        if event.isKeyboardEvent || event.type == .flagsChanged {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
    }

    /// 从旧版 Int 格式迁移 (向后兼容)
    init?(legacyCode: Int?) {
        guard let code = legacyCode else { return nil }
        self.type = .keyboard
        self.code = UInt16(code)
    }

    // MARK: - 显示名称
    var displayName: String {
        switch type {
        case .keyboard:
            return KeyCode.keyMap[code] ?? "Key \(code)"
        case .mouse:
            return KeyCode.mouseMap[code] ?? "🖱\(code)"
        }
    }

    // MARK: - 事件匹配
    func matches(_ event: CGEvent, keyCode: UInt16, mouseButton: UInt16, isMouseEvent: Bool) -> Bool {
        switch type {
        case .keyboard:
            // 键盘按键或修饰键
            guard !isMouseEvent else { return false }
            return code == keyCode
        case .mouse:
            // 鼠标按键
            guard isMouseEvent else { return false }
            return code == mouseButton
        }
    }

    /// 是否为修饰键
    var isModifierKey: Bool {
        return type == .keyboard && KeyCode.modifierKeys.contains(code)
    }

    /// 获取修饰键掩码 (仅对键盘修饰键有效)
    var modifierMask: CGEventFlags {
        guard type == .keyboard else { return CGEventFlags(rawValue: 0) }
        return KeyCode.getKeyMask(code)
    }
}

// MARK: - RecordedEvent
/// 录制的事件数据 - 可序列化的事件信息 (完整版，包含修饰键)
struct RecordedEvent: Codable, Equatable {

    // MARK: - 数据字段
    let type: EventType // 事件类型
    let code: UInt16 // 按键代码
    let modifiers: UInt // 修饰键
    let displayComponents: [String] // 展示用名称组件

    // MARK: - 计算属性

    /// NSEvent.ModifierFlags 格式的修饰键
    var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// 转换为 ScrollHotkey (丢弃修饰键信息)
    var asScrollHotkey: ScrollHotkey {
        return ScrollHotkey(type: type, code: code)
    }

    // MARK: - INIT
    init(from event: CGEvent) {
        // 修饰键
        self.modifiers = UInt(event.flags.rawValue)
        // 根据事件类型匹配
        if event.isKeyboardEvent {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
        // 展示用名称
        self.displayComponents = event.displayComponents
    }

    // MARK: - 匹配方法
    /// 检查是否与给定的 CGEvent 匹配
    func matches(_ event: CGEvent) -> Bool {
        // Guard: 修饰键匹配
        guard event.flags.rawValue == modifiers else { return false }
        // 根据类型匹配
        switch type {
            case .keyboard:
                // Guard: 键盘事件 (这里只匹配 keyDown)
                guard event.type == .keyDown else { return false }
                // 匹配 code
                return code == Int(event.getIntegerValueField(.keyboardEventKeycode))
            case .mouse:
                // Guard: 鼠标事件
                guard event.type != .keyDown && event.type != .keyUp else { return false }
                // 匹配 code
                return code == Int(event.getIntegerValueField(.mouseEventButtonNumber))
        }
    }
    /// Equatable
    static func == (lhs: RecordedEvent, rhs: RecordedEvent) -> Bool {
        return lhs.type == rhs.type &&
               lhs.code == rhs.code &&
               lhs.modifiers == rhs.modifiers
    }
}

// MARK: - ButtonBinding
/// 按钮绑定 - 将录制的事件与系统快捷键关联
struct ButtonBinding: Codable, Equatable {

    // MARK: - 数据字段

    /// 唯一标识符
    let id: UUID

    /// 录制的触发事件
    let triggerEvent: RecordedEvent

    /// 绑定的系统快捷键名称
    let systemShortcutName: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    // MARK: - 计算属性

    /// 获取系统快捷键对象
    var systemShortcut: SystemShortcut.Shortcut? {
        return SystemShortcut.getShortcut(named: systemShortcutName)
    }

    // MARK: - 初始化

    init(id: UUID = UUID(), triggerEvent: RecordedEvent, systemShortcutName: String, isEnabled: Bool = true) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.systemShortcutName = systemShortcutName
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }

    // MARK: - Equatable

    static func == (lhs: ButtonBinding, rhs: ButtonBinding) -> Bool {
        return lhs.id == rhs.id
    }
}
