import CloudKit
import Combine
import Foundation
import MapKit
import os

class PlaceStore: ObservableObject {
    @Published private(set) var places: [Place] = []

    private static let logger = Logger(
        subsystem: "com.herodirt.app",
        category: "PlaceStore"
    )

    private let fileURL: URL?
    private var externalChangeObserver: (any NSObjectProtocol)?

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
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private static let kvsKey = "saved_places"
    private static var localFileURL: URL {
        URL.documentsDirectory.appending(path: "saved_places.json")
    }

    // MARK: - CloudKit Helpers
    private func recordID(for place: Place) -> CKRecord.ID {
        CKRecord.ID(recordName: place.id.uuidString)
    }

    private func place(from record: CKRecord) -> Place? {
        guard
            let name = record[CKKeys.name] as? String,
            let latitude = record[CKKeys.latitude] as? Double,
            let longitude = record[CKKeys.longitude] as? Double,
            let idString = record[CKKeys.id] as? String,
            let uuid = UUID(uuidString: idString)
        else {
            return nil
        }
        var mapItemId: MKMapItem.Identifier? = nil
        if let mapItemIdString = record[CKKeys.mapItemId] as? String {
            mapItemId = MKMapItem.Identifier(rawValue: mapItemIdString)
        }

        return Place(
            id: uuid,
            name: name,
            latitude: latitude,
            longitude: longitude,
            mapItemId: mapItemId
        )
    }

    private func apply(place: Place, to record: CKRecord) {
        record[CKKeys.id] = place.id.uuidString as CKRecordValue
        record[CKKeys.name] = place.name as CKRecordValue
        record[CKKeys.latitude] = place.latitude as CKRecordValue
        record[CKKeys.longitude] = place.longitude as CKRecordValue
        if let mapId = place.mapItemId {
            record[CKKeys.mapItemId] = mapId.rawValue as CKRecordValue
        } else {
            record[CKKeys.mapItemId] = nil
        }
        record[CKKeys.updatedAt] = Date() as CKRecordValue
        if record[CKKeys.createdAt] == nil {
            record[CKKeys.createdAt] = Date() as CKRecordValue
        }
    }

    private func fetchAllFromCloudKit(
        completion: @escaping (Result<[Place], Error>) -> Void
    ) {
        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true)
        )
        let operation = CKQueryOperation(query: query)
        var fetched: [Place] = []
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let p = self.place(from: record) { fetched.append(p) }
            case .failure:
                // Ignore individual record errors; overall errors are handled in queryResultBlock
                break
            }
        }
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                completion(.success(fetched))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        privateDB.add(operation)
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

    private func deleteMissingFromCloudKit(keeping local: [Place]) {
        // Fetch existing, then delete those not present locally
        fetchAllFromCloudKit { result in
            guard case .success(let remote) = result else { return }
            let localIDs = Set(local.map { $0.id })
            let toDeleteIDs =
                remote
                .filter { !localIDs.contains($0.id) }
                .map { CKRecord.ID(recordName: $0.id.uuidString) }
            guard !toDeleteIDs.isEmpty else { return }
            let op = CKModifyRecordsOperation(
                recordsToSave: nil,
                recordIDsToDelete: toDeleteIDs
            )
            op.qualityOfService = .utility
            self.privateDB.add(op)
        }
    }

    private func iCloudAccountAvailable(completion: @escaping (Bool) -> Void) {
        container.accountStatus { status, _ in
            DispatchQueue.main.async {
                completion(status == .available)
            }
        }
    }

    init() {
        fileURL = nil
        load()
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
        syncFromCloudKit()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    deinit {
        if let observer = externalChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func syncFromCloudKit() {
        iCloudAccountAvailable { [weak self] available in
            guard let self = self, available, self.fileURL == nil else {
                return
            }
            self.fetchAllFromCloudKit { result in
                DispatchQueue.main.async {
                    if case .success(let remotePlaces) = result,
                        !remotePlaces.isEmpty, remotePlaces != self.places
                    {
                        self.places = remotePlaces
                        self.save()
                    }
                }
            }
        }
    }

    func addPlace(_ place: Place) {
        places.append(place)
        save()
        iCloudAccountAvailable { [weak self] available in
            guard let self = self, available, self.fileURL == nil else {
                return
            }
            self.upsertAllToCloudKit(self.places)
            self.deleteMissingFromCloudKit(keeping: self.places)
        }
    }

    func renamePlace(_ place: Place, to newName: String) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else {
            return
        }
        places[index].name = newName
        save()
        iCloudAccountAvailable { [weak self] available in
            guard let self = self, available, self.fileURL == nil else {
                return
            }
            self.upsertAllToCloudKit(self.places)
        }
    }

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
        save()
        iCloudAccountAvailable { [weak self] available in
            guard let self = self, available, self.fileURL == nil else {
                return
            }
            self.upsertAllToCloudKit(self.places)
            self.deleteMissingFromCloudKit(keeping: self.places)
        }
    }

    func removePlaces(at offsets: IndexSet) {
        places.remove(atOffsets: offsets)
        save()
        iCloudAccountAvailable { [weak self] available in
            guard let self = self, available, self.fileURL == nil else {
                return
            }
            self.upsertAllToCloudKit(self.places)
            self.deleteMissingFromCloudKit(keeping: self.places)
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
            return target.distance(from: placeLocation)
                < Self.proximityThresholdMeters
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(places)
            if let fileURL {
                try data.write(to: fileURL, options: .atomic)
            } else {
                NSUbiquitousKeyValueStore.default.set(data, forKey: Self.kvsKey)
                try? data.write(to: Self.localFileURL, options: .atomic)
            }
            iCloudAccountAvailable { [weak self] available in
                guard let self = self, available, self.fileURL == nil else {
                    return
                }
                self.upsertAllToCloudKit(self.places)
                self.deleteMissingFromCloudKit(keeping: self.places)
            }
        } catch {
            Self.logger.error("PlaceStore save error: \(error)")
        }
    }

    private func load() {
        if let fileURL {
            guard FileManager.default.fileExists(atPath: fileURL.path()) else {
                return
            }
            do {
                let data = try Data(contentsOf: fileURL)
                places = try JSONDecoder().decode([Place].self, from: data)
            } catch {
                Self.logger.error("PlaceStore load error: \(error)")
            }
        } else {
            let data: Data
            if let kvsData = NSUbiquitousKeyValueStore.default.data(
                forKey: Self.kvsKey
            ) {
                data = kvsData
            } else if FileManager.default.fileExists(
                atPath: Self.localFileURL.path()
            ),
                let fileData = try? Data(contentsOf: Self.localFileURL)
            {
                data = fileData
            } else {
                return
            }
            do {
                let decoded = try JSONDecoder().decode([Place].self, from: data)
                if decoded != places {
                    places = decoded
                }
            } catch {
                Self.logger.error("PlaceStore load error: \(error)")
            }
        }
    }
}
