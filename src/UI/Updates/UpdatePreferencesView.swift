import SwiftUI

public struct UpdatePreferencesView: View {
    @ObservedObject private var sparkleManager = SparkleManager.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Software Update")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("Current Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(sparkleManager.currentAppVersion)
                        .font(.body)
                }
                Spacer()
                Button {
                    sparkleManager.checkForUpdates()
                } label: {
                    if sparkleManager.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Check for Updates")
                    }
                }
                .disabled(sparkleManager.isCheckingForUpdates)
            }

            Toggle("Automatically check for updates", isOn: $sparkleManager.automaticallyChecksForUpdates)

            if let lastChecked = sparkleManager.lastUpdateCheckDate {
                HStack {
                    Text("Last checked:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(lastChecked, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if sparkleManager.updateAvailable, let latest = sparkleManager.latestVersion {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                    Text("Update available: v\(latest)")
                        .font(.body)
                }
            }

            if let feedURL = sparkleManager.updateFeedURL {
                VStack(alignment: .leading) {
                    Text("Update Feed URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(feedURL.absoluteString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
