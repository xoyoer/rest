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
        timerEngine: TimerEngine
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
                wallpaperImage: wallpaperImage,
                isMainScreen: isMain
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
    let wallpaperImage: NSImage?
    let isMainScreen: Bool

    // Entrance animation
    @State private var showOverlay = false
    @State private var showQuote = false
    @State private var showBottom = false
    @State private var breatheIn = false
    @State private var currentTime = Date()

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

                // Current time — lock screen style, updates every minute
                VStack {
                    Text(currentTime, format: .dateTime.hour().minute())
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

                // Bottom — remaining time
                VStack {
                    Spacer()

                    let remaining = Int(timerEngine.restRemainingSeconds)
                    let min = remaining / 60
                    let sec = remaining % 60
                    Text(min > 0 ? "\(min):\(String(format: "%02d", sec))" : "\(sec)s")
                        .font(.system(size: 14, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .monospacedDigit()
                        .padding(.bottom, 50)
                }
                .opacity(showBottom ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onReceive(timerEngine.$restRemainingSeconds) { _ in
            currentTime = Date()
        }
        .onAppear {
            withAnimation(.easeIn(duration: 2.0)) {
                showOverlay = true
            }
            withAnimation(.easeIn(duration: 1.5).delay(1.0)) {
                showQuote = true
            }
            withAnimation(.easeIn(duration: 1.5).delay(1.5)) {
                showBottom = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breatheIn = true
                }
            }
        }
    }
}
