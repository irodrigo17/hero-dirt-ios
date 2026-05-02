import Foundation
import Combine

class PlaceStore: ObservableObject {
    @Published private(set) var places: [Place] = []

    private let fileURL: URL?
    private var externalChangeObserver: (any NSObjectProtocol)?

    private static let kvsKey = "saved_places"
    private static var localFileURL: URL {
        URL.documentsDirectory.appending(path: "saved_places.json")
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

    func addPlace(_ place: Place) {
        places.append(place)
        save()
    }

    func renamePlace(_ place: Place, to newName: String) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].name = newName
        save()
    }

    func removePlace(_ place: Place) {
        places.removeAll { $0.id == place.id }
        save()
    }

    func removePlaces(at offsets: IndexSet) {
        places.remove(atOffsets: offsets)
        save()
    }

    func placeNear(latitude: Double, longitude: Double) -> Place? {
        places.first { place in
            abs(place.latitude - latitude) < 0.0005 &&
            abs(place.longitude - longitude) < 0.0005
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
                NSUbiquitousKeyValueStore.default.synchronize()
                try? data.write(to: Self.localFileURL, options: .atomic)
            }
        } catch {
            print("PlaceStore save error: \(error)")
        }
    }

    private func load() {
        if let fileURL {
            guard FileManager.default.fileExists(atPath: fileURL.path()) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                places = try JSONDecoder().decode([Place].self, from: data)
            } catch {
                print("PlaceStore load error: \(error)")
            }
        } else {
            let data: Data
            if let kvsData = NSUbiquitousKeyValueStore.default.data(forKey: Self.kvsKey) {
                data = kvsData
            } else if FileManager.default.fileExists(atPath: Self.localFileURL.path()),
                      let fileData = try? Data(contentsOf: Self.localFileURL) {
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
                print("PlaceStore load error: \(error)")
            }
        }
    }
}
