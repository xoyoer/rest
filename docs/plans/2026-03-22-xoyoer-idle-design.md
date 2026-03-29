# xoyoer.idle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar app that monitors screen usage and enforces healthy break habits through a two-layer reminder system (gentle nudge + forced full-screen rest).

**Architecture:** SwiftUI menu bar app with AppKit integration for system-level features (CGEvent tap for input monitoring, NSPanel for full-screen lockdown). Core logic (timer engine, fatigue calculator, activity monitor) is separated from UI for testability. Data persisted locally via SwiftData. Built with `swiftc` directly + build script (no Xcode.app required).

**Tech Stack:** Swift 6.2 / SwiftUI / AppKit / SwiftData / Swift Charts / CGEvent / NSPanel / SMAppService

---

## Project Structure

```
/Users/xoyoer/xoyoerai/05-本地程序/idle/
├── Sources/
│   ├── App/
│   │   ├── IdleApp.swift              # App entry point, menu bar setup
│   │   └── AppDelegate.swift          # NSApplicationDelegate for system integration
│   ├── Core/
│   │   ├── ActivityMonitor.swift      # CGEvent tap, keyboard/mouse monitoring
│   │   ├── TimerEngine.swift          # Work/rest cycle state machine
│   │   ├── FatigueCalculator.swift    # Fatigue percentage calculation
│   │   └── QuoteManager.swift         # Random quote selection
│   ├── Views/
│   │   ├── MenuBarPopover.swift       # Menu bar popover content
│   │   ├── RestScreen.swift           # Full-screen forced rest overlay
│   │   ├── SettingsWindow.swift       # Settings window
│   │   └── HistoryCharts.swift        # Usage history charts
│   ├── Models/
│   │   ├── UsageRecord.swift          # SwiftData model for daily usage
│   │   ├── AppSettings.swift          # UserDefaults wrapper
│   │   └── Quote.swift                # Quote data model
│   └── Resources/
│       └── Quotes.json               # Built-in quotes library
├── Tests/
│   ├── TimerEngineTests.swift
│   ├── FatigueCalculatorTests.swift
│   └── ActivityMonitorTests.swift
├── build.sh                           # Build script
├── Info.plist                         # App metadata + permissions
├── idle.entitlements                  # App sandbox entitlements
└── docs/plans/
```

---

## Task 1: Project Scaffold + Build Verification

**Files:**
- Create: `Sources/App/IdleApp.swift`
- Create: `Sources/App/AppDelegate.swift`
- Create: `Info.plist`
- Create: `idle.entitlements`
- Create: `build.sh`

**Step 1: Create app entry point**

```swift
// Sources/App/IdleApp.swift
import SwiftUI

@main
struct IdleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Text("xoyoer.idle")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "eye")
        }

        Settings {
            Text("Settings placeholder")
                .frame(width: 400, height: 300)
        }
    }
}
```

```swift
// Sources/App/AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }
}
```

**Step 2: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>xoyoer.idle</string>
    <key>CFBundleDisplayName</key>
    <string>xoyoer.idle</string>
    <key>CFBundleIdentifier</key>
    <string>com.xoyoer.idle</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>idle</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 xoyoer. All rights reserved.</string>
</dict>
</plist>
```

**Step 3: Create build script**

```bash
#!/bin/bash
set -e

APP_NAME="xoyoer.idle"
BUNDLE_NAME="$APP_NAME.app"
BUILD_DIR="build"
SOURCES=$(find Sources -name "*.swift")
SDK=$(xcrun --show-sdk-path)
TARGET="arm64-apple-macosx14.0"

echo "Building $APP_NAME..."

# Clean
rm -rf "$BUILD_DIR"

# Create .app bundle structure
mkdir -p "$BUILD_DIR/$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUILD_DIR/$BUNDLE_NAME/Contents/Resources"

# Compile
swiftc $SOURCES \
    -o "$BUILD_DIR/$BUNDLE_NAME/Contents/MacOS/idle" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -parse-as-library \
    -O

# Copy resources
cp Info.plist "$BUILD_DIR/$BUNDLE_NAME/Contents/"
if [ -f Sources/Resources/Quotes.json ]; then
    cp Sources/Resources/Quotes.json "$BUILD_DIR/$BUNDLE_NAME/Contents/Resources/"
fi

echo "Build complete: $BUILD_DIR/$BUNDLE_NAME"
echo "Run: open $BUILD_DIR/$BUNDLE_NAME"
```

**Step 4: Build and verify**

Run: `cd /Users/xoyoer/xoyoerai/05-本地程序/idle && chmod +x build.sh && ./build.sh`
Expected: Build succeeds, `build/xoyoer.idle.app` created

**Step 5: Launch and verify menu bar icon appears**

Run: `open build/xoyoer.idle.app`
Expected: Eye icon appears in menu bar, clicking shows "xoyoer.idle" text and Quit button

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: project scaffold with menu bar app skeleton"
```

---

## Task 2: Activity Monitor — Input Detection

**Files:**
- Create: `Sources/Core/ActivityMonitor.swift`
- Modify: `Sources/App/AppDelegate.swift`

**Step 1: Create ActivityMonitor**

```swift
// Sources/Core/ActivityMonitor.swift
import AppKit
import Combine

@MainActor
class ActivityMonitor: ObservableObject {
    @Published var lastActivityTime: Date = Date()
    @Published var isIdle: Bool = false
    @Published var isScreenLocked: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var idleCheckTimer: Timer?

    /// Idle threshold in seconds (default 180 = 3 minutes)
    var idleThreshold: TimeInterval = 180

    func start() {
        startEventTap()
        startIdleCheckTimer()
        observeScreenLock()
    }

    func stop() {
        stopEventTap()
        idleCheckTimer?.invalidate()
    }

    // MARK: - CGEvent Tap

    private func startEventTap() {
        let eventMask: CGEventMask = (
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        )

        // Store reference to self for the C callback
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, _, userInfo in
                guard let userInfo = userInfo else { return nil }
                let monitor = Unmanaged<ActivityMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                Task { @MainActor in
                    monitor.recordActivity()
                }
                return nil
            },
            userInfo: userInfo
        )

        guard let eventTap = eventTap else {
            print("⚠️ Failed to create event tap. Grant Accessibility permission in System Settings > Privacy & Security > Accessibility.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func stopEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func recordActivity() {
        lastActivityTime = Date()
        if isIdle {
            isIdle = false
        }
    }

    // MARK: - Idle Detection

    private func startIdleCheckTimer() {
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }
    }

    private func checkIdleState() {
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        let shouldBeIdle = elapsed >= idleThreshold || isScreenLocked
        if shouldBeIdle != isIdle {
            isIdle = shouldBeIdle
        }
    }

    // MARK: - Screen Lock Detection

    private func observeScreenLock() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func screenLocked() {
        Task { @MainActor in
            isScreenLocked = true
            isIdle = true
        }
    }

    @objc private func screenUnlocked() {
        Task { @MainActor in
            isScreenLocked = false
            recordActivity()
        }
    }

    deinit {
        stop()
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
```

**Step 2: Wire into AppDelegate**

Update AppDelegate to start monitoring on launch.

**Step 3: Build and test**

Run: `./build.sh && open build/xoyoer.idle.app`
Expected: App launches. System prompts for Accessibility permission. After granting, input events are detected.

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: activity monitor with CGEvent tap and idle detection"
```

---

## Task 3: Timer Engine — Work/Rest Cycle State Machine

**Files:**
- Create: `Sources/Core/TimerEngine.swift`
- Create: `Sources/Core/FatigueCalculator.swift`

**Step 1: Create TimerEngine**

```swift
// Sources/Core/TimerEngine.swift
import Foundation
import Combine

enum TimerState: Equatable {
    case working          // User is working, timer counting up
    case idle             // User is idle, work timer paused
    case lightReminder    // Light reminder triggered (30 min)
    case resting          // Forced rest in progress
}

@MainActor
class TimerEngine: ObservableObject {
    // MARK: - Published State
    @Published var state: TimerState = .working
    @Published var continuousWorkSeconds: TimeInterval = 0
    @Published var todayTotalSeconds: TimeInterval = 0
    @Published var todayRestCount: Int = 0
    @Published var restRemainingSeconds: TimeInterval = 0
    @Published var skipUsedToday: Bool = false

    // MARK: - Settings
    var workDurationMinutes: Int = 60          // 60-90 min
    var restDurationMinutes: Int = 15          // 15-30 min
    var lightReminderMinutes: Int = 30         // Light reminder interval

    // MARK: - Private
    private var timer: Timer?
    private var restTimer: Timer?
    private var onLightReminder: (() -> Void)?
    private var onForceRest: (() -> Void)?
    private var onRestComplete: (() -> Void)?

    func configure(
        onLightReminder: @escaping () -> Void,
        onForceRest: @escaping () -> Void,
        onRestComplete: @escaping () -> Void
    ) {
        self.onLightReminder = onLightReminder
        self.onForceRest = onForceRest
        self.onRestComplete = onRestComplete
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        restTimer?.invalidate()
    }

    // MARK: - State Transitions

    func userBecameActive() {
        if state == .idle {
            state = .working
        }
    }

    func userBecameIdle() {
        if state == .working || state == .lightReminder {
            state = .idle
        }
    }

    func startForcedRest() {
        state = .resting
        restRemainingSeconds = TimeInterval(restDurationMinutes * 60)
        todayRestCount += 1
        onForceRest?()

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.restTick()
            }
        }
    }

    func skipRest() -> Bool {
        guard !skipUsedToday else { return false }
        skipUsedToday = true
        endRest()
        return true
    }

    func resetDaily() {
        todayTotalSeconds = 0
        todayRestCount = 0
        skipUsedToday = false
        continuousWorkSeconds = 0
    }

    // MARK: - Tick Logic

    private func tick() {
        guard state == .working || state == .lightReminder else { return }

        continuousWorkSeconds += 1
        todayTotalSeconds += 1

        // Check light reminder (every 30 min of continuous work)
        let lightInterval = TimeInterval(lightReminderMinutes * 60)
        if continuousWorkSeconds.truncatingRemainder(dividingBy: lightInterval) == 0 && continuousWorkSeconds > 0 {
            onLightReminder?()
        }

        // Check forced rest
        let workLimit = TimeInterval(workDurationMinutes * 60)
        if continuousWorkSeconds >= workLimit {
            startForcedRest()
        }
    }

    private func restTick() {
        restRemainingSeconds -= 1
        if restRemainingSeconds <= 0 {
            endRest()
        }
    }

    private func endRest() {
        restTimer?.invalidate()
        continuousWorkSeconds = 0
        state = .working
        onRestComplete?()
    }
}
```

**Step 2: Create FatigueCalculator**

```swift
// Sources/Core/FatigueCalculator.swift
import Foundation

struct FatigueCalculator {
    /// Calculate fatigue percentage (0-100) based on continuous work time
    /// Reaches 100% at the configured work duration limit
    static func calculate(
        continuousWorkSeconds: TimeInterval,
        workLimitMinutes: Int
    ) -> Int {
        let limitSeconds = TimeInterval(workLimitMinutes * 60)
        guard limitSeconds > 0 else { return 0 }
        let ratio = continuousWorkSeconds / limitSeconds
        return min(100, max(0, Int(ratio * 100)))
    }

    /// Format seconds into "X小时Y分" display string
    static func formatDuration(_ totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        } else {
            return "\(minutes)分钟"
        }
    }

    /// Format seconds into "MM:SS" countdown string
    static func formatCountdown(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
```

**Step 3: Build and verify**

Run: `./build.sh`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: timer engine with work/rest state machine and fatigue calculator"
```

---

## Task 4: Quote Manager + Quotes Library

**Files:**
- Create: `Sources/Core/QuoteManager.swift`
- Create: `Sources/Models/Quote.swift`
- Create: `Sources/Resources/Quotes.json`

**Step 1: Create Quote model and manager**

```swift
// Sources/Models/Quote.swift
import Foundation

struct Quote: Codable, Sendable {
    let en: String
    let zh: String
    let author: String?
}
```

```swift
// Sources/Core/QuoteManager.swift
import Foundation

struct QuoteManager: Sendable {
    private let quotes: [Quote]

    init() {
        // Load from bundle or fallback to built-in
        if let url = Bundle.main.url(forResource: "Quotes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([Quote].self, from: data) {
            quotes = loaded
        } else {
            quotes = QuoteManager.builtInQuotes
        }
    }

    func random() -> Quote {
        quotes.randomElement() ?? Quote(en: "Take a break.", zh: "休息一下。", author: nil)
    }

    private static let builtInQuotes: [Quote] = [
        Quote(en: "Take rest; a field that has rested gives a bountiful crop.", zh: "适当休息；休耕的土地才能丰收。", author: "Ovid"),
        Quote(en: "The time to relax is when you don't have time for it.", zh: "最该放松的时刻，恰恰是你觉得没时间放松的时候。", author: "Sydney Harris"),
        Quote(en: "Almost everything will work again if you unplug it for a few minutes, including you.", zh: "几乎所有东西拔掉插头几分钟再重启都能恢复，包括你自己。", author: "Anne Lamott"),
        Quote(en: "Your body is not a machine. It is a garden. It requires tending.", zh: "你的身体不是机器，是一座花园，需要照料。", author: nil),
        Quote(en: "He who has health has hope, and he who has hope has everything.", zh: "有健康就有希望，有希望就有一切。", author: nil)
    ]
}
```

**Step 2: Create full Quotes.json**

Create `Sources/Resources/Quotes.json` with 30+ curated health-themed quotes in Chinese-English pairs.

**Step 3: Build and verify**

Run: `./build.sh`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: quote manager with 30+ health-themed bilingual quotes"
```

---

## Task 5: Menu Bar Popover UI

**Files:**
- Create: `Sources/Views/MenuBarPopover.swift`
- Modify: `Sources/App/IdleApp.swift`

**Step 1: Create popover view**

```swift
// Sources/Views/MenuBarPopover.swift
import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var timerEngine: TimerEngine
    let onStartRest: () -> Void
    let onOpenSettings: () -> Void

    var fatiguePercent: Int {
        FatigueCalculator.calculate(
            continuousWorkSeconds: timerEngine.continuousWorkSeconds,
            workLimitMinutes: timerEngine.workDurationMinutes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text("xoyoer.idle")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            // Stats grid
            HStack(spacing: 20) {
                StatBlock(
                    label: "疲劳值",
                    value: "\(fatiguePercent)%"
                )
                StatBlock(
                    label: "今日时长",
                    value: FatigueCalculator.formatDuration(timerEngine.todayTotalSeconds)
                )
            }

            // Next rest countdown
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                let remaining = max(0, TimeInterval(timerEngine.workDurationMinutes * 60) - timerEngine.continuousWorkSeconds)
                Text("距下次休息 \(FatigueCalculator.formatCountdown(remaining))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            // Rest count
            HStack {
                Image(systemName: "leaf")
                    .foregroundStyle(.secondary)
                Text("今日已休息 \(timerEngine.todayRestCount) 次")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Divider()

            // Actions
            Button(action: onStartRest) {
                Label("立即休息", systemImage: "pause.circle")
            }
            .buttonStyle(.borderless)

            Button(action: onOpenSettings) {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("退出", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 260)
    }
}

struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

**Step 2: Update IdleApp to wire popover with TimerEngine and ActivityMonitor**

Connect the views with the core logic, set up callbacks for light reminders and forced rest.

**Step 3: Update menu bar label to show fatigue percentage**

Dynamic label: show fatigue % next to the eye icon.

**Step 4: Build, launch, verify**

Run: `./build.sh && open build/xoyoer.idle.app`
Expected: Menu bar shows eye icon + fatigue %. Clicking opens popover with stats, countdown, and buttons.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: menu bar popover with stats, countdown, and actions"
```

---

## Task 6: Forced Rest Screen (Full-Screen Lockdown)

**Files:**
- Create: `Sources/Views/RestScreen.swift`

**Step 1: Create full-screen rest overlay**

```swift
// Sources/Views/RestScreen.swift
import SwiftUI
import AppKit

// MARK: - Rest Window Controller

class RestWindowController {
    private var windows: [NSWindow] = []

    func show(
        quote: Quote,
        duration: TimeInterval,
        canSkip: Bool,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        // Create a window for each screen
        for screen in NSScreen.screens {
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isMovable = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            // Get desktop wallpaper for this screen
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen)
            let wallpaperImage: NSImage? = wallpaperURL.flatMap { NSImage(contentsOf: $0) }

            let isMainScreen = screen == NSScreen.main

            let contentView = RestScreenView(
                quote: quote,
                totalDuration: duration,
                canSkip: canSkip,
                wallpaperImage: wallpaperImage,
                isMainScreen: isMainScreen,
                onSkip: { [weak self] in
                    onSkip()
                    self?.dismiss()
                },
                onComplete: { [weak self] in
                    onComplete()
                    self?.dismiss()
                }
            )

            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        // Capture mouse to prevent switching apps
        NSCursor.hide()
    }

    func dismiss() {
        NSCursor.unhide()
        for window in windows {
            window.close()
        }
        windows.removeAll()
    }
}

// MARK: - Rest Screen SwiftUI View

struct RestScreenView: View {
    let quote: Quote
    let totalDuration: TimeInterval
    let canSkip: Bool
    let wallpaperImage: NSImage?
    let isMainScreen: Bool
    let onSkip: () -> Void
    let onComplete: () -> Void

    @State private var remainingSeconds: TimeInterval
    @State private var timer: Timer?

    init(
        quote: Quote,
        totalDuration: TimeInterval,
        canSkip: Bool,
        wallpaperImage: NSImage?,
        isMainScreen: Bool,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.quote = quote
        self.totalDuration = totalDuration
        self.canSkip = canSkip
        self.wallpaperImage = wallpaperImage
        self.isMainScreen = isMainScreen
        self.onSkip = onSkip
        self.onComplete = onComplete
        self._remainingSeconds = State(initialValue: totalDuration)
    }

    var body: some View {
        ZStack {
            // Background: desktop wallpaper or dark fallback
            if let image = wallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }

            // Dim overlay
            Color.black.opacity(0.6)

            if isMainScreen {
                // Main content only on primary screen
                VStack(spacing: 40) {
                    Spacer()

                    // Quote
                    VStack(spacing: 16) {
                        Text(quote.en)
                            .font(.title2)
                            .fontWeight(.light)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)

                        Text(quote.zh)
                            .font(.title3)
                            .fontWeight(.light)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))

                        if let author = quote.author {
                            Text("— \(author)")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 80)

                    Spacer()

                    // Countdown
                    Text(FatigueCalculator.formatCountdown(remainingSeconds))
                        .font(.system(size: 48, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()

                    // Skip button
                    if canSkip {
                        Button(action: onSkip) {
                            Text("跳过本次（今日仅剩 1 次）")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                        .frame(height: 60)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { startCountdown() }
        .onDisappear { timer?.invalidate() }
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                timer?.invalidate()
                onComplete()
            }
        }
    }
}
```

**Step 2: Wire RestWindowController into app flow**

When TimerEngine triggers forced rest → show RestWindowController. When rest completes or user skips → dismiss.

**Step 3: Build, launch, test forced rest**

Run: `./build.sh && open build/xoyoer.idle.app`
Test: Set work duration to 1 minute temporarily, wait for forced rest to trigger. Verify:
- Full-screen lockdown covers all screens
- Desktop wallpaper visible behind dark overlay
- Quote displayed in center
- Countdown ticking
- Skip button works (once only)
- Cannot Cmd+Tab, click through, or drag

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: full-screen forced rest with wallpaper, quotes, and skip logic"
```

---

## Task 7: Light Reminder (Notification + Menu Bar Flash)

**Files:**
- Create: `Sources/Core/NotificationManager.swift`

**Step 1: Create notification manager**

```swift
// Sources/Core/NotificationManager.swift
import UserNotifications

class NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendLightReminder() {
        let content = UNMutableNotificationContent()
        content.title = "xoyoer.idle"
        content.body = "已连续工作 30 分钟，站起来活动一下"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "light-reminder-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

**Step 2: Add menu bar icon flash animation**

When light reminder triggers, animate the menu bar icon (e.g., alternate between `eye` and `eye.trianglebadge.exclamationmark` for a few seconds).

**Step 3: Wire into TimerEngine's onLightReminder callback**

**Step 4: Build and test**

Run: `./build.sh && open build/xoyoer.idle.app`
Expected: After 30 min continuous work (or test with shorter interval), system notification appears and menu bar icon flashes briefly.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: light reminder with system notification and menu bar flash"
```

---

## Task 8: Settings Window

**Files:**
- Create: `Sources/Views/SettingsWindow.swift`
- Create: `Sources/Models/AppSettings.swift`

**Step 1: Create AppSettings (UserDefaults wrapper)**

```swift
// Sources/Models/AppSettings.swift
import Foundation

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var workDurationMinutes: Int {
        didSet { UserDefaults.standard.set(workDurationMinutes, forKey: "workDuration") }
    }
    @Published var restDurationMinutes: Int {
        didSet { UserDefaults.standard.set(restDurationMinutes, forKey: "restDuration") }
    }
    @Published var idleThresholdMinutes: Int {
        didSet { UserDefaults.standard.set(idleThresholdMinutes, forKey: "idleThreshold") }
    }
    @Published var lightReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(lightReminderEnabled, forKey: "lightReminder") }
    }
    @Published var lightReminderMinutes: Int {
        didSet { UserDefaults.standard.set(lightReminderMinutes, forKey: "lightReminderInterval") }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    private init() {
        let d = UserDefaults.standard
        workDurationMinutes = d.object(forKey: "workDuration") as? Int ?? 60
        restDurationMinutes = d.object(forKey: "restDuration") as? Int ?? 15
        idleThresholdMinutes = d.object(forKey: "idleThreshold") as? Int ?? 3
        lightReminderEnabled = d.object(forKey: "lightReminder") as? Bool ?? true
        lightReminderMinutes = d.object(forKey: "lightReminderInterval") as? Int ?? 30
        launchAtLogin = d.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
```

**Step 2: Create SettingsWindow**

Single scrollable window with Apple-native styling. Sections:
- 工作与休息 (work/rest durations, idle threshold)
- 提醒 (light reminder toggle + interval)
- 通用 (launch at login, keyboard shortcuts)

Use native SwiftUI Form with sliders and toggles to match System Settings aesthetic.

**Step 3: Wire Settings into TimerEngine and ActivityMonitor**

When settings change, update the running engine parameters.

**Step 4: Implement launch at login via SMAppService**

```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        print("Launch at login error: \(error)")
    }
}
```

**Step 5: Build and test**

Run: `./build.sh && open build/xoyoer.idle.app`
Expected: Settings window opens from popover. Sliders/toggles work. Changes persist after restart.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: settings window with persistent preferences and launch at login"
```

---

## Task 9: Data Persistence + History Charts

**Files:**
- Create: `Sources/Models/UsageRecord.swift`
- Create: `Sources/Views/HistoryCharts.swift`

**Step 1: Create SwiftData model**

```swift
// Sources/Models/UsageRecord.swift
import SwiftData
import Foundation

@Model
class UsageRecord {
    var date: Date
    var totalSeconds: TimeInterval
    var restCount: Int
    var peakFatiguePercent: Int

    init(date: Date, totalSeconds: TimeInterval, restCount: Int, peakFatiguePercent: Int) {
        self.date = date
        self.totalSeconds = totalSeconds
        self.restCount = restCount
        self.peakFatiguePercent = peakFatiguePercent
    }
}
```

**Step 2: Add data saving logic**

Save current session data periodically (every 5 minutes) and on app quit. One record per day, updated incrementally.

**Step 3: Create HistoryCharts view**

Use Swift Charts framework:
- Bar chart for daily usage hours
- Toggle between: 过去7天 / 过去28天 / 过去90天
- Show rest count overlay

**Step 4: Add history section to Settings window**

Place charts in the Settings window as a section.

**Step 5: Build and test**

Run: `./build.sh && open build/xoyoer.idle.app`
Expected: After some usage, charts show data. Switching time ranges works.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: usage history with SwiftData persistence and Swift Charts"
```

---

## Task 10: Keyboard Shortcuts

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

**Step 1: Register global shortcuts**

- `⇧⌘B` — 手动开始休息
- `⇧⌘I` — 显示/隐藏主窗口

Use `NSEvent.addGlobalMonitorForEvents` for global hotkeys.

**Step 2: Build and test**

Verify shortcuts work from any app.

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: global keyboard shortcuts for manual rest and toggle window"
```

---

## Task 11: Daily Reset + Polish

**Files:**
- Modify: `Sources/Core/TimerEngine.swift`
- Modify: `Sources/App/AppDelegate.swift`

**Step 1: Add daily reset logic**

At midnight (or on wake after midnight), reset daily counters: total time, rest count, skip usage.

**Step 2: Add accessibility permission prompt**

On first launch, if CGEvent tap fails, show a user-friendly alert explaining how to grant Accessibility permission, with a button to open System Settings.

**Step 3: App icon**

Create a minimal app icon (eye symbol in xoyoer brand style: warm white #F5F3EE background, charcoal #2D2D2D icon).

**Step 4: Final build and test full flow**

Run: `./build.sh && open build/xoyoer.idle.app`

Full test checklist:
- [ ] Menu bar icon appears, no dock icon
- [ ] Popover shows correct stats
- [ ] Light reminder fires at 30 min
- [ ] Forced rest fires at configured work duration
- [ ] Rest screen covers all screens, cannot bypass
- [ ] Desktop wallpaper visible behind overlay
- [ ] Quote displays correctly (Chinese + English)
- [ ] Countdown works
- [ ] Skip works once, then disabled
- [ ] Settings persist after restart
- [ ] History charts display data
- [ ] Keyboard shortcuts work
- [ ] Launch at login works
- [ ] Idle detection pauses work timer
- [ ] Screen lock immediately counts as rest
- [ ] Daily reset at midnight

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: daily reset, accessibility prompt, app icon, and polish"
```

---

## Execution Notes

- **Build command:** `./build.sh` from project root
- **Launch:** `open build/xoyoer.idle.app`
- **Required permission:** System Settings > Privacy & Security > Accessibility > add xoyoer.idle
- **No Xcode required:** Built entirely with `swiftc` CLI + build script
- **macOS 14+ required** (current system: macOS 26.3, fully compatible)
