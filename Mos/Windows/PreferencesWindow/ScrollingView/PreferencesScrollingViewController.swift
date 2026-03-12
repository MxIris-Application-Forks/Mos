//
//  PreferencesScrollingViewController.swift
//  Mos
//  滚动选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesScrollingViewController: NSViewController, ScrollOptionsContextProviding {

    // Target application
    // - Using when the VC is inside the Application Setting Popup
    var currentTargetApplication: Application?
    // UI Elements
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var dashKeyBindButton: NSButton!
    @IBOutlet weak var dashKeyDelButton: NSButton!
    @IBOutlet weak var toggleKeyBindButton: NSButton!
    @IBOutlet weak var toggleKeyDelButton: NSButton!
    @IBOutlet weak var disableKeyBindButton: NSButton!
    @IBOutlet weak var disableKeyDelButton: NSButton!
    @IBOutlet weak var scrollStepSlider: NSSlider!
    @IBOutlet weak var scrollStepInput: NSTextField!
    @IBOutlet weak var scrollStepStepper: NSStepper!
    @IBOutlet weak var scrollSpeedSlider: NSSlider!
    @IBOutlet weak var scrollSpeedInput: NSTextField!
    @IBOutlet weak var scrollSpeedStepper: NSStepper!
    @IBOutlet weak var scrollDurationSlider: NSSlider!
    @IBOutlet weak var scrollDurationInput: NSTextField!
    @IBOutlet weak var scrollDurationStepper: NSStepper!
    @IBOutlet weak var scrollDurationDescriptionLabel: NSTextField?
    @IBOutlet weak var resetToDefaultsButton: NSButton!
    var resetButtonHeightConstraint: NSLayoutConstraint?
    // Constants
    let DefaultConfigForCompare = OPTIONS_SCROLL_DEFAULT()
    private var scrollDurationDescriptionDefaultText: String?
    private let scrollDurationLockedDescription = NSLocalizedString(
        "scrollDurationLockedMessage",
        comment: "Message shown when simulate trackpad locks the duration setting"
    )
    // KeyRecorder for custom hotkey recording
    private let keyRecorder = KeyRecorder()
    private weak var currentRecordingPopup: NSButton?

    override func viewDidLoad() {
        // 禁止自动 Focus
        scrollStepInput.refusesFirstResponder = true
        scrollSpeedInput.refusesFirstResponder = true
        scrollDurationInput.refusesFirstResponder = true
        // 创建高度约束
        resetButtonHeightConstraint = resetToDefaultsButton.heightAnchor.constraint(equalToConstant: 24)
        resetButtonHeightConstraint?.isActive = true
        scrollDurationDescriptionDefaultText = scrollDurationDescriptionLabel?.stringValue
        // 设置 KeyRecorder 代理
        keyRecorder.delegate = self
        // 读取设置
        syncViewWithOptions()
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let smoothPopover = segue.destinationController as? ScrollSmoothDetailSettingsPopoverViewController {
            smoothPopover.currentTargetApplication = currentTargetApplication
            smoothPopover.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        } else if let reversePopover = segue.destinationController as? ScrollReverseDetailSettingsPopoverViewController {
            reversePopover.currentTargetApplication = currentTargetApplication
            reversePopover.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        }
    }
    
    // 平滑
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smooth = sender.state.rawValue != 0
        syncViewWithOptions()
    }

    // 翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().reverse = sender.state.rawValue != 0
        syncViewWithOptions()
    }
    
    // 加速键 - 点击触发录制
    @IBAction func dashKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 加速键 - 清除绑定
    @IBAction func dashKeyDelButtonClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().dash = nil
        syncViewWithOptions()
    }
    // 转换键 - 点击触发录制
    @IBAction func toggleKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 转换键 - 清除绑定
    @IBAction func toggleKeyDelButtonClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().toggle = nil
        syncViewWithOptions()
    }
    // 禁用键 - 点击触发录制
    @IBAction func disableKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 禁用键 - 清除绑定
    @IBAction func disableKeyDelButtonClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().block = nil
        syncViewWithOptions()
    }
    
    // 步长
    @IBAction func scrollStepSliderChange(_ sender: NSSlider) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepInputChange(_ sender: NSTextField) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepStepperChange(_ sender: NSStepper) {
        setScrollStep(value: sender.doubleValue)
    }
    func setScrollStep(value: Double) {
        getTargetApplicationScrollOptions().step = value
        syncViewWithOptions()
    }
    
    // 速度
    @IBAction func scrollSpeedSliderChange(_ sender: NSSlider) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedInputChange(_ sender: NSTextField) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedStepperChange(_ sender: NSStepper) {
        setScrollSpeed(value: sender.doubleValue)
    }
    func setScrollSpeed(value: Double) {
        getTargetApplicationScrollOptions().speed = value
        syncViewWithOptions()
    }
    
    // 过渡
    @IBAction func scrollDurationSliderChange(_ sender: NSSlider) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationInputChange(_ sender: NSTextField) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationStepperChange(_ sender: NSStepper) {
        setScrollDuration(value: sender.doubleValue)
    }
    func setScrollDuration(value: Double) {
        let scrollOptions = getTargetApplicationScrollOptions()
        if scrollOptions.smoothSimTrackpad {
            scrollOptions.duration = ScrollDurationLimits.simulateTrackpadDefault
        } else {
            scrollOptions.duration = value
        }
        syncViewWithOptions()
    }
    
    // 重置
    @IBAction func resetToDefaultClick(_ sender: NSButton) {
        if let target = currentTargetApplication {
            target.scroll = OPTIONS_SCROLL_DEFAULT()
        } else {
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        }
        syncViewWithOptions()
    }
    
}

/**
 * 工具函数
 **/
extension PreferencesScrollingViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 是否继承配置
        let isNotInherit = !isTargetApplicationInheritOptions()
        // 滚动配置
        let scroll = getTargetApplicationScrollOptions()
        // 平滑
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: scroll.smooth ? 1 : 0)
        scrollSmoothCheckBox.isEnabled = isNotInherit
        // 翻转
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: scroll.reverse ? 1 : 0)
        scrollReverseCheckBox.isEnabled = isNotInherit
        // 加速键
        updateHotkeyButton(dashKeyBindButton, delButton: dashKeyDelButton, hotkey: scroll.dash, enabled: isNotInherit)
        // 转换键
        updateHotkeyButton(toggleKeyBindButton, delButton: toggleKeyDelButton, hotkey: scroll.toggle, enabled: isNotInherit)
        // 禁用键
        updateHotkeyButton(disableKeyBindButton, delButton: disableKeyDelButton, hotkey: scroll.block, enabled: isNotInherit)
        // 步长
        let step = scroll.step
        scrollStepSlider.doubleValue = step
        scrollStepSlider.isEnabled = isNotInherit
        scrollStepStepper.doubleValue = step
        scrollStepStepper.isEnabled = isNotInherit
        scrollStepInput.stringValue = String(format: "%.2f", step)
        scrollStepInput.isEnabled = isNotInherit
        // 速度
        let speed = scroll.speed
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedSlider.isEnabled = isNotInherit
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedStepper.isEnabled = isNotInherit
        scrollSpeedInput.stringValue = String(format: "%.2f", speed)
        scrollSpeedInput.isEnabled = isNotInherit
        // 过渡
        let isSimTrackpadEnabled = scroll.smoothSimTrackpad
        let resolvedDuration: Double
        if isSimTrackpadEnabled {
            resolvedDuration = ScrollDurationLimits.simulateTrackpadDefault
            if scroll.duration != resolvedDuration {
                scroll.duration = resolvedDuration
            }
        } else {
            resolvedDuration = scroll.duration
        }
        scrollDurationSlider.doubleValue = resolvedDuration
        scrollDurationSlider.isEnabled = isNotInherit && !isSimTrackpadEnabled
        scrollDurationStepper.doubleValue = resolvedDuration
        scrollDurationStepper.isEnabled = isNotInherit && !isSimTrackpadEnabled
        scrollDurationInput.stringValue = String(format: "%.2f", resolvedDuration)
        scrollDurationInput.isEnabled = isNotInherit && !isSimTrackpadEnabled
        if isSimTrackpadEnabled {
            scrollDurationDescriptionLabel?.stringValue = scrollDurationLockedDescription
        } else if let defaultText = scrollDurationDescriptionDefaultText {
            scrollDurationDescriptionLabel?.stringValue = defaultText
        }
        // 更新重置按钮状态
        updateResetButtonState()
    }
    // 更新重置按钮状态与显示
    func updateResetButtonState() {
        let isNotInherit = !isTargetApplicationInheritOptions()
        let scroll = getTargetApplicationScrollOptions()
        let shouldShowResetButton = isNotInherit && scroll != DefaultConfigForCompare
        // 动画过渡
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ANIMATION.duration
            context.allowsImplicitAnimation = true
            resetToDefaultsButton.animator().isEnabled = shouldShowResetButton
            resetToDefaultsButton.animator().alphaValue = shouldShowResetButton ? 1.0 : 0.0
            resetButtonHeightConstraint?.animator().constant = shouldShowResetButton ? 24 : 0
        }, completionHandler: {
            // 触发父视图窗口尺寸更新
            self.view.needsLayout = true
            self.view.layout()
            (self.parent as? PreferencesTabViewController)?.updateWindowSize()
        })
    }

    /// 键盘按键的完整名称映射 (仅用于 ScrollingView 按钮显示)
    private static let keyFullNames: [UInt16: String] = [
        // 修饰键
        KeyCode.commandL: "⌘ Command",
        KeyCode.commandR: "⌘ Command",
        KeyCode.optionL: "⌥ Option",
        KeyCode.optionR: "⌥ Option",
        KeyCode.shiftL: "⇧ Shift",
        KeyCode.shiftR: "⇧ Shift",
        KeyCode.controlL: "⌃ Control",
        KeyCode.controlR: "⌃ Control",
        KeyCode.fnL: "Fn",
        KeyCode.fnR: "Fn",
        // 特殊键
        49: "⎵ Space",
        51: "⌫ Delete",
        53: "⎋ Escape",
        36: "↩ Return",
        76: "↩ Return",
        48: "↹ Tab",
    ]

    /// 获取 ScrollHotkey 的完整显示名称
    private func getFullDisplayName(for hotkey: ScrollHotkey) -> String {
        switch hotkey.type {
        case .keyboard:
            // 优先使用完整名称映射
            if let fullName = PreferencesScrollingViewController.keyFullNames[hotkey.code] {
                return fullName
            }
            // 其他按键使用原始映射
            return KeyCode.keyMap[hotkey.code] ?? "Key \(hotkey.code)"
        case .mouse:
            return KeyCode.mouseMap[hotkey.code] ?? "🖱\(hotkey.code)"
        }
    }

    /// 更新热键按钮的显示文本和删除按钮可见性
    private func updateHotkeyButton(_ button: NSButton?, delButton: NSButton?, hotkey: ScrollHotkey?, enabled: Bool) {
        guard let button = button else { return }

        let hasBound = hotkey != nil

        // 获取显示名称
        let displayName: String
        if let hotkey = hotkey {
            displayName = getFullDisplayName(for: hotkey)
        } else {
            displayName = NSLocalizedString("Disabled", comment: "Hotkey disabled state")
        }

        // 设置按钮标题和启用状态
        button.title = displayName
        button.isEnabled = enabled

        // 设置删除按钮可见性：仅在有绑定且启用时显示
        delButton?.alphaValue = (hasBound && enabled) ? 1.0 : 0.0
        delButton?.isEnabled = hasBound && enabled
    }
}

// MARK: - KeyRecorderDelegate
extension PreferencesScrollingViewController: KeyRecorderDelegate {
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: CGEvent, isDuplicate: Bool) {
        guard let popup = currentRecordingPopup else { return }

        // 从事件创建 ScrollHotkey
        let hotkey = ScrollHotkey(from: event)

        // 保存设置
        if popup === dashKeyBindButton {
            getTargetApplicationScrollOptions().dash = hotkey
        } else if popup === toggleKeyBindButton {
            getTargetApplicationScrollOptions().toggle = hotkey
        } else if popup === disableKeyBindButton {
            getTargetApplicationScrollOptions().block = hotkey
        }

        currentRecordingPopup = nil
        syncViewWithOptions()
    }
}
