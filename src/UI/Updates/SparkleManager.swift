import Foundation
import Combine

public class SparkleManager: ObservableObject {
    public static let shared = SparkleManager()

    @Published public var lastUpdateCheckDate: Date?
    @Published public var updateAvailable: Bool = false
    @Published public var latestVersion: String?
    @Published public var isCheckingForUpdates: Bool = false

    private let userDefaults = UserDefaults.standard
    private let updateFeedURLKey = "SparkleUpdateFeedURL"
    private let autoCheckKey = "SUEnableAutomaticChecks"
    private let lastCheckKey = "SULastCheckTime"
    private let checkIntervalKey = "SUScheduledCheckInterval"

    public var automaticallyChecksForUpdates: Bool {
        get { userDefaults.bool(forKey: autoCheckKey) }
        set {
            userDefaults.set(newValue, forKey: autoCheckKey)
            if newValue {
                userDefaults.set(86400, forKey: checkIntervalKey)
            }
        }
    }

    public var updateFeedURL: URL? {
        get {
            if let urlString = userDefaults.string(forKey: updateFeedURLKey),
               let url = URL(string: urlString) {
                return url
            }
            return URL(string: "https://neuralsdr2.github.io/appcast.xml")
        }
        set {
            userDefaults.set(newValue?.absoluteString, forKey: updateFeedURLKey)
        }
    }

    public var currentAppVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return version ?? "1.0.0"
    }

    public var updateCheckInterval: TimeInterval {
        get { TimeInterval(userDefaults.integer(forKey: checkIntervalKey)) }
        set { userDefaults.set(Int(newValue), forKey: checkIntervalKey) }
    }

    private init() {
        loadLastCheckDate()
    }

    private func loadLastCheckDate() {
        lastUpdateCheckDate = userDefaults.object(forKey: lastCheckKey) as? Date
    }

    public func checkForUpdates() {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        let checkDate = Date()
        userDefaults.set(checkDate, forKey: lastCheckKey)
        lastUpdateCheckDate = checkDate

        guard let feedURL = updateFeedURL else {
            isCheckingForUpdates = false
            return
        }

        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isCheckingForUpdates = false

                guard let data = data,
                      let xmlString = String(data: data, encoding: .utf8),
                      error == nil else {
                    return
                }

                self?.parseAppcast(xmlString)
            }
        }
        task.resume()
    }

    private func parseAppcast(_ xmlString: String) {
        guard let shortVersionRange = xmlString.range(of: "<sparkle:shortVersionString>") else { return }
        let afterVersion = xmlString[shortVersionRange.upperBound...]
        guard let endVersion = afterVersion.range(of: "</sparkle:shortVersionString>") else { return }
        let remoteVersion = String(afterVersion[..<endVersion.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        latestVersion = remoteVersion
        updateAvailable = remoteVersion != currentAppVersion
    }

    public func resetUpdateState() {
        updateAvailable = false
        latestVersion = nil
        lastUpdateCheckDate = nil
        userDefaults.removeObject(forKey: lastCheckKey)
    }
}
