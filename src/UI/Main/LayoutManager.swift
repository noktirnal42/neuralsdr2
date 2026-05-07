//
// LayoutManager.swift
// NeuralSDR2
//
// Persistent layout management for panel configurations
//

import SwiftUI

public enum LayoutPreset: String, CaseIterable {
    case `default` = "Default"
    case compact = "Compact"
    case wide = "Wide"
    case fullScreen = "Full Screen"

    public var sidebarWidth: CGFloat {
        switch self {
        case .default: return 250
        case .compact: return 200
        case .wide: return 280
        case .fullScreen: return 300
        }
    }

    public var inspectorWidth: CGFloat {
        switch self {
        case .default: return 280
        case .compact: return 220
        case .wide: return 300
        case .fullScreen: return 320
        }
    }

    public var sidebarVisible: Bool {
        switch self {
        case .fullScreen: return true
        default: return true
        }
    }

    public var inspectorVisible: Bool {
        switch self {
        case .compact: return false
        default: return true
        }
    }
}

public class LayoutManager: ObservableObject {
    private static let storageKey = "com.neuralsdr2.layout"

    @Published public var sidebarWidth: CGFloat = 250
    @Published public var inspectorWidth: CGFloat = 280
    @Published public var sidebarVisible: Bool = true
    @Published public var inspectorVisible: Bool = true
    @Published public var displayMode: AppState.DisplayMode = .combined

    public init() {
        load()
    }

    public func applyPreset(_ preset: LayoutPreset) {
        sidebarWidth = preset.sidebarWidth
        inspectorWidth = preset.inspectorWidth
        sidebarVisible = preset.sidebarVisible
        inspectorVisible = preset.inspectorVisible
        save()
    }

    public func toggleSidebar() {
        sidebarVisible.toggle()
        save()
    }

    public func toggleInspector() {
        inspectorVisible.toggle()
        save()
    }

    public func save() {
        let config: [String: Any] = [
            "sidebarWidth": Double(sidebarWidth),
            "inspectorWidth": Double(inspectorWidth),
            "sidebarVisible": sidebarVisible,
            "inspectorVisible": inspectorVisible,
            "displayMode": displayModeRawValue(displayMode)
        ]
        UserDefaults.standard.set(config, forKey: Self.storageKey)
    }

    private func load() {
        guard let config = UserDefaults.standard.dictionary(forKey: Self.storageKey) else {
            applyPreset(.default)
            return
        }
        if let w = config["sidebarWidth"] as? Double { sidebarWidth = CGFloat(w) }
        if let w = config["inspectorWidth"] as? Double { inspectorWidth = CGFloat(w) }
        if let v = config["sidebarVisible"] as? Bool { sidebarVisible = v }
        if let v = config["inspectorVisible"] as? Bool { inspectorVisible = v }
        if let m = config["displayMode"] as? String { displayMode = displayModeFromRawValue(m) }
    }

    private func displayModeRawValue(_ mode: AppState.DisplayMode) -> String {
        switch mode {
        case .spectrum: return "spectrum"
        case .waterfall: return "waterfall"
        case .combined: return "combined"
        }
    }

    private func displayModeFromRawValue(_ raw: String) -> AppState.DisplayMode {
        switch raw {
        case "spectrum": return .spectrum
        case "waterfall": return .waterfall
        default: return .combined
        }
    }
}
