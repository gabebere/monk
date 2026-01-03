import Foundation

enum SnapshotReader {
    static func load() -> LiveSnapshot {
        if let defaultsData = SnapshotStorage.userDefaults?.data(forKey: SnapshotStorage.userDefaultsKey),
           let decoded = try? SnapshotStorage.decoder.decode(LiveSnapshot.self, from: defaultsData) {
            return decoded
        }

        if let url = SnapshotStorage.containerURL?.appendingPathComponent(SnapshotStorage.snapshotFileName),
           let data = try? Data(contentsOf: url),
           let decoded = try? SnapshotStorage.decoder.decode(LiveSnapshot.self, from: data) {
            return decoded
        }

        return .empty
    }
}
