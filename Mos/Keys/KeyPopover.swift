//
//  KeyPopover.swift
//  Mos
//  录制按键时显示的 Popover UI 组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class KeyPopover: NSObject {

    // MARK: - Properties
    private var popover: NSPopover?
    var keyPreview: KeyPreview!
    private var escHintLabel: NSTextField?
    private var escHintHeightConstraint: NSLayoutConstraint?
    private var contentView: NSView?

    // MARK: - Constants
    private let baseHeight: CGFloat = 45
    private let hintHeight: CGFloat = 18

    // MARK: - Visibility
    /// 显示录制 popover
    func show(at sourceView: NSView) {
        hide() // 确保之前的 popover 被关闭
        setupPopover()
        popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    /// 隐藏 popover
    func hide() {
        popover?.close()
        popover = nil
    }

    // MARK: - Public Methods
    /// 显示 ESC 退出提示
    func showEscHint() {
        guard let label = escHintLabel,
              let heightConstraint = escHintHeightConstraint,
              heightConstraint.constant == 0 else { return }

        // 动画展开提示
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ANIMATION.duration
            context.allowsImplicitAnimation = true
            label.animator().alphaValue = 1
            heightConstraint.animator().constant = hintHeight
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            // 更新 popover 尺寸
            self.contentView?.layout()
            if let size = self.contentView?.fittingSize {
                self.popover?.contentSize = size
            }
        })
    }

    // MARK: - Private Methods
    private func getContentView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        contentView = view

        // 创建按键显示组件
        keyPreview = KeyPreview()
        keyPreview.translatesAutoresizingMaskIntoConstraints = false

        // 创建 ESC 提示标签
        let hintLabel = NSTextField(labelWithString: NSLocalizedString("Press ESC to cancel recording", comment: "ESC hint in key recording popover"))
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = NSColor.secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.alphaValue = 0
        hintLabel.setContentHuggingPriority(.required, for: .vertical)
        escHintLabel = hintLabel

        // 创建高度约束（初始为 0）
        let heightConstraint = hintLabel.heightAnchor.constraint(equalToConstant: 0)
        escHintHeightConstraint = heightConstraint

        // 添加到内容视图
        view.addSubview(keyPreview)
        view.addSubview(hintLabel)

        // 设置约束
        NSLayoutConstraint.activate([
            // 按键显示约束
            keyPreview.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            keyPreview.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),

            // ESC 提示约束
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: keyPreview.bottomAnchor, constant: 4),
            hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            heightConstraint,

            // 内容视图宽度约束
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 165),
        ])

        return view
    }

    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentViewController = NSViewController()
        newPopover.contentViewController?.view = getContentView()
        newPopover.behavior = .transient
        popover = newPopover
    }
}
