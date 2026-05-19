import CloudKit
import Combine
import Foundation
import MapKit
import os

@MainActor
class PlaceStore: ObservableObject {
    @Published private(set) var places: [Place] = []

    private static let logger = Logger(
        subsystem: "com.herodirt.app",
        category: "PlaceStore"
    )

    private let fileURL: URL?

    // CloudKit
    private let container = CKContainer.default()
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

    // MARK: - CloudKit Helpers

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
            soilOverride: soilOverride
        )
    }

    nonisolated private func apply(place: Place, to record: CKRecord) {
        record[CKKeys.id] = place.id.uuidString as CKRecordValue
        record[CKKeys.name] = place.name as CKRecordValue
        record[CKKeys.latitude] = place.latitude as CKRecordValue
        record[CKKeys.longitude] = place.longitude as CKRecordValue
        if let mapId = place.mapItemId {
            record[CKKeys.mapItemId] = mapId.rawValue as CKRecordValue
        } else {
            record[CKKeys.mapItemId] = nil
        }
        if let override = place.soilOverride,
            let data = try? JSONEncoder().encode(override)
        {
            record[CKKeys.soilOverride] = data as CKRecordValue
        } else {
            record[CKKeys.soilOverride] = nil
        }
        record[CKKeys.updatedAt] = Date() as CKRecordValue
        if record[CKKeys.createdAt] == nil {
            record[CKKeys.createdAt] = Date() as CKRecordValue
        }
    }

    private func fetchAllFromCloudKit() async throws -> [Place] {
        try await withCheckedThrowingContinuation { continuation in
            let query = CKQuery(
                recordType: Self.recordType,
                predicate: NSPredicate(value: true)
            )
            let operation = CKQueryOperation(query: query)
            var fetched: [Place] = []
            operation.recordMatchedBlock = { [weak self] _, result in
                guard let self else { return }
                if case .success(let record) = result, let p = self.place(from: record) {
                    fetched.append(p)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: fetched)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }
    }

    private func upsertAllToCloudKit(_ places: [Place]) {
        guard !places.isEmpty else { return }
        let records: [CKRecord] = places.map { place in
            let record = CKRecord(
                recordType: Self.recordType,
                recordID: recordID(for: place)
            )
            apply(place: place, to: record)
            return record
        }
        let modify = CKModifyRecordsOperation(
            recordsToSave: records,
            recordIDsToDelete: nil
        )
        modify.savePolicy = .changedKeys
        modify.qualityOfService = .utility
        modify.modifyRecordsResultBlock = { _ in }
        privateDB.add(modify)
    }

    private func deleteFromCloudKit(_ place: Place) {
        let op = CKModifyRecordsOperation(
            recordsToSave: nil,
            recordIDsToDelete: [recordID(for: place)]
        )
        op.qualityOfService = .utility
        op.modifyRecordsResultBlock = { _ in }
        privateDB.add(op)
    }

    private func iCloudAccountAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
    }

    // MARK: - Init

    init() {
        fileURL = nil
        load()
        syncFromCloudKit()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    private func syncFromCloudKit() {
        Task {
            guard await iCloudAccountAvailable(), fileURL == nil else { return }
            guard let remotePlaces = try? await fetchAllFromCloudKit() else { return }
            if !remotePlaces.isEmpty && remotePlaces != places {
                places = remotePlaces
                save()
            }
        }
    }

    // MARK: - CRUD

    func addPlace(_ place: Place) {
        places.append(place)
        save()
        Task {
            guard await iCloudAccountAvailable(), fileURL == nil else { return }
            upsertAllToCloudKit(places)
        }
    }

    func renamePlace(_ place: Place, to newName: String) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].name = newName
        save()
        Task {
            guard await iCloudAccountAvailable(), fileURL == nil else { return }
            upsertAllToCloudKit(places)
        }
    }

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
        save()
        Task {
            guard await iCloudAccountAvailable(), fileURL == nil else { return }
            deleteFromCloudKit(place)
        }
    }

    func removePlaces(at offsets: IndexSet) {
        let toDelete = offsets.map { places[$0] }
        places.remove(atOffsets: offsets)
        save()
        Task {
            guard await iCloudAccountAvailable(), fileURL == nil else { return }
            for place in toDelete { deleteFromCloudKit(place) }
        }
    }

    func updateSoilOverride(_ override: SoilOverride?, for place: Place) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].soilOverride = override
        save()
        Task {
            guard await iCloudAccountAvailable(), fileURL == nil else { return }
            upsertAllToCloudKit(places)
        }
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

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(places)
            if let fileURL {
                try data.write(to: fileURL, options: .atomic)
            } else {
                try? data.write(to: Self.localFileURL, options: .atomic)
            }
        } catch {
            Self.logger.error("PlaceStore save error: \(error)")
        }
    }

    private func load() {
        if let fileURL {
            guard FileManager.default.fileExists(atPath: fileURL.path()) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                places = try JSONDecoder().decode([Place].self, from: data)
            } catch {
                Self.logger.error("PlaceStore load error: \(error)")
            }
        } else {
            guard FileManager.default.fileExists(atPath: Self.localFileURL.path()),
                let fileData = try? Data(contentsOf: Self.localFileURL)
            else { return }
            do {
                let decoded = try JSONDecoder().decode([Place].self, from: fileData)
                if decoded != places { places = decoded }
            } catch {
                Self.logger.error("PlaceStore load error: \(error)")
            }
        }
    }
}
