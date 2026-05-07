//
// KeyboardShortcuts.swift
// NeuralSDR2
//
// Centralized keyboard shortcut handler for UI interactions
//

import SwiftUI
import AppKit

public struct KeyboardShortcutHandler: ViewModifier {
    @EnvironmentObject var appState: AppState

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay(
                HiddenShortcutHandler(appState: appState)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            )
    }
}

private struct HiddenShortcutHandler: NSViewRepresentable {
    @ObservedObject var appState: AppState

    func makeNSView(context: Context) -> ShortcutResponderView {
        let view = ShortcutResponderView()
        view.appState = appState
        return view
    }

    func updateNSView(_ nsView: ShortcutResponderView, context: Context) {
        nsView.appState = appState
    }
}

private class ShortcutResponderView: NSView {
    var appState: AppState?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let state = self.appState else { return event }
                if self.handleKeyEvent(event, appState: state) {
                    return nil
                }
                return event
            }
        } else if window == nil, let mon = monitor {
            NSEvent.removeMonitor(mon)
            monitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent, appState: AppState) -> Bool {
        if isEditingTextInput {
            return false
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let keyCode = event.keyCode

        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        let opt = mods.contains(.option)
        let ctrl = mods.contains(.control)

        // Arrow keys for frequency tuning
        if keyCode == 126 { // Up arrow
            let step: Double
            if cmd { step = 100_000 }
            else if opt { step = 1_000_000 }
            else if shift { step = 10_000 }
            else { step = 1_000 }
            appState.setFrequency(appState.frequency + step)
            return true
        }
        if keyCode == 125 { // Down arrow
            let step: Double
            if cmd { step = 100_000 }
            else if opt { step = 1_000_000 }
            else if shift { step = 10_000 }
            else { step = 1_000 }
            appState.setFrequency(appState.frequency - step)
            return true
        }

        // Volume: +/- keys
        if key == "=" || key == "+" {
            _ = try? appState.audioEngine?.setVolume(min(1.0, appState.volume + 0.05))
            appState.volume = min(1.0, appState.volume + 0.05)
            return true
        }
        if key == "-" {
            _ = try? appState.audioEngine?.setVolume(max(0.0, appState.volume - 0.05))
            appState.volume = max(0.0, appState.volume - 0.05)
            return true
        }
        if key == "m" && !cmd {
            appState.toggleMuted()
            return true
        }

        // Display mode: Cmd+1/2/3
        if cmd && key == "1" {
            appState.displayMode = .spectrum
            return true
        }
        if cmd && key == "2" {
            appState.displayMode = .waterfall
            return true
        }
        if cmd && key == "3" {
            appState.displayMode = .combined
            return true
        }

        // Recording: Cmd+R
        if cmd && key == "r" && !shift {
            appState.toggleRecording()
            return true
        }

        // Start/Stop: Space or Cmd+Enter
        if keyCode == 49 && !cmd && !shift && !opt && !ctrl { // Space
            if appState.isRunning { appState.stopSDR() } else { appState.startSDR() }
            return true
        }
        if cmd && keyCode == 36 { // Cmd+Enter
            if appState.isRunning { appState.stopSDR() } else { appState.startSDR() }
            return true
        }

        // Bookmark: Cmd+B
        if cmd && key == "b" {
            appState.addCurrentBookmark()
            return true
        }

        // AGC toggle: Cmd+G
        if cmd && key == "g" {
            appState.agcEnabled.toggle()
            return true
        }

        // Squelch toggle: Cmd+S
        if cmd && key == "s" {
            appState.squelchEnabled.toggle()
            return true
        }

        return false
    }

    private var isEditingTextInput: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSTextView {
            return true
        }
        if let view = responder as? NSView, view is NSTextField {
            return true
        }
        return false
    }

    deinit {
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
        }
    }
}

extension View {
    public func keyboardShortcutHandler() -> some View {
        modifier(KeyboardShortcutHandler())
    }
}
