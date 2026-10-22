import Foundation
import MetricKit
import os

/// Lightweight, privacy-friendly telemetry. Events are written to the unified
/// log (visible in Console.app / `log stream`) and counted locally; MetricKit
/// delivers Apple's daily performance metrics and crash/hang diagnostics.
/// Nothing leaves the device from here. To ship events to a backend (e.g.
/// TelemetryDeck), forward them from `signal(_:_:)`.
enum TelemetryEvent: String, Sendable {
    case appLaunched
    case placeSaved
    case placeRemoved
    case placeRenamed
    case soilTuned
    case conditionsViewed
    case directionsOpened
    case searchPerformed
    case searchResultSelected
    case rainMapToggled
    case feedbackOpened
}

enum Telemetry {
    private static let logger = Logger(subsystem: "com.herodirt.app", category: "Telemetry")
    private static let countsKey = "telemetry.eventCounts"

    static func start() {
        MXMetricManager.shared.add(MetricKitSubscriber.shared)
        signal(.appLaunched)
    }

    static func signal(_ event: TelemetryEvent, _ parameters: [String: String] = [:]) {
        if parameters.isEmpty {
            logger.info("event=\(event.rawValue, privacy: .public)")
        } else {
            let params = parameters
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            logger.info("event=\(event.rawValue, privacy: .public) \(params, privacy: .public)")
        }
        let defaults = UserDefaults.standard
        var counts = defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        counts[event.rawValue, default: 0] += 1
        defaults.set(counts, forKey: countsKey)
    }

    /// Local event counts, e.g. for attaching to a bug report.
    static var eventCounts: [String: Int] {
        UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }
}

// MARK: - MetricKit

final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitSubscriber()

    private let logger = Logger(subsystem: "com.herodirt.app", category: "MetricKit")

    /// Most recent diagnostic payload, kept so a bug report can include it.
    static var latestDiagnosticsURL: URL {
        URL.cachesDirectory.appending(path: "latest_diagnostics.json")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let launch = payload.applicationLaunchMetrics?
                .histogrammedTimeToFirstDraw.bucketEnumerator.allObjects.count ?? 0
            logger.info("metrics payload \(payload.timeStampBegin, privacy: .public)–\(payload.timeStampEnd, privacy: .public), launch buckets: \(launch)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            logger.error("diagnostics: \(crashes) crashes, \(hangs) hangs")
            try? payload.jsonRepresentation().write(to: Self.latestDiagnosticsURL, options: .atomic)
        }
    }
}

// MARK: - App info

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var versionString: String { "\(version) (\(build))" }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        // Simulators report their host architecture; use the simulated model.
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
    }

    @MainActor static var diagnosticsSummary: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
        App: Hero Dirt \(versionString)
        Device: \(deviceModel)
        iOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        Locale: \(Locale.current.identifier)
        """
    }
}
