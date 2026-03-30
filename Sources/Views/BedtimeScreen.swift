import AppKit
import SwiftUI
import IOKit.pwr_mgt

// MARK: - BedtimeWindowController

@MainActor
class BedtimeWindowController {
    private var windows: [NSWindow] = []
    private var refocusTimer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0

    func show(
        quote: Quote,
        bedtimeEngine: BedtimeEngine,
        onRequestUnlock: @escaping () -> Void
    ) {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let mainScreen = NSScreen.main ?? screens[0]

        for screen in screens {
            let isMain = (screen == mainScreen)
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen)
            let wallpaperImage: NSImage? = wallpaperURL.flatMap { NSImage(contentsOf: $0) }

            let view = BedtimeScreenView(
                quote: quote,
                bedtimeEngine: bedtimeEngine,
                wallpaperImage: wallpaperImage,
                isMainScreen: isMain,
                onRequestUnlock: onRequestUnlock
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
            "xoyoer.idle bedtime lock active" as CFString,
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

// MARK: - BedtimeScreenView

struct BedtimeScreenView: View {
    let quote: Quote
    @ObservedObject var bedtimeEngine: BedtimeEngine
    let wallpaperImage: NSImage?
    let isMainScreen: Bool
    var onRequestUnlock: () -> Void

    @State private var showOverlay = false
    @State private var showQuote = false
    @State private var showBottom = false
    @State private var currentTime = Date()

    // Update time every minute
    private let minuteTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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

                // Dark overlay — no breathing, static and heavier than rest screen
                Color.black.opacity(showOverlay ? 0.75 : 0)

                // Current time
                VStack {
                    Text(currentTime, format: .dateTime.hour().minute())
                        .font(.system(size: 56, weight: .thin, design: .rounded))
                        .foregroundStyle(.white.opacity(showQuote ? 0.7 : 0))
                        .padding(.top, 80)
                    Spacer()
                }

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
                .offset(y: -20)
                .opacity(showQuote ? 1 : 0)

                // Bottom area — shutdown button + unlock hint
                if isMainScreen {
                    VStack(spacing: 16) {
                        Spacer()

                        // Shutdown button
                        Button(action: shutdownMac) {
                            HStack(spacing: 8) {
                                Image(systemName: "power")
                                    .font(.system(size: 14))
                                Text("关机")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Unlock hint
                        Text("点击菜单栏叶子图标临时解锁")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.2))

                        Spacer()
                            .frame(height: 40)
                    }
                    .opacity(showBottom ? 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onReceive(minuteTimer) { _ in
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
        }
    }

    private func shutdownMac() {
        let script = NSAppleScript(source: "tell application \"System Events\" to shut down")
        script?.executeAndReturnError(nil)
    }
}
