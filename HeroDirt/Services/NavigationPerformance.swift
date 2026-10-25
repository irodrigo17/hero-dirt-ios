import Foundation
import os
import UIKit

/// Local, Debug-only navigation diagnostics. Session numbers are anonymous;
/// no trail names, identifiers, coordinates, or weather data are logged.
@MainActor
enum NavigationPerformance {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.herodirt.app", category: "NavigationPerformance")
    private static var session = 0
    private static var started = ContinuousClock.now
    private static var monitorTask: Task<Void, Never>?
    #endif

    static func begin() {
        #if DEBUG
        session += 1
        started = .now
        mark("selection_received")
        monitor()
        #endif
    }

    static func monitor() {
        #if DEBUG
        monitorTask?.cancel()
        let observedSession = session
        // A background task requests small main-actor callbacks. A slow network
        // await alone doesn't delay these; busy UI work does. This measures queue
        // responsiveness, not a stack trace or proof of a particular culprit.
        monitorTask = Task.detached(priority: .utility) {
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
                let queued = ContinuousClock.now
                let keepMonitoring = await MainActor.run {
                    guard !Task.isCancelled, session == observedSession,
                          UIApplication.shared.applicationState == .active else { return false }
                    let delay = milliseconds(queued.duration(to: .now))
                    if delay >= 100 {
                        logger.info("navigation session=\(observedSession) phase=main_actor_queue_delay elapsed_ms=\(delay, privacy: .public)")
                    }
                    return true
                }
                if !keepMonitoring { return }
            }
        }
        #endif
    }

    static func mark(_ phase: String) {
        #if DEBUG
        let elapsed = milliseconds(started.duration(to: .now))
        logger.info("navigation session=\(session) phase=\(phase, privacy: .public) since_selection_ms=\(elapsed, privacy: .public)")
        #endif
    }

    static func measure<Value>(_ phase: String, operation: () -> Value) -> Value {
        #if DEBUG
        let observedSession = session
        let start = ContinuousClock.now
        defer {
            let elapsed = milliseconds(start.duration(to: .now))
            logger.info("navigation session=\(observedSession) phase=\(phase, privacy: .public) sync_ms=\(elapsed, privacy: .public)")
        }
        #endif
        return operation()
    }

    /// Total elapsed time including suspension. A large value here alone does
    /// not mean that the main thread was blocked.
    static func measureAsync<Value>(_ phase: String, operation: () async -> Value) async -> Value {
        #if DEBUG
        let observedSession = session
        let start = ContinuousClock.now
        defer {
            let elapsed = milliseconds(start.duration(to: .now))
            logger.info("navigation session=\(observedSession) phase=\(phase, privacy: .public) wall_ms=\(elapsed, privacy: .public)")
        }
        #endif
        return await operation()
    }

    #if DEBUG
    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
    #endif
}
