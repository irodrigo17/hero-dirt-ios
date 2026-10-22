import CloudKit
import Combine
import Foundation
import MapKit
import os

/// Saved places, persisted locally and backed up to iCloud in two ways so they
/// survive deleting and reinstalling the app:
///
/// 1. **iCloud key-value store** — the whole list as JSON. Needs no CloudKit
///    schema, syncs quickly, and is the primary restore path.
/// 2. **CloudKit private database** — one `Place` record per place.
///
/// Copies are merged (never blindly replaced): places are matched by id, the
/// newest `updatedAt` wins, and deletions are remembered as tombstones so a
/// stale copy can't resurrect a place you removed.
@MainActor
class PlaceStore: ObservableObject {
    @Published private(set) var places: [Place] = []

    private static let logger = Logger(
        subsystem: "com.herodirt.app",
        category: "PlaceStore"
    )

    private let fileURL: URL?
    private var syncEnabled: Bool { fileURL == nil }

    /// Ids of places deleted on any device, so merges don't bring them back.
    private var deletedIDs: Set<UUID> = []
    private static let maxTombstones = 500

    // iCloud key-value store
    private let kvs = NSUbiquitousKeyValueStore.default
    private static let kvsPlacesKey = "places.v1"
    private static let kvsDeletedKey = "deletedPlaceIDs.v1"
    private var kvsObserver: NSObjectProtocol?

    // CloudKit
    private lazy var container = CKContainer.default()
    private lazy var privateDB = container.privateCloudDatabase
    private static let recordType = "Place"
    private struct CKKeys {
        static let id = "id"
        static let name = "name"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let mapItemId = "mapItemId"
        static let soilOverride = "soilOverride"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private static var localFileURL: URL {
        URL.documentsDirectory.appending(path: "saved_places.json")
    }

    private static let deletedIDsDefaultsKey = "deletedPlaceIDs"

    // MARK: - Init

    init() {
        fileURL = nil
        load()
        loadTombstones()
        startKeyValueSync()
        syncFromCloudKit()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - CRUD

    func addPlace(_ place: Place) {
        var place = place
        place.updatedAt = Date()
        deletedIDs.remove(place.id)
        places.append(place)
        persist(upsert: [place])
    }

    func renamePlace(_ place: Place, to newName: String) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].name = newName
        places[index].updatedAt = Date()
        persist(upsert: [places[index]])
    }

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
        deletedIDs.insert(place.id)
        persist(delete: [place])
    }

    func removePlaces(at offsets: IndexSet) {
        let toDelete = offsets.map { places[$0] }
        places.remove(atOffsets: offsets)
        deletedIDs.formUnion(toDelete.map(\.id))
        persist(delete: toDelete)
    }

    func updateSoilOverride(_ override: SoilOverride?, for place: Place) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].soilOverride = override
        places[index].updatedAt = Date()
        persist(upsert: [places[index]])
    }

    private static let proximityThresholdMeters: CLLocationDistance = 50

    func placeNear(latitude: Double, longitude: Double) -> Place? {
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return places.first { place in
            let placeLocation = CLLocation(
                latitude: place.latitude,
                longitude: place.longitude
            )
            return target.distance(from: placeLocation) < Self.proximityThresholdMeters
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

    /// Merges a remote copy into `places`. Returns true if anything changed.
    @discardableResult
    private func mergeIn(remote: [Place], remoteDeleted: Set<UUID> = []) -> Bool {
        deletedIDs.formUnion(remoteDeleted)
        let merged = Self.merge(local: places, remote: remote, deleted: deletedIDs)
        guard merged != places else { return false }
        places = merged
        return true
    }

    // MARK: - Persistence

    private func persist(upsert: [Place] = [], delete: [Place] = []) {
        save()
        guard syncEnabled else { return }
        saveTombstones()
        writeKeyValueStore()
        Task {
            guard await iCloudAccountAvailable() else { return }
            if !upsert.isEmpty { upsertToCloudKit(upsert) }
            if !delete.isEmpty { deleteFromCloudKit(delete) }
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(places)
            try data.write(to: fileURL ?? Self.localFileURL, options: .atomic)
        } catch {
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        let url = fileURL ?? Self.localFileURL
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        do {
            let data = try Data(contentsOf: url)
            places = try JSONDecoder().decode([Place].self, from: data)
        } catch {
            Self.logger.error("load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadTombstones() {
        let strings = UserDefaults.standard.stringArray(forKey: Self.deletedIDsDefaultsKey) ?? []
        deletedIDs = Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private func saveTombstones() {
        let strings = Array(deletedIDs.map(\.uuidString).prefix(Self.maxTombstones))
        UserDefaults.standard.set(strings, forKey: Self.deletedIDsDefaultsKey)
    }

    // MARK: - iCloud key-value store

    private func startKeyValueSync() {
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mergeFromKeyValueStore()
            }
        }
        kvs.synchronize()
        mergeFromKeyValueStore()
    }

    private func mergeFromKeyValueStore() {
        let remoteDeleted = Set(
            (kvs.array(forKey: Self.kvsDeletedKey) as? [String] ?? []).compactMap(UUID.init(uuidString:))
        )
        var remote: [Place] = []
        if let data = kvs.data(forKey: Self.kvsPlacesKey) {
            do {
                remote = try JSONDecoder().decode([Place].self, from: data)
            } catch {
                Self.logger.error("iCloud KVS decode failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let hadPlaces = !places.isEmpty
        if mergeIn(remote: remote, remoteDeleted: remoteDeleted) {
            Self.logger.info("merged \(remote.count) places from iCloud KVS (had local: \(hadPlaces))")
            save()
            saveTombstones()
        }
        // Push back anything only we had (e.g. first launch after an update).
        writeKeyValueStore()
    }

    private func writeKeyValueStore() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        if kvs.data(forKey: Self.kvsPlacesKey) != data {
            kvs.set(data, forKey: Self.kvsPlacesKey)
        }
        let deleted = Array(deletedIDs.map(\.uuidString).prefix(Self.maxTombstones))
        if Set(kvs.array(forKey: Self.kvsDeletedKey) as? [String] ?? []) != Set(deleted) {
            kvs.set(deleted, forKey: Self.kvsDeletedKey)
        }
    }

    // MARK: - CloudKit

    private func syncFromCloudKit() {
        Task {
            guard await iCloudAccountAvailable() else { return }
            do {
                let remote = try await fetchAllFromCloudKit()
                if mergeIn(remote: remote) {
                    Self.logger.info("merged \(remote.count) places from CloudKit")
                    save()
                    writeKeyValueStore()
                }
                // Upload anything CloudKit is missing or has an older copy of.
                let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let stale = places.filter { remoteByID[$0.id] != $0 }
                if !stale.isEmpty { upsertToCloudKit(stale) }
                let orphaned = remote.filter { deletedIDs.contains($0.id) }
                if !orphaned.isEmpty { deleteFromCloudKit(orphaned) }
            } catch {
                // Usually a missing record type / index in the production
                // schema. The key-value store still covers restores.
                Self.logger.error("CloudKit fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private func recordID(for place: Place) -> CKRecord.ID {
        CKRecord.ID(recordName: place.id.uuidString)
    }

    nonisolated private func place(from record: CKRecord) -> Place? {
        guard
            let name = record[CKKeys.name] as? String,
            let latitude = record[CKKeys.latitude] as? Double,
            let longitude = record[CKKeys.longitude] as? Double,
            let idString = record[CKKeys.id] as? String,
            let uuid = UUID(uuidString: idString)
        else { return nil }
        var mapItemId: MKMapItem.Identifier? = nil
        if let mapItemIdString = record[CKKeys.mapItemId] as? String {
            mapItemId = MKMapItem.Identifier(rawValue: mapItemIdString)
        }
        var soilOverride: SoilOverride? = nil
        if let overrideData = record[CKKeys.soilOverride] as? Data {
            soilOverride = try? JSONDecoder().decode(SoilOverride.self, from: overrideData)
        }
        return Place(
            id: uuid,
            name: name,
            latitude: latitude,
            longitude: longitude,
            mapItemId: mapItemId,
            soilOverride: soilOverride,
            updatedAt: record[CKKeys.updatedAt] as? Date
        )
    }

    nonisolated private func apply(place: Place, to record: CKRecord) {
        record[CKKeys.id] = place.id.uuidString as CKRecordValue
        record[CKKeys.name] = place.name as CKRecordValue
        record[CKKeys.latitude] = place.latitude as CKRecordValue
        record[CKKeys.longitude] = place.longitude as CKRecordValue
        record[CKKeys.mapItemId] = place.mapItemId?.rawValue as CKRecordValue?
        if let override = place.soilOverride,
            let data = try? JSONEncoder().encode(override)
        {
            record[CKKeys.soilOverride] = data as CKRecordValue
        } else {
            record[CKKeys.soilOverride] = nil
        }
        record[CKKeys.updatedAt] = (place.updatedAt ?? Date()) as CKRecordValue
        if record[CKKeys.createdAt] == nil {
            record[CKKeys.createdAt] = Date() as CKRecordValue
        }
    }

    private func fetchAllFromCloudKit() async throws -> [Place] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var fetched: [Place] = []
        var (results, cursor) = try await privateDB.records(matching: query)
        while true {
            for (_, result) in results {
                if case .success(let record) = result, let p = place(from: record) {
                    fetched.append(p)
                }
            }
            guard let next = cursor else { break }
            (results, cursor) = try await privateDB.records(continuingMatchFrom: next)
        }
        return fetched
    }

    private func upsertToCloudKit(_ places: [Place]) {
        guard !places.isEmpty else { return }
        let records: [CKRecord] = places.map { place in
            let record = CKRecord(recordType: Self.recordType, recordID: recordID(for: place))
            apply(place: place, to: record)
            return record
        }
        let modify = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        modify.savePolicy = .changedKeys
        modify.qualityOfService = .utility
        modify.modifyRecordsResultBlock = { result in
            if case .failure(let error) = result {
                Self.logger.error("CloudKit save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        privateDB.add(modify)
    }

    private func deleteFromCloudKit(_ places: [Place]) {
        let op = CKModifyRecordsOperation(
            recordsToSave: nil,
            recordIDsToDelete: places.map { recordID(for: $0) }
        )
        op.qualityOfService = .utility
        op.modifyRecordsResultBlock = { result in
            if case .failure(let error) = result {
                Self.logger.error("CloudKit delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        privateDB.add(op)
    }

    private func iCloudAccountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }
}
