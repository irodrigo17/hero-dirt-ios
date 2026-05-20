import CloudKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var iCloudStatus: CKAccountStatus?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Hero Dirt is a free, open source app that helps mountain bikers check trail conditions based on recent and forecasted rainfall data.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
                
                Section {
                    Link(destination: URL(string: "https://github.com/irodrigo17/hero-dirt-ios/issues")!) {
                        Label("Report a Bug or Request a Feature", systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Feedback and feature requests are tracked as GitHub Issues.")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/irodrigo17/hero-dirt-ios")!) {
                        Label("View Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } footer: {
                    Text("Source code is freely available on GitHub.")
                }
                
                Section("Your Data") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("iCloud Sync", systemImage: iCloudIcon)
                                .foregroundStyle(iCloudColor)
                            Spacer()
                            if let status = iCloudStatus {
                                Text(statusLabel(status))
                                    .font(.subheadline)
                                    .foregroundStyle(iCloudColor)
                            } else {
                                ProgressView().scaleEffect(0.75)
                            }
                        }
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section("Data Sources") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Open-Meteo", systemImage: "cloud.rain")
                        Text("Free weather API providing historical and forecasted rainfall data. No account or API key required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Apple WeatherKit", systemImage: "cloud.sun")
                        Text("Apple's weather service providing 7-day precipitation forecasts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                iCloudStatus = await withCheckedContinuation { continuation in
                    CKContainer.default().accountStatus { status, _ in
                        continuation.resume(returning: status)
                    }
                }
            }
        }
    }

    // MARK: - iCloud status helpers

    private var iCloudIcon: String {
        iCloudStatus == .available ? "icloud" : "icloud.slash"
    }

    private var iCloudColor: Color {
        switch iCloudStatus {
        case .available: return .green
        case .noAccount, .temporarilyUnavailable: return .orange
        case .restricted, .couldNotDetermine: return .secondary
        default: return .secondary
        }
    }

    private func statusLabel(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "Enabled"
        case .noAccount: return "Not signed in"
        case .restricted: return "Restricted"
        case .temporarilyUnavailable: return "Unavailable"
        case .couldNotDetermine: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private var statusDescription: String {
        switch iCloudStatus {
        case .available:
            return "Saved places are syncing across your devices."
        case .noAccount:
            return "Sign in to iCloud in Settings to sync saved places across your devices."
        case .restricted:
            return "iCloud access is restricted. Saved places are stored locally only."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Saved places are stored locally and will sync when it recovers."
        default:
            return "Saved places are stored in your personal iCloud account (if enabled) and sync automatically across all your iOS devices."
        }
    }
}
