import MapKit
import UIKit

// MARK: - MKOverlay

final class RainfallMapOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(bounds: RainfallGridBounds) {
        let topLeft = MKMapPoint(bounds.topLeft)
        let bottomRight = MKMapPoint(bounds.bottomRight)
        let minX = min(topLeft.x, bottomRight.x)
        let minY = min(topLeft.y, bottomRight.y)
        let width = abs(bottomRight.x - topLeft.x)
        let height = abs(bottomRight.y - topLeft.y)
        self.boundingMapRect = MKMapRect(x: minX, y: minY, width: width, height: height)
        self.coordinate = CLLocationCoordinate2D(
            latitude: (bounds.minLat + bounds.maxLat) / 2,
            longitude: (bounds.minLon + bounds.maxLon) / 2
        )
    }
}

// MARK: - MKOverlayRenderer

final class RainfallOverlayRenderer: MKOverlayRenderer {
    var image: UIImage?
    var overlayOpacity: CGFloat = 0.3

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let cgImage = image?.cgImage else { return }
        let drawRect = self.rect(for: overlay.boundingMapRect)
        context.saveGState()
        context.setAlpha(overlayOpacity)
        // CGContext y-axis is flipped relative to UIImage; translate+scale to correct orientation
        context.translateBy(x: drawRect.minX, y: drawRect.minY + drawRect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: drawRect.size))
        context.restoreGState()
    }
}
