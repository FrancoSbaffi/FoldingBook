import AppKit
import MetalKit
import ScreenCaptureKit
import FoldingBookCore
import OSLog

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class MenuBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var sensor = LidSensor()
    private let environment = DisplayEnvironment()
    private var safety = DisplaySafetyGate()
    private var motion = LidMotionFilter()
    private var stoppingCapture = false
    private var lastSensorReconnect: TimeInterval = 0
    private var demoAngle = 75.0
    private let preferences = UserDefaults.standard
    private var window: OverlayPanel!
    private var view: MTKView!
    private var renderer: PlaneRenderer!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let logger = Logger(subsystem: "com.foldingbook.app", category: "Overlay")
    private var wantsOverlay = false
    private var lastAnglePoll: TimeInterval = 0
    private var lastButtonLabel = ""
    private var shortcut: GlobalShortcut?
    private var timer: Timer?
    private var capture: DesktopCapture?
    private var enabled = true
    private var starting = false
    private var suspended = false
    private var hasFrame = false
    private var current = 110.0
    private var lastReading: TimeInterval = 0
    private var previousTick: TimeInterval = 0
    private var anchor = AutoAnchor(angle: 100, now: 0)
    private var simulated = false
    private var status = "On"
    private var capturedDisplay: CGDirectDisplayID?
    private var lastCaptureAttempt: TimeInterval = 0
    private var lastPermissionCheck: TimeInterval = 0
    private var cachedHasPermission: Bool = false

    private func checkScreenCapturePermission(force: Bool = false) -> Bool {
        let now = CACurrentMediaTime()
        if force || now - lastPermissionCheck >= 2.0 {
            lastPermissionCheck = now
            let result = CGPreflightScreenCaptureAccess()
            if result != cachedHasPermission {
                NSLog("FoldingBook: CGPreflightScreenCaptureAccess changed to: %d", result ? 1 : 0)
            }
            cachedHasPermission = result
        }
        return cachedHasPermission
    }

    private var autoAnchor: Bool {
        get { preferences.bool(forKey: "autoAnchor") }
        set { preferences.set(newValue, forKey: "autoAnchor") }
    }
    private var angleMode: Bool { preferences.bool(forKey: "angleMode") }
    private var activationAngle: Double { min(180, max(10, preferences.double(forKey: "activationAngle"))) }
    private var jitterTolerance: Double { min(5, max(0, preferences.double(forKey: "jitterTolerance"))) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.register(defaults: [
            "enabled": true,
            "autoAnchor": true,
            "anchorDelay": AutoAnchor.defaultDelay,
            "blur": true,
            "tilt": true,
            "perspective": true,
            "showHUD": true,
            "angleMode": true,
            "activationAngle": EffectDefaults.activationAngle,
            "jitterTolerance": EffectDefaults.jitterTolerance
        ])

        enabled = preferences.bool(forKey: "enabled")

        guard let gpu = MTLCreateSystemDefaultDevice() else {
            showError("Metal is unavailable on this Mac.")
            NSApp.terminate(nil)
            return
        }

        do {
            renderer = try PlaneRenderer(gpu: gpu)
        } catch {
            showError(error.localizedDescription)
            NSApp.terminate(nil)
            return
        }

        renderer.blur = preferences.bool(forKey: "blur")
        renderer.warp = preferences.bool(forKey: "tilt")
        renderer.perspective = preferences.bool(forKey: "perspective")

        window = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "FoldingBook Overlay"
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        view = MTKView(frame: .zero, device: gpu)
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = renderer
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        renderer.onRenderComplete = { [weak self] success in
            guard let self, self.wantsOverlay else { return }
            if success {
                if self.window.alphaValue < 1 { self.logger.notice("First frame rendered; making overlay visible") }
                self.window.alphaValue = 1
            } else {
                self.window.orderOut(nil)
                self.logger.error("Overlay render failed; hiding panel")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "FoldingBook")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("FoldingBook: Click to toggle, right-click for options")
        }

        menu.delegate = self
        menu.autoenablesItems = false
        refreshStatus()

        if CommandLine.arguments.contains("--window-check") {
            runWindowCheck()
            return
        }

        do {
            shortcut = try GlobalShortcut { [weak self] in self?.toggleEnabled() }
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
        }

        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer!, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if let screen = DisplayEnvironment.usableBuiltInScreen() {
            fitOverlay(to: screen)
        }
        anchorHere()

        NSLog("FoldingBook menu bar ready; %@", sensor.diagnostic)
    }

    private func runWindowCheck() {
        let screen = NSScreen.main!
        fitOverlay(to: screen)
        renderer.blur = true
        renderer.warp = true
        renderer.perspective = true

        let artwork = PlaneRenderer.artwork()
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        let result = CVPixelBufferCreate(nil, artwork.width, artwork.height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
        guard result == kCVReturnSuccess, let pixelBuffer else { fatalError("Test pixel buffer unavailable") }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: artwork.width, height: artwork.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.draw(artwork, in: CGRect(x: 0, y: 0, width: artwork.width, height: artwork.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let accepted = renderer.setDesktopFrame(pixelBuffer)
        var shortcutCalls = 0
        do { shortcut = try GlobalShortcut { shortcutCalls += 1 } }
        catch { logger.error("\(error.localizedDescription, privacy: .public)") }
        let shortcutEventResult = GlobalShortcut.dispatchTestEvent()

        var sliderValue = 0.0
        let sliderCheck = MenuSlider(title: "Jitter tolerance", value: 2, range: 0...5, step: 0.5) { sliderValue = $0 }
        sliderCheck.slider.doubleValue = 1.1
        sliderCheck.slider.sendAction(sliderCheck.slider.action, to: sliderCheck.slider.target)
        let sliderPassed = sliderValue == 1 && sliderCheck.slider.doubleValue == 1

        renderer.delta = 0.6
        wantsOverlay = true
        window.alphaValue = 0
        window.orderFrontRegardless()

        var ticks = 0
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ticks == 10 { self.wantsOverlay = false; self.window.orderOut(nil) }
            if ticks == 15 { self.wantsOverlay = true; self.window.alphaValue = 0; self.window.orderFrontRegardless() }
            self.view.draw()
            ticks += 1
            if ticks == 30 {
                let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(self.window.windowNumber)) as? [[String: Any]] ?? []
                let onScreen = windows.first?[kCGWindowIsOnscreen as String] as? Bool == true
                var visiblePixels = false

                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(self.window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    if let center = bitmap.colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.deviceRGB) {
                        visiblePixels = center.alphaComponent > 0.99 && center.greenComponent > 0.05 && center.blueComponent > 0.05
                    }
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("window-check.png"))
                    }
                }
                let passed = accepted && visiblePixels && onScreen && sliderPassed && self.renderer.completedDraws > 20 && self.window.alphaValue == 1 && self.window.ignoresMouseEvents && !self.window.canBecomeKey && self.view.layer?.contentsScale == screen.backingScaleFactor && shortcutCalls == 1 && shortcutEventResult == 0
                let report = "\(passed ? "PASS" : "FAIL"): pixelBuffer=\(accepted) visiblePixels=\(visiblePixels) onScreen=\(onScreen) slider=\(sliderPassed) scale=\(self.view.layer?.contentsScale ?? 0) drawable=\(self.view.drawableSize) attempts=\(self.renderer.attemptedDraws) missing=\(self.renderer.missingDrawables) completed=\(self.renderer.completedDraws) shortcutCalls=\(shortcutCalls) clickThrough=\(self.window.ignoresMouseEvents) canBecomeKey=\(self.window.canBecomeKey)\n"
                try? report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("window-check.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let button = statusItem.button else { return }
            rebuildMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else {
            toggleEnabled()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        @discardableResult func item(_ title: String, _ action: Selector?, checked: Bool? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let checked { item.state = checked ? .on : .off }
            menu.addItem(item)
            return item
        }

        item("FoldingBook · \(status)", nil).isEnabled = false

        if !checkScreenCapturePermission() {
            let permItem = item("⚠️ Enable Screen Recording…", #selector(openPermissions))
            permItem.toolTip = "Click to open System Settings and toggle the switch for FoldingBook."
            menu.addItem(.separator())
        }

        let toggle = item(enabled ? "Disable Effect" : "Enable Effect", #selector(toggleEnabled))
        if shortcut != nil {
            toggle.keyEquivalent = "l"
            toggle.keyEquivalentModifierMask = [.control, .command]
        } else {
            item("⌃⌘L shortcut unavailable", nil).isEnabled = false
        }
        menu.addItem(.separator())

        item("Activate Below Angle", #selector(toggleAngleMode), checked: angleMode)
        let activation = NSMenuItem()
        activation.view = MenuSlider(title: "Activate at ≤", value: activationAngle, range: 10...180, step: 1, enabled: angleMode) { [weak self] value in
            self?.preferences.set(value, forKey: "activationAngle")
            self?.resetMotion()
        }
        menu.addItem(activation)

        let jitter = NSMenuItem()
        jitter.view = MenuSlider(title: "Jitter Tolerance", value: jitterTolerance, range: 0...5, step: 0.5) { [weak self] value in
            self?.preferences.set(value, forKey: "jitterTolerance")
            self?.resetMotion()
        }
        menu.addItem(jitter)
        menu.addItem(.separator())

        item("Anchor Here", #selector(anchorHere)).isEnabled = enabled && !angleMode
        item("Auto-Anchor on Rest", #selector(toggleAutoAnchor), checked: autoAnchor && !angleMode).isEnabled = !angleMode
        let delay = item("Delay Before Anchor", nil)
        let submenu = NSMenu()
        for value in [AutoAnchor.defaultDelay, 0.3, 0.5, 1.0, 2.0] {
            let choice = NSMenuItem(title: "\(value) seconds", action: #selector(setDelay(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = value
            choice.state = preferences.double(forKey: "anchorDelay") == value ? .on : .off
            submenu.addItem(choice)
        }
        delay.submenu = submenu
        delay.isEnabled = !angleMode
        menu.addItem(.separator())

        item("Progressive Blur", #selector(toggleBlur), checked: renderer.blur)
        item("Hold Visual Plane", #selector(toggleTilt), checked: renderer.warp)
        item("Perspective Projection", #selector(togglePerspective), checked: renderer.perspective)
        item("Show Lid Angle in Menu Bar", #selector(toggleHUD), checked: preferences.bool(forKey: "showHUD"))
        item("Simulate a Fold", #selector(toggleSimulation), checked: simulated).isEnabled = enabled
        menu.addItem(.separator())

        item("Screen Recording Settings…", #selector(openPermissions))
        item("Quit FoldingBook", #selector(quit))
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        preferences.set(enabled, forKey: "enabled")
        safety.reset()
        if enabled {
            anchorHere()
            update()
        } else {
            stopCapture()
            status = "Off"
        }
        refreshStatus()
    }

    private func startCapture() {
        guard enabled, !suspended, safety.state == .ready, capture == nil, !stoppingCapture,
              let screen = DisplayEnvironment.usableBuiltInScreen(),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }

        lastCaptureAttempt = CACurrentMediaTime()

        // Only start capture if screen recording permissions are actually preflight approved.
        // This permanently eliminates repeated macOS system permission modal popups.
        guard checkScreenCapturePermission(force: true) else {
            status = "Permission required"
            refreshStatus()
            return
        }

        fitOverlay(to: screen)
        capturedDisplay = displayID

        starting = true
        status = "Starting…"
        NSLog("FoldingBook: Starting ScreenCaptureKit capture on display %u...", displayID)
        let session = DesktopCapture()
        capture = session
        session.onFrame = { [weak self, weak session] buffer in
            guard let self, let session, self.capture === session, self.enabled else { return }
            let ok = self.renderer.setDesktopFrame(buffer)
            if ok && !self.hasFrame {
                self.hasFrame = true
                NSLog("FoldingBook: First desktop frame received: %zu x %zu", CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer))
            }
        }
        session.onError = { [weak self, weak session] error in
            guard let self, let session, self.capture === session else { return }
            NSLog("FoldingBook: Capture error: %@", error.localizedDescription)
            self.captureFailed(error)
        }
        Task { @MainActor in
            do {
                try await session.start(displayID: displayID)
                guard capture === session, enabled else {
                    await session.stop()
                    return
                }
                starting = false
                status = "Active"
                NSLog("FoldingBook: Capture started successfully")
                refreshStatus()
            } catch {
                guard capture === session else { return }
                NSLog("FoldingBook: session.start failed: %@", error.localizedDescription)
                captureFailed(error)
            }
        }
    }

    private func stopCapture(resetSimulation: Bool = true) {
        let previous = capture
        capture = nil
        starting = false
        hasFrame = false
        if resetSimulation { simulated = false }
        capturedDisplay = nil
        wantsOverlay = false
        window.orderOut(nil)
        renderer.delta = 0
        renderer.clearDesktopFrame()
        if let previous {
            stoppingCapture = true
            Task { @MainActor in
                await previous.stop()
                stoppingCapture = false
            }
        }
    }

    private func captureFailed(_ error: Error) {
        let now = CACurrentMediaTime()
        if suspended || environment.lidClosed(now: now) == true || DisplayEnvironment.usableBuiltInScreen() == nil || (now - lastReading <= 1 && current <= 5) {
            stopCapture()
            safety.reset()
            status = "Paused · display changing"
            refreshStatus()
            return
        }
        let error = error as NSError
        stopCapture()
        let denied = error.domain == SCStreamErrorDomain && error.code == -3801
        if denied || !checkScreenCapturePermission(force: true) {
            status = "Screen recording permission required"
        } else {
            status = "Capture unavailable"
        }
        refreshStatus()
    }

    private func update() {
        guard !suspended else { return }
        let now = CACurrentMediaTime()
        let pollInterval = enabled ? 1.0 / 30 : 0.2
        if (enabled || preferences.bool(forKey: "showHUD")), now - lastAnglePoll >= pollInterval {
            lastAnglePoll = now
            if let angle = sensor.read() {
                current = angle
                lastReading = now
            } else if enabled && now - lastSensorReconnect > 2 {
                lastSensorReconnect = now
                sensor = LidSensor()
            }
        }
        guard enabled else {
            refreshStatus()
            return
        }

        let dt = min(0.1, max(0, now - previousTick))
        previousTick = now
        let freshSensor = now - lastReading <= 1
        let screen = DisplayEnvironment.usableBuiltInScreen()
        let closed = environment.lidClosed(now: now) == true || (freshSensor && current <= 5)

        guard safety.update(lidClosed: closed, builtInAvailable: screen != nil, sensorAvailable: freshSensor || simulated, now: now) else {
            if capture != nil || wantsOverlay { stopCapture() }
            status = safety.state.rawValue
            refreshStatus()
            return
        }

        if let capturedDisplay, let screen,
           screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID != capturedDisplay {
            stopCapture()
            safety.reset()
            return
        }

        // Keep desktop capture running continuously while enabled and permitted.
        // Rate-limit start attempts to at least 2.5s to avoid tight retry loops.
        if capture == nil && !starting && (now - lastCaptureAttempt >= 2.5) && checkScreenCapturePermission() {
            startCapture()
        }

        let input = simulated ? demoAngle : current
        guard AngleActivation.allows(angle: input, limit: activationAngle, enabled: angleMode) else {
            motion.reset(to: activationAngle)
            renderer.delta = 0
            wantsOverlay = false
            window.orderOut(nil)
            status = "Armed · above \(Int(activationAngle))°"
            refreshStatus()
            return
        }

        let stableAngle = motion.update(input, tolerance: simulated ? 0 : jitterTolerance)
        anchor.delay = preferences.double(forKey: "anchorDelay")
        anchor.movementThreshold = max(0.1, jitterTolerance)
        anchor.update(angle: stableAngle, now: now, enabled: autoAnchor && !angleMode && !simulated)

        let reference = angleMode ? activationAngle : anchor.reference
        let target = Float((reference - stableAngle) * .pi / 180)
        renderer.delta += (target - renderer.delta) * Float(1 - exp(-dt / 0.08))

        guard CaptureDemand.needsCapture(delta: renderer.delta, blur: renderer.blur, warp: renderer.warp) else {
            wantsOverlay = false
            window.orderOut(nil)
            status = "Armed · resting"
            refreshStatus()
            return
        }

        status = starting ? "Starting…" : (simulated ? "Demo" : (checkScreenCapturePermission() ? "Active" : "Permission required"))

        wantsOverlay = hasFrame && abs(renderer.delta) > 0.002 && (renderer.blur || renderer.warp)
        if wantsOverlay {
            if let screen = DisplayEnvironment.usableBuiltInScreen() {
                fitOverlay(to: screen)
            }
            if !window.isVisible {
                window.alphaValue = 0
                window.orderFrontRegardless()
                logger.notice("Showing overlay; drawable \(self.view.drawableSize.width) x \(self.view.drawableSize.height)")
            }
            view.draw()
        } else {
            window.orderOut(nil)
        }
        refreshStatus()
    }

    private func refreshStatus() {
        statusItem?.button?.toolTip = "FoldingBook: \(status). Click or ⌃⌘L to toggle; right-click for options."
        statusItem?.button?.appearsDisabled = !enabled
        guard let button = statusItem?.button else { return }
        let showAngle = preferences.bool(forKey: "showHUD")
        let fresh = simulated || CACurrentMediaTime() - lastReading < 1
        let label = showAngle ? (fresh ? "\(Int(current.rounded()))°" : "—°") : ""
        if label != lastButtonLabel || (showAngle && button.image != nil) {
            lastButtonLabel = label
            statusItem.length = showAngle ? 44 : NSStatusItem.squareLength
            button.image = showAngle ? nil : NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "FoldingBook")
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = label
        }
    }

    @objc private func anchorHere() {
        if !simulated, let angle = sensor.read() {
            current = angle
            lastReading = CACurrentMediaTime()
        }
        anchor.anchor(at: current, now: CACurrentMediaTime())
        motion.reset(to: angleMode ? min(current, activationAngle) : current)
    }

    private func resetMotion() {
        renderer.delta = 0
        wantsOverlay = false
        window.orderOut(nil)
        anchorHere()
    }

    @objc private func toggleAngleMode() {
        preferences.set(!angleMode, forKey: "angleMode")
        resetMotion()
    }

    @objc private func toggleAutoAnchor() {
        autoAnchor.toggle()
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        preferences.set(sender.representedObject as? Double ?? AutoAnchor.defaultDelay, forKey: "anchorDelay")
    }

    @objc private func toggleBlur() {
        renderer.blur.toggle()
        preferences.set(renderer.blur, forKey: "blur")
    }

    @objc private func toggleTilt() {
        renderer.warp.toggle()
        preferences.set(renderer.warp, forKey: "tilt")
    }

    @objc private func togglePerspective() {
        renderer.perspective.toggle()
        preferences.set(renderer.perspective, forKey: "perspective")
    }

    @objc private func toggleHUD() {
        preferences.set(!preferences.bool(forKey: "showHUD"), forKey: "showHUD")
        refreshStatus()
    }

    @objc private func toggleSimulation() {
        simulated.toggle()
        if simulated {
            demoAngle = max(10, (angleMode ? activationAngle : anchor.reference) - 35)
        } else {
            resetMotion()
        }
    }

    @objc private func openPermissions() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func willSleep() {
        suspended = true
        safety.reset()
        stopCapture()
        status = "Paused · sleeping"
        refreshStatus()
    }

    @objc private func didWake() {
        suspended = false
        safety.reset()
        lastReading = 0
        sensor = LidSensor()
        if enabled { update() }
    }

    @objc private func displaysChanged() {
        guard enabled else { return }
        stopCapture()
        safety.reset()
        status = "Waiting for built-in display…"
        refreshStatus()
    }

    private func fitOverlay(to screen: NSScreen) {
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.layer?.contentsScale = screen.backingScaleFactor
        view.drawableSize = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        window?.orderOut(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "FoldingBook"
        alert.informativeText = message
        alert.runModal()
    }
}
