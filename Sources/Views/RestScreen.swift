import AppKit
import SwiftUI
import IOKit.pwr_mgt

// MARK: - LockdownPanel

class LockdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }
}

// MARK: - RestWindowController

@MainActor
class RestWindowController {
    private var windows: [NSWindow] = []
    private var refocusTimer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0

    func show(
        quote: Quote,
        timerEngine: TimerEngine,
        canSkip: Bool,
        onSkip: @escaping () -> Void
    ) {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let mainScreen = NSScreen.main ?? screens[0]

        for screen in screens {
            let isMain = (screen == mainScreen)
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen)
            let wallpaperImage: NSImage? = wallpaperURL.flatMap { NSImage(contentsOf: $0) }

            let view = RestScreenView(
                quote: quote,
                timerEngine: timerEngine,
                canSkip: canSkip,
                wallpaperImage: wallpaperImage,
                isMainScreen: isMain,
                onSkip: { [weak self] in
                    self?.dismiss()
                    onSkip()
                }
            )

            let hostingView = NSHostingView(rootView: view)
            hostingView.autoresizingMask = [.width, .height]

            let panel = LockdownPanel(
                contentRect: NSRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1
            )
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.contentView = hostingView
            panel.setFrame(screen.frame, display: true)
            panel.makeKeyAndOrderFront(nil)

            windows.append(panel)
        }

        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "xoyoer.idle rest screen active" as CFString,
            &sleepAssertionID
        )

        NSCursor.arrow.set()

        refocusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.windows.first?.makeKeyAndOrderFront(nil)
                NSCursor.arrow.set()
            }
        }
    }

    func dismiss() {
        refocusTimer?.invalidate()
        refocusTimer = nil

        for window in windows {
            window.close()
        }
        windows.removeAll()

        NSApp.presentationOptions = []

        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
    }
}

// MARK: - RestScreenView

struct RestScreenView: View {
    let quote: Quote
    @ObservedObject var timerEngine: TimerEngine
    let canSkip: Bool
    let wallpaperImage: NSImage?
    let isMainScreen: Bool
    let onSkip: () -> Void

    // Entrance animation
    @State private var showOverlay = false
    @State private var showQuote = false
    @State private var showBottom = false
    @State private var breatheIn = false

    // Long-press skip
    @State private var isHoldingSkip = false
    @State private var holdProgress: Double = 0
    @State private var mouseActive = false

    private let holdTicker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background wallpaper
                if let image = wallpaperImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                }

                // Animated overlay with breathing rhythm
                Color.black.opacity(showOverlay ? (breatheIn ? 0.63 : 0.57) : 0)

                // Current time — lock screen style
                VStack {
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 56, weight: .thin, design: .rounded))
                        .foregroundStyle(.white.opacity(showQuote ? 0.7 : 0))
                        .padding(.top, 80)
                    Spacer()
                }

                // Quote — staggered fade-in
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
                .offset(y: -40)
                .opacity(showQuote ? 1 : 0)

                // Bottom area — staggered fade-in
                VStack {
                    Spacer()

                    // Remaining time as subtle text
                    let remaining = Int(timerEngine.restRemainingSeconds)
                    let min = remaining / 60
                    let sec = remaining % 60
                    Text(min > 0 ? "\(min):\(String(format: "%02d", sec))" : "\(sec)s")
                        .font(.system(size: 14, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .monospacedDigit()
                        .padding(.bottom, 20)

                    skipArea
                        .opacity(mouseActive || isHoldingSkip ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: mouseActive)
                }
                .opacity(showBottom ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    mouseActive = true
                    // Auto-hide after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                        if !isHoldingSkip { mouseActive = false }
                    }
                case .ended:
                    if !isHoldingSkip { mouseActive = false }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Staggered entrance: overlay → quote → bottom
            withAnimation(.easeIn(duration: 2.0)) {
                showOverlay = true
            }
            withAnimation(.easeIn(duration: 1.5).delay(1.0)) {
                showQuote = true
            }
            withAnimation(.easeIn(duration: 1.5).delay(1.5)) {
                showBottom = true
            }
            // Start breathing animation after entrance
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breatheIn = true
                }
            }
        }
        .onReceive(holdTicker) { _ in
            guard isHoldingSkip, holdProgress < 1.0 else { return }
            holdProgress += 0.01 // 50ms × 100 ticks = 5 seconds
            if holdProgress >= 1.0 {
                isHoldingSkip = false
                onSkip()
            }
        }
    }

    // MARK: - Skip Area (Long-press)

    @ViewBuilder
    private var skipArea: some View {
        if !isMainScreen {
            Spacer().frame(height: 60)
        } else if !canSkip {
            Text("今日跳过机会已用完")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.bottom, 50)
        } else {
            VStack(spacing: 14) {
                // Reflection text — appears when holding
                if isHoldingSkip {
                    Text(GuardianLock.shared.todaySkipPhrase)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                // Hold circle
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                        .frame(width: 76, height: 76)

                    // Progress ring
                    if holdProgress > 0 {
                        Circle()
                            .trim(from: 0, to: holdProgress)
                            .stroke(
                                Color.white.opacity(0.5),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 76, height: 76)
                    }

                    // Center content
                    if isHoldingSkip {
                        let remaining = max(1, Int(ceil(5.0 * (1.0 - holdProgress))))
                        Text("\(remaining)")
                            .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .monospacedDigit()
                    } else {
                        VStack(spacing: 2) {
                            Text("按住")
                                .font(.system(size: 11, weight: .light))
                            Text("跳过")
                                .font(.system(size: 11, weight: .light))
                        }
                        .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isHoldingSkip {
                                isHoldingSkip = true
                                holdProgress = 0
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                isHoldingSkip = false
                                holdProgress = 0
                            }
                        }
                )

                // Hint
                Text(isHoldingSkip ? "松开取消" : "今日仅 1 次机会")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(isHoldingSkip ? 0.3 : 0.2))
            }
            .padding(.bottom, 50)
            .animation(.easeInOut(duration: 0.3), value: isHoldingSkip)
        }
    }
}
