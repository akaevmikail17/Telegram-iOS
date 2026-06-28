import Foundation

// Centralised file-based persistence for Events data.
// Files live in Application Support with .completeFileProtection.
// On first access, data is migrated from UserDefaults and removed there.

enum TGEventPersistence {

    // MARK: - Events

    static func loadEvents() -> [TGEvent] {
        guard let url = eventsURL else { return [] }
        if !FileManager.default.fileExists(atPath: url.path) {
            migrateFromUserDefaults(key: TGEventStorage.eventsKey, to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([TGEvent].self, from: data) else { return [] }
        return events
    }

    static func saveEvents(_ events: [TGEvent]) {
        guard let url = eventsURL,
              let data = try? JSONEncoder().encode(events) else { return }
        write(data, to: url)
    }

    // MARK: - Votes V1

    static func loadVotesV1() -> [String: String] {
        guard let url = votesV1URL else { return [:] }
        if !FileManager.default.fileExists(atPath: url.path) {
            migrateFromUserDefaults(key: TGEventStorage.votesKey, to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func saveVotesV1(_ dict: [String: String]) {
        guard let url = votesV1URL,
              let data = try? JSONEncoder().encode(dict) else { return }
        write(data, to: url)
    }

    // MARK: - Votes V2

    static func loadVotesV2() -> [String: [TGVoteEntry]] {
        guard let url = votesV2URL else { return [:] }
        if !FileManager.default.fileExists(atPath: url.path) {
            migrateFromUserDefaults(key: "tg_event_votes_v2", to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [TGVoteEntry]].self, from: data) else { return [:] }
        return dict
    }

    static func saveVotesV2(_ dict: [String: [TGVoteEntry]]) {
        guard let url = votesV2URL,
              let data = try? JSONEncoder().encode(dict) else { return }
        write(data, to: url)
    }

    // MARK: - Private

    private static var supportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static var eventsURL: URL? { supportDir?.appendingPathComponent("tg_events_v1.json") }
    private static var votesV1URL: URL? { supportDir?.appendingPathComponent("tg_event_votes_v1.json") }
    private static var votesV2URL: URL? { supportDir?.appendingPathComponent("tg_event_votes_v2.json") }

    @discardableResult
    private static func write(_ data: Data, to url: URL) -> Bool {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil
    }

    private static func migrateFromUserDefaults(key: String, to url: URL) {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if write(data, to: url) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
