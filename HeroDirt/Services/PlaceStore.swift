import CloudKit
import Foundation
import MapKit
import Observation
import os

// MARK: - Key-value storage abstraction

/// The subset of `NSUbiquitousKeyValueStore` the place store uses, so tests
/// and previews can use an in-memory store.
protocol SyncedKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func array(forKey key: String) -> [Any]?
    func set(_ array: [Any]?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SyncedKeyValueStore {}

final class InMemoryKeyValueStore: SyncedKeyValueStore {
    private var values: [String: Any] = [:]
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    func set(_ array: [Any]?, forKey key: String) { values[key] = array }
    func synchronize() -> Bool { true }
}

// MARK: - PlaceStore

/// Saved places. The single source of truth is the iCloud key-value store:
/// it keeps data on the device (even without an iCloud account), syncs it
/// across devices, and restores it after the app is reinstalled.
///
/// A plain JSON backup file is also written on every change, because iCloud
/// replaces the key-value store's contents when the user signs out or
/// switches accounts. It is only read when the key-value store comes up
/// empty or the account changes.
///
/// Copies are merged, never blindly replaced: places are matched by id, the
/// newest `updatedAt` wins, and deletions are remembered as tombstones so a
/// stale copy can't bring back a place you removed.
@MainActor
@Observable
class PlaceStore {
    private(set) var places: [Place] = []

    @ObservationIgnored private static let logger = Logger(subsystem: "com.herodirt.app", category: "PlaceStore")

    @ObservationIgnored private let kvs: SyncedKeyValueStore
    @ObservationIgnored private let backupURL: URL
    @ObservationIgnored private var deletedIDs: Set<UUID> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let placesKey = "places.v1"
    private static let deletedKey = "deletedPlaceIDs.v1"
    private static let maxTombstones = 500

    static var defaultBackupURL: URL {
        URL.documentsDirectory.appending(path: "saved_places.json")
    }

    // MARK: - Init

    /// The app's store: iCloud key-value store plus a backup in Documents.
    convenience init() {
        self.init(
            kvs: NSUbiquitousKeyValueStore.default,
            backupURL: Self.defaultBackupURL,
            observeICloud: true
        )
        CloudKitImport.runOnce(into: self)
    }

    /// A store backed only by `fileURL` (and an in-memory key-value store).
    /// Used by tests and previews.
    convenience init(fileURL: URL) {
        self.init(kvs: InMemoryKeyValueStore(), backupURL: fileURL, observeICloud: false)
    }

    init(kvs: SyncedKeyValueStore, backupURL: URL, observeICloud: Bool) {
        self.kvs = kvs
        self.backupURL = backupURL
        if observeICloud, let ubiquitous = kvs as? NSUbiquitousKeyValueStore {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitous,
                queue: .main
            ) { [weak self] note in
                let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                MainActor.assumeIsolated {
                    self?.reloadFromKeyValueStore(accountChanged: reason == NSUbiquitousKeyValueStoreAccountChange)
                }
            })
            ubiquitous.synchronize()
        }
        reloadFromKeyValueStore(accountChanged: false)
    }

    // MARK: - CRUD

    func addPlace(_ place: Place) {
        var place = place
        place.updatedAt = Date()
        deletedIDs.remove(place.id)
        places.append(place)
        save()
    }

    func renamePlace(_ place: Place, to newName: String) {
        update(place.id) { $0.name = newName }
    }

    func updateSoilOverride(_ override: SoilOverride?, for place: Place) {
        update(place.id) { $0.soilOverride = override }
    }

    /// Saves a SoilGrids lookup on the place (enrichment, not a user edit).
    func updateSoil(_ soil: SoilData, for placeID: UUID) {
        guard places.first(where: { $0.id == placeID })?.soil != soil else { return }
        update(placeID) { $0.soil = soil }
    }

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
        deletedIDs.insert(place.id)
        save()
    }

    func removePlaces(at offsets: IndexSet) {
        let removed = offsets.map { places[$0].id }
        places.remove(atOffsets: offsets)
        deletedIDs.formUnion(removed)
        save()
    }

    private func update(_ id: UUID, _ change: (inout Place) -> Void) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        change(&places[index])
        places[index].updatedAt = Date()
        save()
    }

    private static let proximityThresholdMeters: CLLocationDistance = 50

    func placeNear(latitude: Double, longitude: Double) -> Place? {
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return places.first { place in
            target.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                < Self.proximityThresholdMeters
        }
    }

    // MARK: - Merge (pure, testable)

    /// Merges two copies of the saved places list. Places are matched by id and
    /// the most recently updated copy wins (local wins ties); anything in
    /// `deleted` is dropped. Local order is preserved, new remote places are
    /// appended.
    nonisolated static func merge(local: [Place], remote: [Place], deleted: Set<UUID>) -> [Place] {
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        var result: [Place] = []
        for place in local where !deleted.contains(place.id) && seen.insert(place.id).inserted {
            if let other = remoteByID[place.id],
               (other.updatedAt ?? .distantPast) > (place.updatedAt ?? .distantPast)
            {
                result.append(other)
            } else {
                result.append(place)
            }
        }
        for place in remote where !deleted.contains(place.id) && seen.insert(place.id).inserted {
            result.append(place)
        }
        return result
    }

    /// Merges places from another source (iCloud change, CloudKit import).
    func mergeIn(_ remote: [Place], deleted remoteDeleted: Set<UUID> = []) {
        deletedIDs.formUnion(remoteDeleted)
        let merged = Self.merge(local: places, remote: remote, deleted: deletedIDs)
        guard merged != places else { return }
        places = merged
        save()
    }

    // MARK: - Persistence

    private func reloadFromKeyValueStore(accountChanged: Bool) {
        let remoteDeleted = Set(
            (kvs.array(forKey: Self.deletedKey) as? [String] ?? []).compactMap(UUID.init(uuidString:))
        )
        var remote: [Place] = []
        if let data = kvs.data(forKey: Self.placesKey) {
            do {
                remote = try JSONDecoder().decode([Place].self, from: data)
            } catch {
                Self.logger.error("key-value store decode failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // The backup covers first launch after updating from the file-only
        // version, and iCloud wiping the store on sign-out/account switch.
        if remote.isEmpty || accountChanged {
            remote = Self.merge(local: remote, remote: loadBackup(), deleted: remoteDeleted)
        }

        deletedIDs.formUnion(remoteDeleted)
        let merged = Self.merge(local: places, remote: remote, deleted: deletedIDs)
        if merged != places { places = merged }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(places)
            if kvs.data(forKey: Self.placesKey) != data {
                kvs.set(data, forKey: Self.placesKey)
            }
            let deleted = Array(deletedIDs.map(\.uuidString).sorted().prefix(Self.maxTombstones))
            if (kvs.array(forKey: Self.deletedKey) as? [String] ?? []).sorted() != deleted {
                kvs.set(deleted, forKey: Self.deletedKey)
            }
            try data.write(to: backupURL, options: .atomic)
        } catch {
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadBackup() -> [Place] {
        guard FileManager.default.fileExists(atPath: backupURL.path()) else { return [] }
        do {
            return try JSONDecoder().decode([Place].self, from: Data(contentsOf: backupURL))
        } catch {
            Self.logger.error("backup load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

// MARK: - One-time CloudKit import

/// Earlier builds synced places through custom CloudKit records. This pulls
/// any of those into the key-value store once, then never touches CloudKit
/// again. Safe to delete after testers have updated.
enum CloudKitImport {
    private static let doneKey = "cloudKitImportDone.v1"
    private static let logger = Logger(subsystem: "com.herodirt.app", category: "CloudKitImport")

    @MainActor
    static func runOnce(into store: PlaceStore) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        Task {
            let container = CKContainer.default()
            guard (try? await container.accountStatus()) == .available else { return }
            do {
                let places = try await fetchAll(from: container.privateCloudDatabase)
                store.mergeIn(places)
                logger.info("imported \(places.count) places from CloudKit")
                UserDefaults.standard.set(true, forKey: doneKey)
            } catch let error as CKError where error.code == .unknownItem || error.code == .invalidArguments {
                // No Place record type (never synced) or not queryable.
                UserDefaults.standard.set(true, forKey: doneKey)
            } catch {
                logger.error("CloudKit import failed, will retry: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func fetchAll(from db: CKDatabase) async throws -> [Place] {
        let query = CKQuery(recordType: "Place", predicate: NSPredicate(value: true))
        var places: [Place] = []
        var (results, cursor) = try await db.records(matching: query)
        while true {
            for (_, result) in results {
                if case .success(let record) = result, let place = place(from: record) {
                    places.append(place)
                }
            }
            guard let next = cursor else { break }
            (results, cursor) = try await db.records(continuingMatchFrom: next)
        }
        return places
    }

    private static func place(from record: CKRecord) -> Place? {
        guard
            let name = record["name"] as? String,
            let latitude = record["latitude"] as? Double,
            let longitude = record["longitude"] as? Double,
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString)
        else { return nil }
        let soilOverride = (record["soilOverride"] as? Data)
            .flatMap { try? JSONDecoder().decode(SoilOverride.self, from: $0) }
        return Place(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            mapItemId: (record["mapItemId"] as? String).flatMap { MKMapItem.Identifier(rawValue: $0) },
            soilOverride: soilOverride,
            updatedAt: record["updatedAt"] as? Date
        )
    }
}
