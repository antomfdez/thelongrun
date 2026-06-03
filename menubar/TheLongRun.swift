import Cocoa
import CoreGraphics
import IOKit.hid

let kAppVersion = "1.1"

// A "hold mode": the keys we press-and-hold and the modifier flags stamped on them.
struct HoldPreset {
    let name: String
    let keys: [CGKeyCode]
    let flags: CGEventFlags
}

// One hotkey -> one hold mode.
struct Bind {
    var key: CGKeyCode
    var presetIndex: Int
    var running = false
}

struct KeyChoice { let label: String; let code: CGKeyCode }

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // --- presets -------------------------------------------------------------
    let presets: [HoldPreset] = [
        HoldPreset(name: "Sprint — W + Shift", keys: [56, 13], flags: .maskShift),
        HoldPreset(name: "Walk — W",           keys: [13],     flags: []),
        HoldPreset(name: "Sprint — ↑ + Shift", keys: [56, 126], flags: .maskShift),
        HoldPreset(name: "Walk — ↑",           keys: [126],    flags: []),
    ]
    // Quick-pick keys (Record a key… captures anything else).
    let keyChoices: [KeyChoice] = [
        KeyChoice(label: "\\", code: 42), KeyChoice(label: "`", code: 50),
        KeyChoice(label: "W", code: 13),  KeyChoice(label: "A", code: 0),
        KeyChoice(label: "S", code: 1),   KeyChoice(label: "D", code: 2),
        KeyChoice(label: "Z", code: 6),   KeyChoice(label: "X", code: 7),
        KeyChoice(label: "C", code: 8),   KeyChoice(label: "V", code: 9),
        KeyChoice(label: "=", code: 24),  KeyChoice(label: "-", code: 27),
        KeyChoice(label: "F8", code: 100), KeyChoice(label: "F9", code: 101),
    ]

    // --- state ---------------------------------------------------------------
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    let source = CGEventSource(stateID: .hidSystemState)
    var eventTap: CFMachPort?

    var binds: [Bind] = [Bind(key: 42, presetIndex: 0)]   // default: "\" -> Sprint
    var recordingBind: Int?
    var permTimer: Timer?
    var repeatTimer: Timer?
    var guideShown = false

    // settings
    var exclusive = true        // one bind at a time (starting one stops others)
    var keyRepeat = false       // re-emit held keys for games that need autorepeat
    var scope = "auto"          // "auto" (The Long Dark) | "everywhere" | <bundleID>

    // --- lifecycle -----------------------------------------------------------
    func applicationDidFinishLaunching(_ note: Notification) {
        load()
        menu.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        buildMenu()
        refreshIcon()
        if let icon = NSImage(systemSymbolName: "figure.run", accessibilityDescription: nil) {
            NSApp.applicationIconImage = icon
        }

        // Auto-release: if focus leaves the active context, drop all held keys.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        ensurePermissionsAndStart()
    }

    func applicationWillTerminate(_ note: Notification) { releaseAllRunning(rebuild: false) }

    @objc func appActivated(_ n: Notification) {
        if !isActiveContext() { releaseAllRunning() }
    }

    // --- permissions ---------------------------------------------------------
    func ensurePermissionsAndStart() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)   // Input Monitoring
        if !AXIsProcessTrusted() {                              // Accessibility
            let opt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([opt: true] as CFDictionary)
        }
        if startTap() { refreshIcon(); buildMenu(); return }
        if !guideShown { guideShown = true; showPermissionAlert() }
        permTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self = self else { return }
            if self.startTap() { t.invalidate(); self.permTimer = nil; self.refreshIcon(); self.buildMenu() }
        }
    }

    // --- event tap -----------------------------------------------------------
    func startTap() -> Bool {
        if eventTap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<AppController>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if recordingBind != nil {            // recording works regardless of scope
                captureRecorded(kc)
                return nil
            }
            if let i = binds.firstIndex(where: { $0.key == kc }), isActiveContext() {
                toggleBind(i)
                return nil                       // consume only when in-context
            }
        }
        return Unmanaged.passUnretained(event)   // otherwise the key passes through normally
    }

    // --- scope ---------------------------------------------------------------
    func isActiveContext() -> Bool {
        if scope == "everywhere" { return true }
        guard let f = NSWorkspace.shared.frontmostApplication else { return false }
        if scope == "auto" {
            let n = (f.localizedName ?? "").lowercased()
            let b = (f.bundleIdentifier ?? "").lowercased()
            return n.contains("long dark") || b.contains("longdark")
        }
        return f.bundleIdentifier == scope
    }

    // --- key synthesis -------------------------------------------------------
    func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
    func holdKeys(_ p: HoldPreset)    { for k in p.keys { postKey(k, down: true, flags: p.flags) } }
    func releaseKeys(_ p: HoldPreset) { for k in p.keys.reversed() { postKey(k, down: false, flags: []) } }

    func toggleBind(_ i: Int) {
        let turningOn = !binds[i].running
        if turningOn && exclusive {
            for j in binds.indices where j != i && binds[j].running {
                releaseKeys(presets[binds[j].presetIndex]); binds[j].running = false
            }
        }
        binds[i].running = turningOn
        if turningOn { holdKeys(presets[binds[i].presetIndex]) }
        else { releaseKeys(presets[binds[i].presetIndex]) }
        updateRepeatTimer(); refreshIcon(); buildMenu()
    }

    func releaseAllRunning(rebuild: Bool = true) {
        var changed = false
        for j in binds.indices where binds[j].running {
            releaseKeys(presets[binds[j].presetIndex]); binds[j].running = false; changed = true
        }
        if changed { updateRepeatTimer(); if rebuild { refreshIcon(); buildMenu() } }
    }

    func updateRepeatTimer() {
        let need = keyRepeat && binds.contains { $0.running }
        if need && repeatTimer == nil {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                for b in self.binds where b.running {
                    let p = self.presets[b.presetIndex]
                    for k in p.keys { self.postKey(k, down: true, flags: p.flags) }
                }
            }
        } else if !need {
            repeatTimer?.invalidate(); repeatTimer = nil
        }
    }

    // --- recording -----------------------------------------------------------
    func startRecording(forBind i: Int) { recordingBind = i; refreshIcon(); buildMenu() }
    func captureRecorded(_ code: CGKeyCode) {
        guard let i = recordingBind else { return }
        recordingBind = nil
        binds[i].key = code
        save(); refreshIcon(); buildMenu()
    }

    // --- menu actions --------------------------------------------------------
    @objc func toggleBindItem(_ it: NSMenuItem)  { toggleBind(it.tag) }
    @objc func recordBindItem(_ it: NSMenuItem)  { startRecording(forBind: it.tag) }
    @objc func pickKeyItem(_ it: NSMenuItem) {
        guard let a = it.representedObject as? [Int] else { return }
        binds[a[0]].key = CGKeyCode(a[1]); save(); buildMenu()
    }
    @objc func pickModeItem(_ it: NSMenuItem) {
        guard let a = it.representedObject as? [Int] else { return }
        let i = a[0]
        if binds[i].running { releaseKeys(presets[binds[i].presetIndex]) }
        binds[i].presetIndex = a[1]
        if binds[i].running { holdKeys(presets[binds[i].presetIndex]) }
        save(); buildMenu()
    }
    @objc func addBindItem(_ s: Any?) {
        binds.append(Bind(key: 0, presetIndex: 1)); save()
        startRecording(forBind: binds.count - 1)
    }
    @objc func removeBindItem(_ it: NSMenuItem) {
        let i = it.tag
        if binds[i].running { releaseKeys(presets[binds[i].presetIndex]) }
        binds.remove(at: i)
        if binds.isEmpty { binds = [Bind(key: 42, presetIndex: 0)] }
        save(); refreshIcon(); buildMenu()
    }
    @objc func toggleExclusive(_ s: Any?) { exclusive.toggle(); save(); buildMenu() }
    @objc func toggleRepeat(_ s: Any?)    { keyRepeat.toggle(); save(); updateRepeatTimer(); buildMenu() }
    @objc func pickScope(_ it: NSMenuItem) {
        scope = (it.representedObject as? String) ?? "auto"
        releaseAllRunning(); save(); buildMenu()
    }
    @objc func showPermissionHelp(_ s: Any?) { showPermissionAlert() }
    @objc func about(_ s: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "The Long Run",
            .applicationVersion: kAppVersion,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Auto-hold movement keys for The Long Dark.",
        ])
    }
    @objc func quit(_ s: Any?) { NSApp.terminate(nil) }

    // --- conflict detection --------------------------------------------------
    func warnings(for i: Int) -> String? {
        let b = binds[i]
        if b.key == 0 { return "no key set" }
        if presets[b.presetIndex].keys.contains(b.key) {
            return "toggle key is also a held key — it won't reach the game"
        }
        if binds.indices.contains(where: { $0 != i && binds[$0].key == b.key }) {
            return "same key as another bind"
        }
        return nil
    }

    // --- UI ------------------------------------------------------------------
    var anyRunning: Bool { binds.contains { $0.running } }

    func scopeLabel() -> String {
        switch scope {
        case "everywhere": return "Everywhere"
        case "auto":       return "The Long Dark"
        default:
            let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == scope }
            return app?.localizedName ?? scope
        }
    }

    func refreshIcon() {
        guard let b = statusItem.button else { return }
        if recordingBind != nil { b.image = nil; b.contentTintColor = nil; b.title = "⌨️…"; return }
        if eventTap == nil      { b.image = nil; b.contentTintColor = nil; b.title = "⚠️";  return }
        b.title = ""
        let symbol = anyRunning ? "figure.run" : "figure.walk"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "The Long Run") {
            img.isTemplate = !anyRunning
            b.image = img
            b.contentTintColor = anyRunning ? .systemGreen : nil
        } else {
            b.image = nil; b.title = anyRunning ? "🏃" : "🚶"
        }
    }

    // Rebuild menu on open so the "Active in" running-apps list is fresh.
    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu() }

    func buildMenu() {
        menu.removeAllItems()

        if eventTap == nil {
            let warn = NSMenuItem(title: "⚠️ Needs Input Monitoring + Accessibility",
                                  action: #selector(showPermissionHelp(_:)), keyEquivalent: "")
            warn.target = self; menu.addItem(warn); menu.addItem(.separator())
        }

        let header: String
        if let i = recordingBind { header = "Press a key for bind \(i + 1)…" }
        else if anyRunning { header = "● Running" } else { header = "○ Idle" }
        let status = NSMenuItem(title: header, action: nil, keyEquivalent: ""); status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        for (i, bind) in binds.enumerated() {
            let warn = warnings(for: i)
            let prefix = warn == nil ? "" : "⚠︎ "
            let title = "\(prefix)\(keyName(bind.key))  →  \(presets[bind.presetIndex].name)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()

            let onoff = NSMenuItem(title: bind.running ? "Stop" : "Start",
                                   action: #selector(toggleBindItem(_:)), keyEquivalent: "")
            onoff.target = self; onoff.tag = i; onoff.state = bind.running ? .on : .off
            sub.addItem(onoff)
            if let w = warn {
                let wi = NSMenuItem(title: "⚠︎ \(w)", action: nil, keyEquivalent: ""); wi.isEnabled = false
                sub.addItem(wi)
            }
            sub.addItem(.separator())

            let keyHdr = NSMenuItem(title: "Toggle key", action: nil, keyEquivalent: "")
            let keyMenu = NSMenu()
            for c in keyChoices {
                let it = NSMenuItem(title: "\(c.label)   (\(keyName(c.code)))", action: #selector(pickKeyItem(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = [i, Int(c.code)]; it.state = (c.code == bind.key) ? .on : .off
                keyMenu.addItem(it)
            }
            keyMenu.addItem(.separator())
            let rec = NSMenuItem(title: "Record a key… (any key)", action: #selector(recordBindItem(_:)), keyEquivalent: "")
            rec.target = self; rec.tag = i; keyMenu.addItem(rec)
            keyHdr.submenu = keyMenu; sub.addItem(keyHdr)

            let modeHdr = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
            let modeMenu = NSMenu()
            for (mi, p) in presets.enumerated() {
                let it = NSMenuItem(title: p.name, action: #selector(pickModeItem(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = [i, mi]; it.state = (mi == bind.presetIndex) ? .on : .off
                modeMenu.addItem(it)
            }
            modeHdr.submenu = modeMenu; sub.addItem(modeHdr)

            sub.addItem(.separator())
            let rm = NSMenuItem(title: "Remove this bind", action: #selector(removeBindItem(_:)), keyEquivalent: "")
            rm.target = self; rm.tag = i; sub.addItem(rm)

            item.submenu = sub; menu.addItem(item)
        }

        let add = NSMenuItem(title: "Add bind…", action: #selector(addBindItem(_:)), keyEquivalent: "")
        add.target = self; menu.addItem(add)

        menu.addItem(.separator())

        // Active in ▸
        let scopeHdr = NSMenuItem(title: "Active in: \(scopeLabel())", action: nil, keyEquivalent: "")
        let scopeMenu = NSMenu()
        let everywhere = NSMenuItem(title: "Everywhere", action: #selector(pickScope(_:)), keyEquivalent: "")
        everywhere.target = self; everywhere.representedObject = "everywhere"; everywhere.state = scope == "everywhere" ? .on : .off
        scopeMenu.addItem(everywhere)
        let auto = NSMenuItem(title: "The Long Dark (auto-detect)", action: #selector(pickScope(_:)), keyEquivalent: "")
        auto.target = self; auto.representedObject = "auto"; auto.state = scope == "auto" ? .on : .off
        scopeMenu.addItem(auto)
        scopeMenu.addItem(.separator())
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.bundleIdentifier != nil {
            let it = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier!, action: #selector(pickScope(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = app.bundleIdentifier!; it.state = scope == app.bundleIdentifier ? .on : .off
            scopeMenu.addItem(it)
        }
        scopeHdr.submenu = scopeMenu; menu.addItem(scopeHdr)

        let exc = NSMenuItem(title: "One bind at a time", action: #selector(toggleExclusive(_:)), keyEquivalent: "")
        exc.target = self; exc.state = exclusive ? .on : .off; menu.addItem(exc)
        let rep = NSMenuItem(title: "Key auto-repeat (for stubborn games)", action: #selector(toggleRepeat(_:)), keyEquivalent: "")
        rep.target = self; rep.state = keyRepeat ? .on : .off; menu.addItem(rep)

        menu.addItem(.separator())
        let ab = NSMenuItem(title: "About The Long Run", action: #selector(about(_:)), keyEquivalent: "")
        ab.target = self; menu.addItem(ab)
        let q = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        q.target = self; menu.addItem(q)
    }

    // --- persistence ---------------------------------------------------------
    func save() {
        let d = UserDefaults.standard
        d.set(binds.map { [Int($0.key), $0.presetIndex] }, forKey: "binds")
        d.set(exclusive, forKey: "exclusive")
        d.set(keyRepeat, forKey: "keyRepeat")
        d.set(scope, forKey: "scope")
    }
    func load() {
        let d = UserDefaults.standard
        if let pairs = d.array(forKey: "binds") as? [[Int]], !pairs.isEmpty {
            binds = pairs.map { Bind(key: CGKeyCode($0[0]), presetIndex: min(max($0[1], 0), presets.count - 1)) }
        }
        if d.object(forKey: "exclusive") != nil { exclusive = d.bool(forKey: "exclusive") }
        if d.object(forKey: "keyRepeat") != nil { keyRepeat = d.bool(forKey: "keyRepeat") }
        if let s = d.string(forKey: "scope") { scope = s }
    }

    // --- permissions UI ------------------------------------------------------
    func showPermissionAlert() {
        let a = NSAlert()
        a.messageText = "Two permissions needed"
        a.informativeText = "The Long Run reads your hotkeys and holds the movement keys, so it needs "
            + "BOTH of these for TheLongRun:\n\n   • Privacy & Security ▸ Input Monitoring\n"
            + "   • Privacy & Security ▸ Accessibility\n\nTurn both on — the app picks it up automatically. "
            + "If it's already checked but still not working, remove it with “–” and re-add it."
        a.addButton(withTitle: "Open Input Monitoring")
        a.addButton(withTitle: "Open Accessibility")
        a.addButton(withTitle: "Later")
        switch a.runModal() {
        case .alertFirstButtonReturn:  openSettings("Privacy_ListenEvent")
        case .alertSecondButtonReturn: openSettings("Privacy_Accessibility")
        default: break
        }
    }
    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // --- key names -----------------------------------------------------------
    func keyName(_ code: CGKeyCode) -> String { keyNameMap[code] ?? "key \(code)" }
}

// macOS virtual key code -> friendly label (for display of any captured key).
let keyNameMap: [CGKeyCode: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
    34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    24: "=", 27: "-", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    49: "Space", 48: "Tab", 36: "Return", 53: "Esc", 51: "Delete",
    123: "←", 124: "→", 125: "↓", 126: "↑",
    56: "Left Shift", 60: "Right Shift", 59: "Left Ctrl", 62: "Right Ctrl",
    58: "Left Option", 61: "Right Option", 55: "Left Cmd", 54: "Right Cmd",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
]

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
