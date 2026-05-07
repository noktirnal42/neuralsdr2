// NeuralSDR2App.swift
// NeuralSDR2 - Application Entry Point

import SwiftUI
import NeuralSDR2Kit

@main
struct NeuralSDR2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("SDR") {
                Button("Start") {
                    appState.startSDR()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Stop") {
                    appState.stopSDR()
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Scan Devices") {
                    appState.scanForDevices()
                }
            }
            CommandMenu("View") {
                Button("Spectrum Only") {
                    appState.workspace = .radio
                    appState.displayMode = .spectrum
                }
                Button("Waterfall Only") {
                    appState.workspace = .radio
                    appState.displayMode = .waterfall
                }
                Button("Combined") {
                    appState.workspace = .radio
                    appState.displayMode = .combined
                }
                Divider()
                Button("Aircraft Map") {
                    appState.workspace = .aircraft
                }
                Button("Satellite Operations") {
                    appState.workspace = .satellites
                }
                Button("3D Earth") {
                    appState.workspace = .earth
                }
                Button("Recordings") {
                    appState.workspace = .recordings
                }
            }
            CommandMenu("Demodulator") {
                ForEach(DemodulatorType.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        appState.setMode(mode)
                    }
                    .keyboardShortcut(mode.shortcut)
                }
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("NeuralSDR2 launched - Debug mode")
        #else
        print("NeuralSDR2 launched")
        #endif
        NSLog("NeuralSDR2 AppDelegate did finish launching")
        presentMainWindowIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup handled by deinitializers
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            presentMainWindowIfNeeded()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func presentMainWindowIfNeeded() {
        NSApp.activate(ignoringOtherApps: true)
        NSLog("NeuralSDR2 evaluating main window presentation, window count=%ld", NSApp.windows.count)

        if let existingWindow = fallbackWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let existingWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.frame.width > 200 && $0.frame.height > 200
        }) {
            NSLog("NeuralSDR2 reusing existing visible window with frame %@", NSStringFromRect(existingWindow.frame))
            existingWindow.makeKeyAndOrderFront(nil)
            fallbackWindow = existingWindow
            return
        }

        for window in NSApp.windows where window.frame.width <= 200 || window.frame.height <= 200 {
            NSLog("NeuralSDR2 hiding placeholder window with frame %@", NSStringFromRect(window.frame))
            window.orderOut(nil)
        }

        let rootView = ContentView()
            .environmentObject(AppState.shared)
            .frame(minWidth: 1200, minHeight: 800)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: rootView)
        window.title = "NeuralSDR2"
        window.minSize = NSSize(width: 1200, height: 800)
        window.center()
        window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: true)
        window.setFrameAutosaveName("NeuralSDR2MainWindow")
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSLog("NeuralSDR2 created fallback window with frame %@", NSStringFromRect(window.frame))
        fallbackWindow = window
    }
}
