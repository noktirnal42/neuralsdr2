//
// BookmarkManager.swift
// NeuralSDR2
//
// Persistent bookmark system for frequency/mode combinations
//

import SwiftUI

public struct Bookmark: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var frequency: Double
    public var mode: DemodulatorType
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        frequency: Double,
        mode: DemodulatorType = .NFM,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.mode = mode
        self.tags = tags
    }

    public func formatFrequency() -> String {
        if frequency >= 1_000_000_000 {
            return String(format: "%.3f GHz", frequency / 1_000_000_000)
        } else if frequency >= 1_000_000 {
            return String(format: "%.3f MHz", frequency / 1_000_000)
        } else if frequency >= 1_000 {
            return String(format: "%.1f kHz", frequency / 1_000)
        } else {
            return "\(Int(frequency)) Hz"
        }
    }
}

public class BookmarkManager: ObservableObject {
    private static let storageKey = "com.neuralsdr2.bookmarks"

    @Published public var bookmarks: [Bookmark] = []

    public init() {
        load()
    }

    public func addBookmark(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
        save()
    }

    public func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    public func updateBookmark(_ bookmark: Bookmark) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
            save()
        }
    }

    public func bookmarksGroupedByTag() -> [(tag: String, bookmarks: [Bookmark])] {
        var tagged: [String: [Bookmark]] = [:]
        var untagged: [Bookmark] = []

        for bookmark in bookmarks {
            if bookmark.tags.isEmpty {
                untagged.append(bookmark)
            } else {
                for tag in bookmark.tags {
                    tagged[tag, default: []].append(bookmark)
                }
            }
        }

        var result: [(tag: String, bookmarks: [Bookmark])] = tagged.map { (tag: $0.key, bookmarks: $0.value.sorted { $0.frequency < $1.frequency }) }
        result.sort { $0.tag < $1.tag }

        if !untagged.isEmpty {
            result.append((tag: "Untagged", bookmarks: untagged.sorted { $0.frequency < $1.frequency }))
        }

        return result
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            bookmarks = Self.defaultBookmarks
            save()
            return
        }

        do {
            let decoder = JSONDecoder()
            bookmarks = try decoder.decode([Bookmark].self, from: data)
        } catch {
            bookmarks = Self.defaultBookmarks
            save()
        }
    }

    public func save() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(bookmarks)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // Silently fail
        }
    }

    public static let defaultBookmarks: [Bookmark] = [
        Bookmark(name: "NOAA Weather 1", frequency: 162_400_000, mode: .NFM, tags: ["Weather"]),
        Bookmark(name: "NOAA Weather 2", frequency: 162_475_000, mode: .NFM, tags: ["Weather"]),
        Bookmark(name: "NOAA Weather 3", frequency: 162_550_000, mode: .NFM, tags: ["Weather"]),
        Bookmark(name: "FM 97.1", frequency: 97_100_000, mode: .WFM, tags: ["FM Broadcast"]),
        Bookmark(name: "FM 100.3", frequency: 100_300_000, mode: .WFM, tags: ["FM Broadcast"]),
        Bookmark(name: "FM 101.5", frequency: 101_500_000, mode: .WFM, tags: ["FM Broadcast"]),
        Bookmark(name: "FM 103.7", frequency: 103_700_000, mode: .WFM, tags: ["FM Broadcast"]),
        Bookmark(name: "2m Calling", frequency: 146_520_000, mode: .NFM, tags: ["Ham Radio"]),
        Bookmark(name: "70cm Calling", frequency: 446_000_000, mode: .NFM, tags: ["Ham Radio"]),
        Bookmark(name: "2m Repeat", frequency: 145_525_000, mode: .NFM, tags: ["Ham Radio"]),
        Bookmark(name: "70cm Repeat", frequency: 435_800_000, mode: .NFM, tags: ["Ham Radio"]),
        Bookmark(name: "ADS-B 1090", frequency: 1_090_000_000, mode: .NFM, tags: ["ADS-B"]),
        Bookmark(name: "Air Tower", frequency: 125_000_000, mode: .AM, tags: ["Air Band"]),
        Bookmark(name: "Air Ground", frequency: 121_500_000, mode: .AM, tags: ["Air Band"]),
        Bookmark(name: "40m CW", frequency: 7_025_000, mode: .CW, tags: ["Ham Radio"]),
        Bookmark(name: "20m USB", frequency: 14_250_000, mode: .USB, tags: ["Ham Radio"]),
    ]
}

extension DemodulatorType: Codable {}
