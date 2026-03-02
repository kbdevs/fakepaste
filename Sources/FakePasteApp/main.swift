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

    static let `default` = AppTypingSettings(
        wpm: 130.0,
        typoRate: 0.04,
        wordPauseChance: 0.18,
        wordPauseMin: 0.08,
        wordPauseMax: 0.22
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
            wordPauseMax: defaults.object(forKey: "settings.wordPauseMax") as? Double ?? AppTypingSettings.default.wordPauseMax
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(wpm, forKey: "settings.wpm")
        defaults.set(typoRate, forKey: "settings.typoRate")
        defaults.set(wordPauseChance, forKey: "settings.wordPauseChance")
        defaults.set(wordPauseMin, forKey: "settings.wordPauseMin")
        defaults.set(wordPauseMax, forKey: "settings.wordPauseMax")
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

        typingQueue.async { [weak self] in
            defer {
                self?.lock.lock()
                self?.isTyping = false
                self?.shouldCancelTyping = false
                self?.lock.unlock()
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
