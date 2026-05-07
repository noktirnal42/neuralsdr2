//
// ContentView.swift
// NeuralSDR2
//
// Main application view with spectrum display and controls
//

import SwiftUI
import AppKit
import AVFoundation

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var layoutManager = LayoutManager()

    public init() {}

public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ToolbarView(layoutManager: layoutManager)
                    .frame(height: 44)
                
                Divider()
                
                HStack(spacing: 0) {
                    if layoutManager.sidebarVisible {
                        SidebarView()
                            .frame(width: layoutManager.sidebarWidth)
                            .border(Color.gray.opacity(0.3))
                        
                        ResizableDivider(width: $layoutManager.sidebarWidth, isVisible: true)
                    }
                    
                    MainDisplayView()
                        .frame(minWidth: 400)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if layoutManager.inspectorVisible {
                        ResizableDivider(width: $layoutManager.inspectorWidth, isVisible: true, mirror: true)
                        
                        InspectorView()
                            .frame(width: layoutManager.inspectorWidth)
                            .border(Color.gray.opacity(0.3))
                    }
                }
                .frame(height: geometry.size.height - 88) // Subtract toolbar and status bar heights
                
                Divider()
                
                StatusBarView()
                    .frame(height: 44)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .environmentObject(layoutManager)
            .environmentObject(appState.mapState)
            .environmentObject(appState.mapIntegrationManager.weatherRadarManager)
            .keyboardShortcutHandler()
            .onChange(of: layoutManager.sidebarWidth) { _ in layoutManager.save() }
            .onChange(of: layoutManager.inspectorWidth) { _ in layoutManager.save() }
        }
    }
}

private struct ResizableDivider: View {
    @Binding var width: CGFloat
    var isVisible: Bool
    var mirror: Bool = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Divider()
            .frame(width: 4)
            .contentShape(Rectangle())
            .cursor(mirror ? .resizeRight : .resizeLeft)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta = mirror ? value.translation.width - dragOffset : -(value.translation.width - dragOffset)
                        dragOffset = value.translation.width
                        width = max(150, min(500, width + delta))
                    }
                    .onEnded { _ in
                        dragOffset = 0
                    }
            )
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Toolbar

public struct ToolbarView: View {
    @ObservedObject var layoutManager: LayoutManager
    @EnvironmentObject var appState: AppState
    @State private var frequencyText: String = ""

    public init(layoutManager: LayoutManager) {
        self.layoutManager = layoutManager
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Start/Stop button
            Button(action: {
                if appState.isRunning { appState.stopSDR() } else { appState.startSDR() }
            }) {
                Image(systemName: appState.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Text(appState.isRunning ? "Stop" : "Start")
            }
            .buttonStyle(.borderedProminent)

            Divider()

            WorkspaceSwitcherStrip()

            Divider()

            // Frequency display and entry
            HStack {
                Text("Freq")
                    .font(.system(size: 11))
                    .fixedSize()

                TextField("MHz", text: $frequencyText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .onSubmit {
                    commitFrequencyText()
                }

                Menu("Bands") {
                    Button("FM Broadcast") { appState.setFrequency(100_000_000) }
                    Button("Air Band") { appState.setFrequency(125_000_000) }
                    Button("2m Ham") { appState.setFrequency(145_000_000) }
                    Button("70cm Ham") { appState.setFrequency(435_000_000) }
                    Button("ADS-B") { appState.setFrequency(1_090_000_000) }
                }
            }

            Divider()

            // Layout controls
            HStack(spacing: 4) {
                Button(action: { layoutManager.toggleSidebar() }) {
                    Image(systemName: layoutManager.sidebarVisible ? "sidebar.left" : "sidebar.left.slash")
                }
                .buttonStyle(.bordered)
                .help("Toggle Sidebar (Cmd+B for bookmarks)")

                Button(action: { layoutManager.toggleInspector() }) {
                    Image(systemName: layoutManager.inspectorVisible ? "menubar.rectangle" : "menubar.rectangle")
                }
                .buttonStyle(.bordered)
                .help("Toggle Inspector")

                Menu("Layout") {
                    ForEach(LayoutPreset.allCases, id: \.self) { preset in
                        Button(preset.rawValue) { layoutManager.applyPreset(preset) }
                    }
                }
            }

            Spacer()

            // Device info
            if let device = appState.deviceInfo {
                Label(device.name, systemImage: "usb")
                    .font(.caption)
            } else {
                Label("No Device", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            syncFrequencyText()
        }
        .onChange(of: appState.frequency) { _ in
            syncFrequencyText()
        }
    }

    private func syncFrequencyText() {
        let formatted = String(format: "%.3f", appState.frequency / 1_000_000)
        if frequencyText != formatted {
            frequencyText = formatted
        }
    }

    private func commitFrequencyText() {
        let trimmed = frequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let valueMHz = Double(trimmed) else {
            syncFrequencyText()
            return
        }
        appState.setFrequency(valueMHz * 1_000_000)
        syncFrequencyText()
    }
}

// MARK: - Sidebar

public struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedBand = "All Bands"

    let bands = ["All Bands", "HF", "VHF", "UHF", "FM Broadcast", "Air Band", "2m Ham", "70cm Ham", "ADS-B"]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MissionControlSection()

            Divider()

            WorkspaceSection()

            Divider()

            Text("Spectrum Bands")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            List(selection: $selectedBand) {
                ForEach(bands, id: \.self) { band in
                    Text(band)
                        .tag(band)
                        .onTapGesture {
                            selectedBand = band
                            tuneBand(band)
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()

            BookmarkSection()
        }
        .frame(minWidth: 150)
    }

    private func tuneBand(_ band: String) {
        switch band {
        case "FM Broadcast":
            appState.showBroadcastWorkspace()
        case "Air Band":
            appState.setFrequency(125_000_000)
            appState.setMode(.AM)
        case "2m Ham":
            appState.setFrequency(145_000_000)
            appState.setMode(.NFM)
        case "70cm Ham":
            appState.setFrequency(435_000_000)
            appState.setMode(.NFM)
        case "ADS-B":
            appState.showAircraftWorkspace()
        default:
            break
        }
    }
}

private struct WorkspaceSwitcherStrip: View {
    @EnvironmentObject var appState: AppState

    private let workspaces: [AppState.Workspace] = [.radio, .aircraft, .satellites, .earth, .recordings]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(workspaces, id: \.self) { workspace in
                Button {
                    select(workspace)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: workspace))
                        Text(shortLabel(for: workspace))
                    }
                    .frame(minWidth: 76)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.workspace == workspace ? accent(for: workspace) : .gray.opacity(0.28))
                .opacity(appState.workspace == workspace ? 1 : 0.82)
            }
        }
    }

    private func select(_ workspace: AppState.Workspace) {
        switch workspace {
        case .radio:
            appState.showBroadcastWorkspace()
        case .aircraft:
            appState.showAircraftWorkspace()
        case .satellites:
            appState.showSatelliteWorkspace()
        case .earth, .recordings:
            appState.setWorkspace(workspace)
        }
    }

    private func shortLabel(for workspace: AppState.Workspace) -> String {
        switch workspace {
        case .radio: return "Radio"
        case .aircraft: return "Aircraft"
        case .satellites: return "Sat Ops"
        case .earth: return "3D Earth"
        case .recordings: return "Library"
        }
    }

    private func icon(for workspace: AppState.Workspace) -> String {
        switch workspace {
        case .radio: return "waveform"
        case .aircraft: return "airplane"
        case .satellites: return "antenna.radiowaves.left.and.right"
        case .earth: return "globe.americas"
        case .recordings: return "folder"
        }
    }

    private func accent(for workspace: AppState.Workspace) -> Color {
        switch workspace {
        case .radio: return .blue
        case .aircraft: return .cyan
        case .satellites: return .orange
        case .earth: return .mint
        case .recordings: return .pink
        }
    }
}

private struct MissionControlSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mission Control")
                    .font(.system(size: 12, weight: .semibold))
                Text(workspaceSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                StatusChip(
                    title: appState.deviceInfo?.name ?? "No SDR Device",
                    subtitle: appState.statusMessage,
                    icon: appState.deviceInfo == nil ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right",
                    tint: appState.deviceInfo == nil ? .orange : .green
                )
                StatusChip(
                    title: appState.workspace.rawValue,
                    subtitle: workspaceDetail,
                    icon: workspaceIcon,
                    tint: workspaceTint
                )
            }
        }
        .padding(12)
    }

    private var workspaceSummary: String {
        switch appState.workspace {
        case .radio:
            return "Tune and inspect live spectrum."
        case .aircraft:
            return "Track aircraft and weather on the universal map."
        case .satellites:
            return "Manage passes, Doppler, and post-pass workflows."
        case .earth:
            return "Inspect the 3D Earth visualization."
        case .recordings:
            return "Review decoded products and saved captures."
        }
    }

    private var workspaceDetail: String {
        switch appState.workspace {
        case .radio:
            return "\(appState.currentMode.rawValue) • \(String(format: "%.3f MHz", appState.frequency / 1_000_000))"
        case .aircraft:
            return "\(appState.mapState.trackedAircraft.count) aircraft • \(appState.dump978Enabled ? "weather linked" : "weather off")"
        case .satellites:
            return "\(appState.mapState.trackedSatellites.count) tracked • \(appState.activeSatelliteTarget ?? "no target")"
        case .earth:
            return "Map layers and Earth scene ready"
        case .recordings:
            return "\(appState.decodedAPTArtifacts.count) NOAA • \(appState.decodedPacketArtifacts.count) packet"
        }
    }

    private var workspaceIcon: String {
        switch appState.workspace {
        case .radio: return "waveform.path.ecg"
        case .aircraft: return "airplane.circle.fill"
        case .satellites: return "antenna.radiowaves.left.and.right.circle.fill"
        case .earth: return "globe.americas.fill"
        case .recordings: return "tray.full.fill"
        }
    }

    private var workspaceTint: Color {
        switch appState.workspace {
        case .radio: return .blue
        case .aircraft: return .cyan
        case .satellites: return .orange
        case .earth: return .mint
        case .recordings: return .pink
        }
    }
}

private struct StatusChip: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WorkspaceSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workspaces")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Button("Broadcast Monitor") {
                appState.showBroadcastWorkspace()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)

            Button("Aircraft Tracker") {
                appState.showAircraftWorkspace()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)

            Button("Satellite Passes") {
                appState.showSatelliteWorkspace()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 12)
    }
}

private struct BookmarkSection: View {
    @EnvironmentObject var appState: AppState
    @State private var newBookmarkName = ""
    @State private var showAddSheet = false
    @State private var editingBookmark: Bookmark?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bookmarks")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            let grouped = appState.bookmarkManager.bookmarksGroupedByTag()
            if grouped.isEmpty {
                Text("No bookmarks")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(grouped, id: \.tag) { group in
                        Section(header: Text(group.tag).font(.system(size: 10, weight: .semibold))) {
                            ForEach(group.bookmarks) { bookmark in
                                BookmarkRow(bookmark: bookmark, editingBookmark: $editingBookmark)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddBookmarkSheet(isPresented: $showAddSheet)
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    @Binding var editingBookmark: Bookmark?
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.name)
                    .font(.system(size: 11))
                Text("\(bookmark.formatFrequency()) - \(bookmark.mode.rawValue)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onDoubleClick {
            appState.setFrequency(bookmark.frequency)
            appState.setMode(bookmark.mode)
        }
        .contextMenu {
            Button("Tune") {
                appState.setFrequency(bookmark.frequency)
                appState.setMode(bookmark.mode)
            }
            Button("Edit...") {
                editingBookmark = bookmark
            }
            Divider()
            Button("Delete", role: .destructive) {
                appState.bookmarkManager.removeBookmark(bookmark)
            }
        }
    }
}

private struct AddBookmarkSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var tags = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Bookmark")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                HStack {
                    Text("Frequency:")
                    Spacer()
                    Text(String(format: "%.3f MHz", appState.frequency / 1_000_000))
                        .font(.system(size: 11).monospaced())
                }
                HStack {
                    Text("Mode:")
                    Spacer()
                    Text(appState.currentMode.rawValue)
                }
                TextField("Tags (comma separated)", text: $tags)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Button("Add") {
                    let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let bookmark = Bookmark(
                        name: name.isEmpty ? String(format: "%.3f MHz", appState.frequency / 1_000_000) : name,
                        frequency: appState.frequency,
                        mode: appState.currentMode,
                        tags: tagList
                    )
                    appState.bookmarkManager.addBookmark(bookmark)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty && tags.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

private extension View {
    func onDoubleClick(action: @escaping () -> Void) -> some View {
        gesture(
            TapGesture(count: 2)
                .onEnded { _ in action() }
        )
    }
}

// MARK: - Main Display

public struct MainDisplayView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var mapState: MapState

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            WorkspaceSurfaceHeader()

            Divider()

            switch appState.workspace {
            case .radio:
                radioDisplay
            case .aircraft:
                AircraftWorkspaceView()
            case .satellites:
                SatelliteWorkspaceView()
            case .earth:
                EarthWorkspaceView()
            case .recordings:
                RecordingWorkspaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(workspaceBackground)
    }

    @ViewBuilder
    private var radioDisplay: some View {
        switch appState.displayMode {
        case .spectrum:
            SpectrumDisplayView()
        case .waterfall:
            WaterfallDisplayView()
        case .combined:
            CombinedDisplayView()
        }
    }

    private var workspaceBackground: Color {
        switch appState.workspace {
        case .radio:
            return .black
        case .aircraft, .satellites, .earth, .recordings:
            return Color(NSColor.windowBackgroundColor)
        }
    }
}

private struct WorkspaceSurfaceHeader: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var mapState: MapState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(workspaceTitle, systemImage: workspaceIcon)
                    .font(.headline)
                Text(workspaceSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                WorkspaceMetricPill(title: workspaceMetricTitle, value: workspaceMetricValue, tint: workspaceTint)
                WorkspaceMetricPill(title: "Mode", value: appState.currentMode.rawValue, tint: .blue)
                WorkspaceMetricPill(title: "Center", value: centerFrequencyLabel, tint: .secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private var workspaceTitle: String {
        switch appState.workspace {
        case .radio: return "Radio Console"
        case .aircraft: return "Aircraft Operations"
        case .satellites: return "Satellite Operations"
        case .earth: return "3D Earth"
        case .recordings: return "Recordings Library"
        }
    }

    private var workspaceSubtitle: String {
        switch appState.workspace {
        case .radio:
            return "Live spectrum, demodulation, and manual tuning."
        case .aircraft:
            return "Aircraft tracks, UAT weather, and map-linked receiver status."
        case .satellites:
            return "Pass planning, Doppler tracking, and post-pass decode workflows."
        case .earth:
            return "Global context for the wider SDR operating picture."
        case .recordings:
            return "Saved captures, decoded NOAA products, and internal packet reports."
        }
    }

    private var workspaceIcon: String {
        switch appState.workspace {
        case .radio: return "waveform.path.ecg.rectangle"
        case .aircraft: return "airplane.departure"
        case .satellites: return "antenna.radiowaves.left.and.right.circle"
        case .earth: return "globe.americas"
        case .recordings: return "externaldrive.badge.timemachine"
        }
    }

    private var workspaceMetricTitle: String {
        switch appState.workspace {
        case .radio: return "Bandwidth"
        case .aircraft: return "Aircraft"
        case .satellites: return "Tracked"
        case .earth: return "Map Style"
        case .recordings: return "Decoded"
        }
    }

    private var workspaceMetricValue: String {
        switch appState.workspace {
        case .radio:
            return formatBandwidth(appState.bandwidth)
        case .aircraft:
            return "\(mapState.trackedAircraft.count)"
        case .satellites:
            return "\(mapState.trackedSatellites.count)"
        case .earth:
            return mapState.mapStyle.rawValue.capitalized
        case .recordings:
            return "\(appState.decodedAPTArtifacts.count + appState.decodedPacketArtifacts.count)"
        }
    }

    private var workspaceTint: Color {
        switch appState.workspace {
        case .radio: return .blue
        case .aircraft: return .cyan
        case .satellites: return .orange
        case .earth: return .mint
        case .recordings: return .pink
        }
    }

    private var centerFrequencyLabel: String {
        if appState.frequency >= 1_000_000_000 {
            return String(format: "%.3f GHz", appState.frequency / 1_000_000_000)
        }
        return String(format: "%.3f MHz", appState.frequency / 1_000_000)
    }

    private func formatBandwidth(_ hz: Double) -> String {
        if hz >= 1_000_000 {
            return String(format: "%.2f MHz", hz / 1_000_000)
        } else if hz >= 1_000 {
            return String(format: "%.1f kHz", hz / 1_000)
        } else {
            return String(format: "%.0f Hz", hz)
        }
    }
}

private struct WorkspaceMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WorkspaceDashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundColor(tint)
            content
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WorkspaceDashboardMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WorkspaceDashboardRow: View {
    let label: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Inspector Panel

public struct InspectorView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Mode selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Demodulator")
                        .font(.system(size: 11, weight: .semibold))

                    Picker("Mode", selection: $appState.currentMode) {
                        ForEach(DemodulatorType.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                // Filter settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filter")
                        .font(.system(size: 11, weight: .semibold))

                    HStack {
                        Text("Bandwidth:")
                        Spacer()
                        Text(formatBandwidth(appState.bandwidth))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: Binding(
                        get: { appState.bandwidth },
                        set: { appState.setBandwidth($0) }
                    ), in: 100...50000)
                }

                Divider()

                // Gain control
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gain")
                        .font(.system(size: 11, weight: .semibold))

                    HStack {
                        Text("RF Gain:")
                        Slider(value: Binding(
                            get: { appState.tunerGain },
                            set: { appState.setTunerGain($0) }
                        ), in: 0...50)
                        .disabled(appState.agcEnabled)
                        Text("dB")
                            .foregroundColor(.secondary)
                    }

                    Toggle("AGC", isOn: Binding(
                        get: { appState.agcEnabled },
                        set: { appState.setAGCEnabled($0) }
                    ))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Monitor")
                        .font(.system(size: 11, weight: .semibold))

                    Toggle("Mute Speakers", isOn: Binding(
                        get: { appState.isMuted },
                        set: { appState.setMuted($0) }
                    ))

                    Text("Monitoring only. DSP and recording continue while muted.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if appState.currentMode == .IQ {
                        Text("IQ mode keeps raw signal and spectrum live with no speaker demodulation.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Squelch
                VStack(alignment: .leading, spacing: 8) {
                    Text("Squelch")
                        .font(.system(size: 11, weight: .semibold))

                    HStack {
                        Text("Threshold:")
                        Slider(value: Binding(
                            get: { Double(appState.squelchThreshold) },
                            set: { appState.setSquelchThreshold(Float($0)) }
                        ), in: -120...0)
                        Text("dB")
                            .foregroundColor(.secondary)
                    }

                    Toggle("Squelch", isOn: Binding(
                        get: { appState.squelchEnabled },
                        set: { appState.setSquelchEnabled($0) }
                    ))
                }

                Divider()

                if appState.workspace == .aircraft {
                    AircraftOperationsSection()
                    Divider()
                }

                if appState.workspace == .satellites {
                    SatelliteOperationsSection()
                    Divider()
                }

                if appState.workspace == .recordings {
                    RecordingOperationsSection()
                    Divider()
                }

                // RDS Panel (only for WFM mode)
                if appState.currentMode == .WFM {
                    RDSDataPanel()
                    Divider()
                }

                Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                    appState.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func formatBandwidth(_ hz: Double) -> String {
        if hz >= 1_000_000 {
            return String(format: "%.2f MHz", hz / 1_000_000)
        } else if hz >= 1_000 {
            return String(format: "%.1f kHz", hz / 1_000)
        } else {
            return String(format: "%.0f Hz", hz)
        }
    }
}

private struct AircraftOperationsSection: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var weatherRadarManager: WeatherRadarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aircraft Ops")
                .font(.system(size: 11, weight: .semibold))

            HStack {
                Button("Tune ADS-B") {
                    appState.showAircraftWorkspace()
                }
                .buttonStyle(.bordered)

                Button("Reconnect Feed") {
                    appState.connectToDump978()
                }
                .buttonStyle(.bordered)
            }

            Toggle("UAT Weather Overlay", isOn: Binding(
                get: { appState.dump978Enabled },
                set: { appState.setWeatherOverlayEnabled($0) }
            ))

            HStack {
                Text("dump978 Host")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                TextField("127.0.0.1", text: Binding(
                    get: { appState.dump978Host },
                    set: { appState.setDump978Host($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            }

            HStack {
                Text("dump978 Port")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                TextField("30978", value: Binding(
                    get: { Int(appState.dump978Port) },
                    set: { appState.setDump978Port(UInt16(max(0, min(65535, $0)))) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }

            Text(weatherRadarManager.dump978StateDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(appState.mapState.aircraftSourceStatus)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("Aircraft: \(appState.mapState.trackedAircraft.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Weather blocks: \(weatherRadarManager.weatherBlockCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastUpdate = weatherRadarManager.lastWeatherUpdate {
                    Text("Age \(formatAge(lastUpdate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                if let lastAircraftUpdate = appState.mapState.lastAircraftUpdate {
                    Text("Last aircraft \(formatAge(lastAircraftUpdate)) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Stale window \(Int(appState.mapState.aircraftExpirationInterval))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatAge(_ date: Date) -> String {
        let age = max(Int(Date().timeIntervalSince(date)), 0)
        if age < 60 {
            return "\(age)s"
        }
        return "\(age / 60)m"
    }
}

private struct SatelliteOperationsSection: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var mapState: MapState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Satellite Ops")
                .font(.system(size: 11, weight: .semibold))

            HStack {
                Button("Tune NOAA APT") {
                    appState.showSatelliteWorkspace()
                }
                .buttonStyle(.bordered)

                Button("Refresh TLEs") {
                    Task {
                        try? await appState.mapIntegrationManager.refreshTrackedSatellitesFromCelesTrak()
                    }
                }
                .buttonStyle(.bordered)
            }

            Toggle("Show Ground Tracks", isOn: $mapState.showGroundTracks)
            Toggle("Show Orbits", isOn: $mapState.showOrbits)

            HStack {
                Text("Observer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                TextField("Lat", value: $mapState.observerLatitude, format: .number.precision(.fractionLength(4)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                TextField("Lon", value: $mapState.observerLongitude, format: .number.precision(.fractionLength(4)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
            }

            Button("Use Current Location") {
                mapState.resumeAutomaticObserverLocation()
            }
            .buttonStyle(.bordered)
            .disabled(!mapState.isLocationEnabled && mapState.userLocation == nil)

            Text(mapState.locationStatusMessage)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(mapState.satelliteSourceStatus)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(appState.satelliteDopplerStatus)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Text("\(mapState.trackedSatellites.count) tracked satellites")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let refresh = mapState.lastSatelliteRefresh {
                    Text("TLE age \(formatAge(refresh))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let armed = appState.armedSatelliteRecording {
                Text("Armed: \(armed)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if !upcomingPasses.isEmpty {
                Divider()

                ForEach(Array(mapState.trackedSatellites.filter { $0.nextPass != nil }.sorted {
                    ($0.nextPass?.aos ?? .distantFuture) < ($1.nextPass?.aos ?? .distantFuture)
                }.prefix(3))) { satellite in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(satellite.name)
                            .font(.caption.bold())
                        Text("AOS \(relativeTime(until: satellite.nextPass?.aos ?? .distantFuture)) • Max \(satellite.nextPass?.maxElevation ?? 0, specifier: "%.0f")°")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack {
                            Button("Tune") {
                                appState.tuneToSatellite(satellite)
                            }
                            .buttonStyle(.borderless)

                            Button("Arm Rec") {
                                appState.armRecordingForNextPass(satellite)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .onChange(of: mapState.showGroundTracks) { _ in appState.persistSessionPreferences() }
        .onChange(of: mapState.showOrbits) { _ in appState.persistSessionPreferences() }
        .onChange(of: mapState.observerLatitude) { _ in
            if !mapState.isUsingCurrentLocation {
                updateObserverLocation()
            }
        }
        .onChange(of: mapState.observerLongitude) { _ in
            if !mapState.isUsingCurrentLocation {
                updateObserverLocation()
            }
        }
    }

    private func formatAge(_ date: Date) -> String {
        let age = max(Int(Date().timeIntervalSince(date)), 0)
        if age < 60 {
            return "\(age)s"
        }
        return "\(age / 60)m"
    }

    private var upcomingPasses: [SatellitePass] {
        mapState.trackedSatellites
            .compactMap(\.nextPass)
            .sorted { $0.aos < $1.aos }
    }

    private func relativeTime(until date: Date) -> String {
        let interval = max(Int(date.timeIntervalSinceNow), 0)
        if interval < 60 {
            return "in \(interval)s"
        }
        if interval < 3600 {
            return "in \(interval / 60)m"
        }
        return "in \(interval / 3600)h"
    }

    private func updateObserverLocation() {
        mapState.setManualObserverLocation(
            lat: mapState.observerLatitude,
            lon: mapState.observerLongitude
        )
        appState.mapIntegrationManager.updateSatellitePositions()
        appState.persistSessionPreferences()
    }
}

private struct RecordingOperationsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var recentRecordings: [RecordingMetadata] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recording Ops")
                .font(.system(size: 11, weight: .semibold))

            HStack {
                Button(appState.isRecording ? "Stop Capture" : "Start Capture") {
                    appState.toggleRecording()
                    reloadRecordingsSoon()
                }
                .buttonStyle(.borderedProminent)

                Button("Open Workspace") {
                    appState.setWorkspace(.recordings)
                }
                .buttonStyle(.bordered)
            }

            Text("State: \(recordingStateLabel)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let directory = appState.recordingManagerWrapper?.getRecordingsDirectory() {
                Text(directory.path)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if recentRecordings.isEmpty {
                Text("No saved recordings yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(recentRecordings.prefix(3)), id: \.filePath) { recording in
                    VStack(alignment: .leading, spacing: 2) {
                        Text((recording.filePath as NSString).lastPathComponent)
                            .font(.caption)
                        Text("\(recording.mode) • \(recording.frequency / 1_000_000, specifier: "%.3f") MHz")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: reloadRecordings)
        .onChange(of: appState.isRecording) { _ in
            reloadRecordingsSoon()
        }
    }

    private var recordingStateLabel: String {
        switch appState.recordingManagerWrapper?.currentState ?? .idle {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .stopping:
            return "Stopping"
        }
    }

    private func reloadRecordings() {
        if appState.recordingManagerWrapper == nil {
            appState.recordingManagerWrapper = RecordingManagerWrapper()
        }
        recentRecordings = appState.recordingManagerWrapper?.getRecordings() ?? []
    }

    private func reloadRecordingsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            reloadRecordings()
        }
    }
}

// MARK: - Status Bar

public struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        HStack(spacing: 16) {
            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            SMeterView(level: appState.signalLevel)

            Spacer()

            if appState.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("REC")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red)
                }
            }

            Text("\(formatSampleRate(appState.sampleRate))")
                .font(.system(size: 11).monospaced())
                .foregroundColor(.secondary)

            Text(formatFrequency(appState.frequency))
                .font(.system(size: 11).monospaced())
                .foregroundColor(.secondary)

            Text(appState.currentMode.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)

            if appState.isMuted {
                Text("MUTED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1_000_000_000 {
            return String(format: "%.3f GHz", freq / 1_000_000_000)
        } else if freq >= 1_000_000 {
            return String(format: "%.3f MHz", freq / 1_000_000)
        } else {
            return String(format: "%.0f kHz", freq / 1_000)
        }
    }

    private func formatSampleRate(_ rate: Double) -> String {
        if rate >= 1_000_000 {
            return String(format: "%.2f MSps", rate / 1_000_000)
        } else {
            return String(format: "%.0f kSps", rate / 1_000)
        }
    }
}

// MARK: - S-Meter

public struct SMeterView: View {
    public init(level: Float) { self.level = level }
    let level: Float
    @State private var animatedLevel: Float = -120.0

    public var body: some View {
        HStack(spacing: 2) {
            Text("S")
                .font(.system(size: 10, weight: .bold))

            ForEach(0..<10) { i in
                Rectangle()
                    .fill(colorForLevel(level: animatedLevel, index: i))
                    .frame(width: 3, height: 12)
            }

            Text(String(format: "%+.0f dB", level))
                .font(.system(size: 9).monospaced())
                .foregroundColor(.secondary)
        }
        .onChange(of: level) { newValue in
            withAnimation(.easeOut(duration: 0.1)) {
                animatedLevel = newValue
            }
        }
    }

    private func colorForLevel(level: Float, index: Int) -> Color {
        let threshold: Float = -120 + Float(index) * 10
        if level >= threshold {
            if index < 6 { return .green }
            else if index < 8 { return .yellow }
            else { return .red }
        }
        return Color.gray.opacity(0.3)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}

public struct AircraftWorkspaceView: View {
    public init() {}

    public var body: some View {
        OperationsMapWorkspaceView()
    }
}

public struct SatelliteWorkspaceView: View {
    public init() {}

    public var body: some View {
        OperationsMapWorkspaceView()
    }
}

private struct OperationsMapWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var mapState: MapState

    var body: some View {
        HSplitView {
            UniversalMapView()
                .frame(minWidth: 520, maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    WorkspaceDashboardCard(title: "Universal Ops", icon: "globe.americas.fill", tint: .blue) {
                        Text("One map for aircraft, weather, and satellite operations.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        WorkspaceDashboardMetric(title: "Aircraft", value: "\(mapState.trackedAircraft.count)", tint: .cyan)
                        WorkspaceDashboardMetric(title: "Satellites", value: "\(mapState.trackedSatellites.count)", tint: .orange)
                        WorkspaceDashboardMetric(title: "Weather", value: mapState.weatherOverlayEnabled ? "Live" : "Off", tint: .blue)
                    }

                    WorkspaceDashboardCard(title: "Receiver Status", icon: "dot.radiowaves.left.and.right", tint: .cyan) {
                        WorkspaceDashboardRow(label: "Aircraft", value: mapState.aircraftSourceStatus)
                        WorkspaceDashboardRow(label: "Satellites", value: mapState.satelliteSourceStatus)
                        WorkspaceDashboardRow(label: "Doppler", value: appState.satelliteDopplerStatus)
                    }

                    WorkspaceDashboardCard(title: "Observer", icon: "location.fill", tint: .green) {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            TextField("Lat", value: $mapState.observerLatitude, format: .number.precision(.fractionLength(4)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }

                        HStack {
                            Text("Longitude")
                            Spacer()
                            TextField("Lon", value: $mapState.observerLongitude, format: .number.precision(.fractionLength(4)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }

                        Button("Use Current Location") {
                            mapState.resumeAutomaticObserverLocation()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!mapState.isLocationEnabled && mapState.userLocation == nil)

                        Text(mapState.locationStatusMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    WorkspaceDashboardCard(title: "Traffic", icon: "airplane.circle.fill", tint: .mint) {
                        if mapState.trackedAircraft.isEmpty {
                            Text("No aircraft tracked")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(mapState.trackedAircraft.prefix(8)), id: \.id) { aircraft in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(aircraft.callsign.isEmpty ? aircraft.icao : aircraft.callsign)
                                        .font(.caption.bold())
                                    Text("\(aircraft.altitude) ft • \(aircraft.speed) kt")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    WorkspaceDashboardCard(title: "Upcoming Passes", icon: "satellite.fill", tint: .orange) {
                        if sortedTrackedSatellites.isEmpty {
                            Text("No predicted passes yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(sortedTrackedSatellites.prefix(5))) { satellite in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(satellite.name)
                                        .font(.caption.bold())
                                    if let pass = satellite.nextPass {
                                        Text("AOS \(relativeTime(until: pass.aos)) • Peak \(pass.maxElevation, specifier: "%.1f")°")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    HStack {
                                        Button("Tune") {
                                            appState.tuneToSatellite(satellite)
                                        }
                                        .buttonStyle(.borderless)

                                        Button("Arm Rec") {
                                            appState.armRecordingForNextPass(satellite)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if appState.armedSatelliteRecording != nil {
                        Button("Cancel Auto Record") {
                            appState.cancelArmedSatelliteRecording()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Refresh TLE Catalog") {
                        Task {
                            try? await appState.mapIntegrationManager.refreshTrackedSatellitesFromCelesTrak()
                            appState.mapIntegrationManager.updateSatellitePositions()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)
        }
        .onChange(of: mapState.observerLatitude) { _ in
            if !mapState.isUsingCurrentLocation {
                updateObserverLocation()
            }
        }
        .onChange(of: mapState.observerLongitude) { _ in
            if !mapState.isUsingCurrentLocation {
                updateObserverLocation()
            }
        }
    }

    private func relativeAge(for date: Date) -> String {
        let age = max(Int(Date().timeIntervalSince(date)), 0)
        if age < 60 {
            return "\(age)s ago"
        }
        return "\(age / 60)m ago"
    }

    private var upcomingPasses: [SatellitePass] {
        mapState.trackedSatellites
            .compactMap(\.nextPass)
            .sorted { $0.aos < $1.aos }
    }

    private var sortedTrackedSatellites: [SatelliteTrack] {
        mapState.trackedSatellites
            .filter { $0.nextPass != nil }
            .sorted { ($0.nextPass?.aos ?? .distantFuture) < ($1.nextPass?.aos ?? .distantFuture) }
    }

    private func relativeTime(until date: Date, includePrefix: Bool = true) -> String {
        let interval = max(Int(date.timeIntervalSinceNow), 0)
        let body: String
        if interval < 60 {
            body = "\(interval)s"
        } else if interval < 3600 {
            body = "\(interval / 60)m"
        } else {
            body = "\(interval / 3600)h"
        }
        return includePrefix ? "in \(body)" : body
    }

    private func updateObserverLocation() {
        mapState.setManualObserverLocation(
            lat: mapState.observerLatitude,
            lon: mapState.observerLongitude
        )
        appState.mapIntegrationManager.updateSatellitePositions()
        appState.persistSessionPreferences()
    }

    private var selectedTargetName: String? {
        appState.activeSatelliteTarget ?? sortedTrackedSatellites.first?.name
    }

    private var selectedProfileFrequencyMHz: Binding<Double> {
        Binding(
            get: {
                guard let targetName = selectedTargetName else { return 0 }
                return appState.satelliteProfile(for: targetName).frequency / 1_000_000
            },
            set: { newValue in
                guard let targetName = selectedTargetName else { return }
                appState.updateSatelliteProfile(name: targetName, frequency: newValue * 1_000_000)
            }
        )
    }

    private var selectedProfileMode: Binding<DemodulatorType> {
        Binding(
            get: {
                guard let targetName = selectedTargetName else { return .NFM }
                return appState.satelliteProfile(for: targetName).mode
            },
            set: { newValue in
                guard let targetName = selectedTargetName else { return }
                appState.updateSatelliteProfile(name: targetName, mode: newValue)
            }
        )
    }

    private var selectedProfileBandwidth: Binding<Double> {
        Binding(
            get: {
                guard let targetName = selectedTargetName else { return 0 }
                return appState.satelliteProfile(for: targetName).bandwidth
            },
            set: { newValue in
                guard let targetName = selectedTargetName else { return }
                appState.updateSatelliteProfile(name: targetName, bandwidth: newValue)
            }
        )
    }

    private var selectedReceivePreset: Binding<SatelliteReceivePreset> {
        Binding(
            get: {
                guard let targetName = selectedTargetName else { return .fmVoice }
                return appState.satelliteProfile(for: targetName).receivePreset
            },
            set: { newValue in
                guard let targetName = selectedTargetName else { return }
                appState.updateSatelliteProfile(name: targetName, receivePreset: newValue)
            }
        )
    }

    private func followUpHint(for preset: SatelliteReceivePreset) -> String {
        switch preset {
        case .noaaAPT:
            return "After pass: open latest audio for APT image workflow"
        case .packet:
            return "After pass: run internal packet analysis on saved audio"
        case .digitalVoice:
            return "After pass: hand off latest IQ to digital voice decoder"
        case .fmVoice:
            return "After pass: review saved audio recording"
        }
    }
}

public struct EarthWorkspaceView: View {
    public init() {}

    public var body: some View {
        Earth3DView()
    }
}

public struct RecordingWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                RecordingPanel()
                Spacer(minLength: 0)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity, alignment: .top)
            .padding()

            Divider()

            RecordingWorkspaceSidebar()
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if appState.recordingManagerWrapper == nil {
                appState.recordingManagerWrapper = RecordingManagerWrapper()
            }
        }
    }
}

private final class RecordingPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentPath: String?

    private var player: AVAudioPlayer?

    func togglePlayback(for path: String) {
        if isPlaying, currentPath == path {
            stop()
            return
        }

        do {
            stop()
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            currentPath = path
            isPlaying = true
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentPath = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}

private struct RecordingWorkspaceSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var recordings: [RecordingMetadata] = []
    @State private var selectedRecordingPath: String?
    @StateObject private var previewPlayer = RecordingPreviewPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Recordings")
                    .font(.headline)

                if let directory = appState.recordingManagerWrapper?.getRecordingsDirectory() {
                    Text(directory.path)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                if let latestAPT = appState.latestAPTRecording {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Latest NOAA APT Session")
                            .font(.subheadline)
                        Text((latestAPT.filePath as NSString).lastPathComponent)
                            .font(.caption)
                        Text(latestAPT.satellite)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(latestAPT.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let detail = latestAPT.detailText {
                            Text(detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let source = latestAPT.sourceFilePath {
                            Text("Source: \((source as NSString).lastPathComponent)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let latestArtifact = appState.decodedAPTArtifacts.first(where: { $0.imagePath == latestAPT.filePath }),
                           let coverage = latestArtifact.coverageSummary {
                            NOAAQualityPill(
                                tier: appState.noaaArtifactQualityTier(latestArtifact),
                                score: appState.noaaArtifactQualityScore(latestArtifact)
                            )
                            if appState.mapState.selectedDecodedNOAAArtifactID == latestArtifact.imagePath {
                                Text("Selected From Map")
                                    .font(.caption2.bold())
                                    .foregroundColor(.orange)
                            }
                            Text(
                                "Observer \(coverage.observerLatitude, specifier: "%.2f"), \(coverage.observerLongitude, specifier: "%.2f")"
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            if let first = coverage.firstLine, let last = coverage.lastLine {
                                Text(
                                    "Track \(first.latitude, specifier: "%.1f"), \(first.longitude, specifier: "%.1f") → \(last.latitude, specifier: "%.1f"), \(last.longitude, specifier: "%.1f")"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            Button("Open Image") {
                                appState.executePostPassAction(latestAPT)
                            }
                            .buttonStyle(.bordered)

                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: latestAPT.filePath)])
                            }
                            .buttonStyle(.bordered)
                        }

                        if let latestArtifact = appState.decodedAPTArtifacts.first(where: { $0.imagePath == latestAPT.filePath }) {
                            HStack {
                                Button("Open Ch A") {
                                    appState.openAPTChannelImage(latestArtifact, channel: 1)
                                }
                                .buttonStyle(.bordered)

                                Button("Open Ch B") {
                                    appState.openAPTChannelImage(latestArtifact, channel: 2)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if !appState.decodedAPTArtifacts.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decoded NOAA Library")
                            .font(.subheadline)

                        ForEach(filteredDecodedAPTArtifacts.prefix(12)) { artifact in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artifact.satellite)
                                        .font(.caption)
                                    NOAAQualityPill(
                                        tier: appState.noaaArtifactQualityTier(artifact),
                                        score: appState.noaaArtifactQualityScore(artifact)
                                    )
                                    if appState.mapState.selectedDecodedNOAAArtifactID == artifact.imagePath {
                                        Text("Selected From Map")
                                            .font(.caption2.bold())
                                            .foregroundColor(.orange)
                                    }
                                    Text((artifact.imagePath as NSString).lastPathComponent)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(
                                        String(
                                            format: "%d lines • sync %.2f • jitter %.1f • balance %+.2f • telem %.2f • sep %.2f • cal %.2f",
                                            artifact.lineCount,
                                            artifact.syncQuality,
                                            artifact.lineJitter,
                                            artifact.channelBalance,
                                            artifact.telemetryContrast,
                                            artifact.channelSeparation,
                                            artifact.calibrationSpread
                                        )
                                    )
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                    Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if let coverage = artifact.coverageSummary {
                                        Text(
                                            "Obs \(coverage.observerLatitude, specifier: "%.1f"), \(coverage.observerLongitude, specifier: "%.1f")"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        if let first = coverage.firstLine, let last = coverage.lastLine {
                                            Text(
                                                "Track \(first.latitude, specifier: "%.1f"), \(first.longitude, specifier: "%.1f") → \(last.latitude, specifier: "%.1f"), \(last.longitude, specifier: "%.1f")"
                                            )
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Button("Open") {
                                        NSWorkspace.shared.open(artifact.imageURL)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Ch A") {
                                        appState.openAPTChannelImage(artifact, channel: 1)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Ch B") {
                                        appState.openAPTChannelImage(artifact, channel: 2)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                if let latestPacket = appState.latestPacketRecording {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Latest Packet Session")
                            .font(.subheadline)
                        Text((latestPacket.filePath as NSString).lastPathComponent)
                            .font(.caption)
                        Text(latestPacket.satellite)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(latestPacket.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let detail = latestPacket.detailText {
                            Text(detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let source = latestPacket.sourceFilePath {
                            Text("Source: \((source as NSString).lastPathComponent)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let artifact = appState.decodedPacketArtifacts.first(where: { $0.reportPath == latestPacket.filePath }),
                           !artifact.decodedFrames.isEmpty {
                            ForEach(Array(artifact.decodedFrames.prefix(2).enumerated()), id: \.offset) { index, frame in
                                Text("Frame \(index + 1): \(frame)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        HStack {
                            Button("Open Report") {
                                appState.executePostPassAction(latestPacket)
                            }
                            .buttonStyle(.bordered)

                            if let source = latestPacket.sourceFilePath {
                                Button("Open Audio") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: source))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if !appState.decodedPacketArtifacts.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decoded Packet Library")
                            .font(.subheadline)

                        ForEach(appState.decodedPacketArtifacts.prefix(12)) { artifact in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artifact.satellite)
                                        .font(.caption)
                                    Text((artifact.reportPath as NSString).lastPathComponent)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(
                                        String(
                                            format: "Packet %.0f%% • flags %d • frames %d • %.1f/%.1f kHz",
                                            artifact.confidence * 100,
                                            artifact.hdlcFlagCount,
                                            artifact.decodedFrames.count,
                                            artifact.markFrequency / 1000,
                                            artifact.spaceFrequency / 1000
                                        )
                                    )
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if let frame = artifact.decodedFrames.first {
                                        Text(frame)
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Button("Report") {
                                        NSWorkspace.shared.open(artifact.reportURL)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Audio") {
                                        NSWorkspace.shared.open(artifact.sourceURL)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                if !groupedDecoderHandoffs.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decoder Handoff")
                            .font(.subheadline)

                        ForEach(groupedDecoderHandoffs, id: \.preset) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.preset.rawValue)
                                    .font(.caption.bold())
                                ForEach(group.items.prefix(6)) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.satellite)
                                                .font(.caption2)
                                            Text((item.filePath as NSString).lastPathComponent)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            if let detail = item.detailText {
                                                Text(detail)
                                                    .font(.caption2.monospaced())
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        Button("Open File") {
                                            appState.executePostPassAction(item)
                                            NSWorkspace.shared.open(URL(fileURLWithPath: item.filePath))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }

                Text(appState.lastPostPassActionMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider()

                Text("Saved Recordings")
                    .font(.subheadline)

                if let selected = selectedRecording {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Recording")
                            .font(.caption.bold())

                        Text((selected.filePath as NSString).lastPathComponent)
                            .font(.caption)
                        Text(selected.notes.isEmpty ? appState.inferredSatelliteName(for: selected) : selected.notes)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(selected.mode) • \(selected.frequency / 1_000_000, specifier: "%.3f") MHz • \(selected.sampleRate, specifier: "%.0f") Hz")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack {
                            if canPreview(selected) {
                                Button(previewPlayer.currentPath == selected.filePath && previewPlayer.isPlaying ? "Stop" : "Listen") {
                                    previewPlayer.togglePlayback(for: selected.filePath)
                                }
                                .buttonStyle(.bordered)
                            }

                            if appState.canDecodeAgain(selected) {
                                Button("Decode Again") {
                                    appState.decodeRecordingFromLibrary(selected)
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selected.filePath)])
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()
                }

                if recordings.isEmpty {
                    Text("No recordings saved yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recordings.prefix(40), id: \.filePath) { recording in
                        Button {
                            selectedRecordingPath = recording.filePath
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text((recording.filePath as NSString).lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text("\(recording.mode) • \(recording.frequency / 1_000_000, specifier: "%.3f") MHz")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if !recording.notes.isEmpty {
                                    Text(recording.notes)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(selectedRecordingPath == recording.filePath ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .scrollIndicators(.visible)
        .onAppear(perform: reload)
        .onChange(of: appState.isRecording) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                reload()
            }
        }
        .onChange(of: appState.recordingLibraryRefreshToken) { _ in
            DispatchQueue.main.async {
                reload()
            }
        }
    }

    private func reload() {
        if appState.recordingManagerWrapper == nil {
            appState.recordingManagerWrapper = RecordingManagerWrapper()
        }
        recordings = appState.recordingManagerWrapper?.getRecordings() ?? []
        if selectedRecordingPath == nil {
            selectedRecordingPath = recordings.first?.filePath
        } else if !recordings.contains(where: { $0.filePath == selectedRecordingPath }) {
            selectedRecordingPath = recordings.first?.filePath
        }
        appState.refreshDecodedAPTArtifacts()
        appState.refreshDecodedPacketArtifacts()
    }

    private var groupedDecoderHandoffs: [(preset: SatelliteReceivePreset, items: [PostPassActionItem])] {
        let grouped = Dictionary(grouping: appState.decoderHandoffQueue.filter { $0.preset == .digitalVoice }) { $0.preset }
        return grouped.keys.sorted { $0.rawValue < $1.rawValue }.map { ($0, grouped[$0] ?? []) }
    }

    private var filteredDecodedAPTArtifacts: [APTDecodedArtifact] {
        appState.decodedAPTArtifacts.filter {
            appState.noaaArtifactQualityTier($0).rank >= appState.mapState.minimumNOAAQualityTier.rank
        }
    }

    private var selectedRecording: RecordingMetadata? {
        recordings.first(where: { $0.filePath == selectedRecordingPath })
    }

    private func canPreview(_ recording: RecordingMetadata) -> Bool {
        URL(fileURLWithPath: recording.filePath).pathExtension.lowercased() == "wav"
    }
}

private struct NOAAQualityPill: View {
    let tier: NOAAArtifactQualityTier
    let score: Double

    var body: some View {
        Text("\(tier.rawValue) \(Int((score * 100).rounded()))")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(999)
    }

    private var backgroundColor: Color {
        switch tier {
        case .strong:
            return Color.green.opacity(0.16)
        case .usable:
            return Color.orange.opacity(0.16)
        case .weak:
            return Color.red.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch tier {
        case .strong:
            return .green
        case .usable:
            return .orange
        case .weak:
            return .red
        }
    }
}
