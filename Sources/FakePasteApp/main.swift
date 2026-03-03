import AppKit
import ApplicationServices
import FakePasteCore
import Foundation

struct AppTypingSettings {
    static let wpmNormalizationFactor: Double = 9.0

    var wpm: Double
    var typoRate: Double
    var wordPauseChance: Double
    var wordPauseMin: Double
    var wordPauseMax: Double
    var showProgressOverlay: Bool

    static let `default` = AppTypingSettings(
        wpm: 130.0,
        typoRate: 0.04,
        wordPauseChance: 0.18,
        wordPauseMin: 0.08,
        wordPauseMax: 0.22,
        showProgressOverlay: false
    )

    func makeModel() -> HumanTypingModel {
        HumanTypingModel(
            targetWPM: wpm * Self.wpmNormalizationFactor,
            typoRate: typoRate,
            wordPauseChance: wordPauseChance,
            wordPauseMin: wordPauseMin,
            wordPauseMax: wordPauseMax
        )
    }

    static func load() -> AppTypingSettings {
        let defaults = UserDefaults.standard
        let loadedWPM = defaults.object(forKey: "settings.wpm") as? Double
        var wpm = loadedWPM ?? AppTypingSettings.default.wpm
        if wpm > 300 {
            wpm = wpm / Self.wpmNormalizationFactor
            defaults.set(wpm, forKey: "settings.wpm")
        }
        return AppTypingSettings(
            wpm: wpm,
            typoRate: defaults.object(forKey: "settings.typoRate") as? Double ?? AppTypingSettings.default.typoRate,
            wordPauseChance: defaults.object(forKey: "settings.wordPauseChance") as? Double ?? AppTypingSettings.default.wordPauseChance,
            wordPauseMin: defaults.object(forKey: "settings.wordPauseMin") as? Double ?? AppTypingSettings.default.wordPauseMin,
            wordPauseMax: defaults.object(forKey: "settings.wordPauseMax") as? Double ?? AppTypingSettings.default.wordPauseMax,
            showProgressOverlay: defaults.object(forKey: "settings.showProgressOverlay") as? Bool ?? AppTypingSettings.default.showProgressOverlay
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(wpm, forKey: "settings.wpm")
        defaults.set(typoRate, forKey: "settings.typoRate")
        defaults.set(wordPauseChance, forKey: "settings.wordPauseChance")
        defaults.set(wordPauseMin, forKey: "settings.wordPauseMin")
        defaults.set(wordPauseMax, forKey: "settings.wordPauseMax")
        defaults.set(showProgressOverlay, forKey: "settings.showProgressOverlay")
    }
}

final class ProgressOverlayController {
    private let panel: NSPanel
    private let progressTrack: NSView
    private let progressFill: NSView
    private let remainingTimeLabel: NSTextField
    private var progressFillWidthConstraint: NSLayoutConstraint?
    private var followTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 194, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        progressTrack = NSView(frame: NSRect(x: 12, y: 8, width: 156, height: 8))
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor(calibratedWhite: 0.35, alpha: 1.0).cgColor
        progressTrack.layer?.cornerRadius = 4

        progressFill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 8))
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor(calibratedRed: 0.52, green: 0.46, blue: 0.70, alpha: 1.0).cgColor
        progressFill.layer?.cornerRadius = 4

        remainingTimeLabel = NSTextField(labelWithString: "")
        remainingTimeLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1.0)
        remainingTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        remainingTimeLabel.alignment = .right
        remainingTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        remainingTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        contentView.layer?.cornerRadius = 10
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        remainingTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressTrack)
        contentView.addSubview(remainingTimeLabel)
        progressTrack.addSubview(progressFill)
        NSLayoutConstraint.activate([
            progressTrack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            progressTrack.trailingAnchor.constraint(equalTo: remainingTimeLabel.leadingAnchor, constant: -2),
            progressTrack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 8),
            remainingTimeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            remainingTimeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
        ])
        progressFillWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidthConstraint?.isActive = true
        panel.contentView = contentView
    }

    func show() {
        setProgress(0, remainingTime: nil)
        repositionNearCaret()
        panel.orderFrontRegardless()
        startFollowingCaret()
    }

    func hide() {
        stopFollowingCaret()
        panel.orderOut(nil)
    }

    func setProgress(_ value: Double, remainingTime: TimeInterval? = nil) {
        let clamped = min(1.0, max(0.0, value))
        panel.contentView?.layoutSubtreeIfNeeded()
        let maxWidth = progressTrack.bounds.width
        progressFillWidthConstraint?.constant = maxWidth * clamped
        remainingTimeLabel.stringValue = formatRemainingTime(remainingTime)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func formatRemainingTime(_ remainingTime: TimeInterval?) -> String {
        guard let remainingTime else { return "" }
        let clampedSeconds = max(0, Int(ceil(remainingTime)))
        if clampedSeconds < 60 {
            return "\(clampedSeconds)s"
        }
        let minutes = clampedSeconds / 60
        let seconds = clampedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startFollowingCaret() {
        stopFollowingCaret()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.repositionNearCaret()
        }
    }

    private func stopFollowingCaret() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func repositionNearCaret() {
        let panelSize = panel.frame.size
        if let caret = currentCaretRect(), !isLikelyInvalidCaret(caret) {
            let direct = clamped(point: NSPoint(x: caret.midX - (panelSize.width / 2.0), y: caret.maxY + 14), panelSize: panelSize)
            let flipped = clamped(point: flippedCaretOrigin(caret, panelSize: panelSize), panelSize: panelSize)
            panel.setFrameOrigin(bestCandidate([direct, flipped], panelSize: panelSize))
            return
        }

        panel.setFrameOrigin(clamped(point: topCenterFallbackOrigin(panelSize: panelSize), panelSize: panelSize))
    }

    private func flippedCaretOrigin(_ caret: CGRect, panelSize: NSSize) -> NSPoint {
        guard let screen = bestScreen(forX: caret.midX) else {
            return NSPoint(x: caret.midX - (panelSize.width / 2.0), y: caret.maxY + 14)
        }

        let cocoaCaretY = screen.frame.maxY - caret.origin.y - caret.height
        return NSPoint(x: caret.midX - (panelSize.width / 2.0), y: cocoaCaretY + caret.height + 14)
    }

    private func isPointOnAnyScreen(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(point) }
    }

    private func bestCandidate(_ candidates: [NSPoint], panelSize: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let scored = candidates.map { point -> (NSPoint, CGFloat) in
            let center = NSPoint(x: point.x + panelSize.width / 2.0, y: point.y + panelSize.height / 2.0)
            let distance = hypot(center.x - mouse.x, center.y - mouse.y)
            return (point, distance)
        }
        return scored.min(by: { $0.1 < $1.1 })?.0 ?? candidates.first ?? NSPoint(x: 0, y: 0)
    }

    private func isLikelyInvalidCaret(_ caret: CGRect) -> Bool {
        if caret.isNull || caret.isInfinite || caret.isEmpty {
            return true
        }
        return abs(caret.origin.x) < 0.5 && abs(caret.origin.y) < 0.5 && caret.width < 1.5 && caret.height < 1.5
    }

    private func bestScreen(forX x: CGFloat) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) ?? NSScreen.main
    }

    private func clamped(point: NSPoint, panelSize: NSSize) -> NSPoint {
        guard let screen = bestScreen(forX: point.x + panelSize.width / 2.0) else { return point }
        let visible = screen.visibleFrame.insetBy(dx: 4, dy: 4)
        let clampedX = min(max(point.x, visible.minX), visible.maxX - panelSize.width)
        let clampedY = min(max(point.y, visible.minY), visible.maxY - panelSize.height)
        return NSPoint(x: clampedX, y: clampedY)
    }

    private func topCenterFallbackOrigin(panelSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 0, y: 0)
        }

        let visible = screen.visibleFrame
        let x = visible.midX - (panelSize.width / 2.0)
        let y = visible.maxY - panelSize.height - 6
        return NSPoint(x: x, y: y)
    }

    private func currentCaretRect() -> CGRect? {
        let system = AXUIElementCreateSystemWide()

        var focusedObject: AnyObject?
        let focusedStatus = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard focusedStatus == .success, let focused = focusedObject else { return nil }

        let element = focused as! AXUIElement
        var selectedRangeObject: AnyObject?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeObject)
        guard rangeStatus == .success, let selectedRangeObject else { return nil }
        guard CFGetTypeID(selectedRangeObject) == AXValueGetTypeID() else { return nil }
        let selectedRangeValue = unsafeBitCast(selectedRangeObject, to: AXValue.self)

        var boundsObject: AnyObject?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsObject
        )
        guard boundsStatus == .success, let boundsObject else { return nil }
        guard CFGetTypeID(boundsObject) == AXValueGetTypeID() else { return nil }
        let boundsValue = unsafeBitCast(boundsObject, to: AXValue.self)

        var rect = CGRect.zero
        guard AXValueGetType(boundsValue) == .cgRect, AXValueGetValue(boundsValue, .cgRect, &rect) else { return nil }
        return rect
    }
}

final class FakePasteAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let hotkeyQueue = DispatchQueue(label: "com.fakepaste.hotkey", qos: .userInitiated)
    private let typingQueue = DispatchQueue(label: "com.fakepaste.typing", qos: .userInitiated)
    private let lock = NSLock()

    private var isTyping = false
    private var shouldCancelTyping = false
    private var lastHotkeyHandledAt: CFAbsoluteTime = 0
    private var settings = AppTypingSettings.load()
    private let progressOverlay = ProgressOverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissionPrompt()
        setupStatusItem()
        setupHotkeyMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "FakePaste")
            button.image?.isTemplate = true
            button.toolTip = "FakePaste"
        }

        self.statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "FakePaste", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let hotkey = NSMenuItem(title: "Hotkey: Option+Cmd+V", action: nil, keyEquivalent: "")
        hotkey.isEnabled = false
        menu.addItem(hotkey)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSpeedMenu())
        menu.addItem(makeTyposMenu())
        menu.addItem(makePausesMenu())

        let progressOverlayItem = NSMenuItem(
            title: "Show Progress Overlay",
            action: #selector(toggleProgressOverlay),
            keyEquivalent: ""
        )
        progressOverlayItem.target = self
        progressOverlayItem.state = settings.showProgressOverlay ? .on : .off
        menu.addItem(progressOverlayItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func makeSpeedMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Speed (WPM)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let presets: [Double] = [40, 70, 100, 130, 170, 220]
        for preset in presets {
            let presetItem = NSMenuItem(
                title: String(format: "%.0f", preset),
                action: #selector(setSpeed(_:)),
                keyEquivalent: ""
            )
            presetItem.target = self
            presetItem.representedObject = preset
            presetItem.state = abs(settings.wpm - preset) < 1 ? .on : .off
            submenu.addItem(presetItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeTyposMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Typos", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let presets: [(String, Double)] = [
            ("Off (0%)", 0.0),
            ("Low (2%)", 0.02),
            ("Normal (4%)", 0.04),
            ("High (7%)", 0.07),
        ]

        for (label, value) in presets {
            let option = NSMenuItem(title: label, action: #selector(setTypos(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = value
            option.state = abs(settings.typoRate - value) < 0.0001 ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func makePausesMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Word Pauses", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let profiles: [(String, Double, Double, Double)] = [
            ("Off", 0.0, 0.0, 0.0),
            ("Short", 0.12, 0.05, 0.12),
            ("Balanced", 0.18, 0.08, 0.22),
            ("Long", 0.30, 0.12, 0.35),
        ]

        for (label, chance, min, max) in profiles {
            let option = NSMenuItem(title: label, action: #selector(setPauseProfile(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = [chance, min, max]

            let selected = abs(settings.wordPauseChance - chance) < 0.0001
                && abs(settings.wordPauseMin - min) < 0.0001
                && abs(settings.wordPauseMax - max) < 0.0001
            option.state = selected ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    @objc private func setSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        lock.lock()
        settings.wpm = value
        settings.save()
        lock.unlock()
        refreshMenu()
    }

    @objc private func setTypos(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        lock.lock()
        settings.typoRate = value
        settings.save()
        lock.unlock()
        refreshMenu()
    }

    @objc private func setPauseProfile(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Double], values.count == 3 else { return }
        lock.lock()
        settings.wordPauseChance = values[0]
        settings.wordPauseMin = values[1]
        settings.wordPauseMax = values[2]
        settings.save()
        lock.unlock()
        refreshMenu()
    }

    @objc private func toggleProgressOverlay() {
        lock.lock()
        settings.showProgressOverlay.toggle()
        settings.save()
        let shouldShow = settings.showProgressOverlay && isTyping
        lock.unlock()

        if shouldShow {
            DispatchQueue.main.async { [weak self] in
                self?.progressOverlay.show()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.progressOverlay.hide()
            }
        }

        refreshMenu()
    }

    private func setupHotkeyMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isTriggerHotkey(event) else { return }

        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let shouldIgnore = (now - lastHotkeyHandledAt) < 0.15
        if !shouldIgnore {
            lastHotkeyHandledAt = now
        }
        lock.unlock()
        guard !shouldIgnore else { return }

        hotkeyQueue.async { [weak self] in
            self?.waitForHotkeyReleaseThenSettle()
            self?.triggerTypingFromClipboard()
        }
    }

    private func isTriggerHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 9 else { return false }
        guard flags.contains(.command), flags.contains(.option) else { return false }
        guard !flags.contains(.control), !flags.contains(.shift) else { return false }
        return true
    }

    private func waitForHotkeyReleaseThenSettle() {
        let timeoutAt = CFAbsoluteTimeGetCurrent() + 2.0
        while areHotkeyModifiersPressed(), CFAbsoluteTimeGetCurrent() < timeoutAt {
            Thread.sleep(forTimeInterval: 0.01)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func areHotkeyModifiersPressed() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskCommand) || flags.contains(.maskAlternate)
    }

    private func triggerTypingFromClipboard() {
        lock.lock()
        if isTyping {
            shouldCancelTyping = true
            lock.unlock()
            return
        }
        isTyping = true
        shouldCancelTyping = false
        let currentSettings = settings
        lock.unlock()

        if currentSettings.showProgressOverlay {
            DispatchQueue.main.async { [weak self] in
                self?.progressOverlay.show()
            }
        }

        typingQueue.async { [weak self] in
            defer {
                self?.lock.lock()
                self?.isTyping = false
                self?.shouldCancelTyping = false
                self?.lock.unlock()
                DispatchQueue.main.async { [weak self] in
                    self?.progressOverlay.hide()
                }
            }

            guard let self else { return }
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }

            var rng = SystemRandomNumberGenerator()
            let plan = currentSettings.makeModel().typingPlan(for: text, rng: &rng)
            self.execute(plan)
        }
    }

    private func execute(_ actions: [TypingAction]) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let totalActions = max(1, actions.count)
        let estimatedTotalDuration = max(0, actions.reduce(0.0) { partial, action in
            if case let .delay(delay) = action {
                return partial + delay
            }
            return partial
        })
        let startTime = CFAbsoluteTimeGetCurrent()
        var completed = 0

        DispatchQueue.main.async { [weak self] in
            self?.progressOverlay.setProgress(0, remainingTime: estimatedTotalDuration)
        }

        for action in actions {
            if isTypingCancelled() {
                return
            }

            switch action {
            case .character(let string):
                sendUnicode(string, source: source)
            case .backspace:
                sendBackspace(source: source)
            case .delay(let delay):
                sleepInterruptible(delay)
            }

            completed += 1
            let progress = Double(completed) / Double(totalActions)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let modelRemaining = max(0, estimatedTotalDuration - elapsed)
            let paceRemaining = max(0, (elapsed / max(progress, 0.001)) - elapsed)
            let remainingTime = progress < 0.15 ? modelRemaining : paceRemaining
            DispatchQueue.main.async { [weak self] in
                self?.progressOverlay.setProgress(progress, remainingTime: remainingTime)
            }
        }
    }

    private func sleepInterruptible(_ delay: TimeInterval) {
        let step: TimeInterval = 0.02
        var remaining = delay
        while remaining > 0 {
            if isTypingCancelled() {
                return
            }
            let chunk = min(step, remaining)
            Thread.sleep(forTimeInterval: chunk)
            remaining -= chunk
        }
    }

    private func isTypingCancelled() -> Bool {
        lock.lock()
        let cancelled = shouldCancelTyping
        lock.unlock()
        return cancelled
    }

    private func sendUnicode(_ value: String, source: CGEventSource) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return
        }

        let utf16 = Array(value.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func sendBackspace(source: CGEventSource) {
        let keycode: CGKeyCode = 51
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: false)
        else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func requestAccessibilityPermissionPrompt() {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = FakePasteAppDelegate()
app.delegate = delegate
app.run()
