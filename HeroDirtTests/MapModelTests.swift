import MapKit
import Testing

@testable import HeroDirt

@MainActor
struct MapModelTests {

    private let place = Place(name: "Skeggs", latitude: 37.41, longitude: -122.30)
    private let pin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)

    @Test func selectingOpensDetailsAndFocuses() {
        let model = MapModel()
        model.select(.saved(place.id), places: [place])
        #expect(model.selection == .saved(place.id))
        #expect(model.isDetailsSheetPresented)
        #expect(model.cameraCommand != nil)
        #expect(model.annotationSelection(in: [place]) != nil)
    }

    @Test func droppedPinNameResolvesWithoutChangingIdentity() {
        let model = MapModel()
        model.select(.droppedPin(pin, name: nil), places: [], focus: false)
        let identity = model.selection?.identity
        model.droppedPinNamed("Los Gatos, CA")
        #expect(model.droppedPin?.name == "Los Gatos, CA")
        #expect(model.selection?.identity == identity)
    }

    @Test func savingADroppedPinSelectsTheSavedPlace() {
        let model = MapModel()
        model.select(.droppedPin(place.coordinate, name: "Skeggs"), places: [], focus: false)
        model.didSave(place)
        #expect(model.selection == .saved(place.id))
        #expect(model.droppedPin == nil)
    }

    @Test func unsavingKeepsAPinWhereThePlaceWas() {
        let model = MapModel()
        model.select(.saved(place.id), places: [place])
        model.didUnsave(place)
        #expect(model.droppedPin?.coordinate.latitude == place.latitude)
        #expect(model.droppedPin?.name == "Skeggs")
    }

    @Test func closingClearsEverything() {
        let model = MapModel()
        model.select(.droppedPin(pin, name: nil), places: [])
        model.closeDetails()
        #expect(model.selection == nil)
        #expect(!model.isDetailsSheetPresented)
        #expect(model.annotationSelection(in: []) == nil)
    }

    @Test func splitLayoutShowsDetailsInSidebarNotSheet() {
        let model = MapModel()
        model.applyLayout(split: true, places: [], animated: false)
        #expect(model.isSplit)
        #expect(!model.isMainSheetPresented)
        model.select(.saved(place.id), places: [place])
        #expect(!model.isDetailsSheetPresented)
        #expect(model.sheetBias == 0)
    }

    @Test func initialFitHappensOnce() {
        let model = MapModel()
        model.fitPlacesIfNeeded([])
        #expect(model.cameraCommand == nil)
        model.fitPlacesIfNeeded([place])
        let first = model.cameraCommand?.id
        model.fitPlacesIfNeeded([place])
        #expect(model.cameraCommand?.id == first)
    }

    @Test func prefersSplitOnlyForWideWindows() {
        #expect(MapModel.prefersSplit(for: CGSize(width: 874, height: 402)))
        #expect(MapModel.prefersSplit(for: CGSize(width: 951, height: 669)))
        #expect(!MapModel.prefersSplit(for: CGSize(width: 402, height: 874)))
        #expect(!MapModel.prefersSplit(for: CGSize(width: 500, height: 400)))
    }
}
