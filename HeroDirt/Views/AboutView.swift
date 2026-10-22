import CloudKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var iCloudStatus: CKAccountStatus?
    @AppStorage(RainUnitPreference.storageKey) private var unitPreference = RainUnitPreference.automatic

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Hero Dirt is a free, open source app that helps mountain bikers find hero dirt: that perfect tacky, grippy trail you get a day or two after the rain.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
                
                Section {
                    Button {
                        openIssue(kind: .bug)
                    } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                    }
                    Button {
                        openIssue(kind: .idea)
                    } label: {
                        Label("Request a Feature", systemImage: "lightbulb")
                    }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Opens a new GitHub issue with your app version and device details filled in.")
                }

                Section("Settings") {
                    Picker(selection: $unitPreference) {
                        ForEach(RainUnitPreference.allCases) { pref in
                            Text(pref == .automatic ? "Automatic (\(pref.resolved().symbol))" : pref.label)
                                .tag(pref)
                        }
                    } label: {
                        Label("Rain Units", systemImage: "ruler")
                    }
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
                        Text("Free weather data for recent rain and how fast the ground dries out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("ISRIC SoilGrids", systemImage: "square.3.layers.3d.down.right")
                        Text("Global soil maps used to estimate how sandy or clay-heavy the dirt is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Apple WeatherKit", systemImage: "cloud.sun")
                        Text("Apple's weather service, used for the rain forecast.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    Link(destination: URL(string: "https://github.com/irodrigo17/hero-dirt-ios")!) {
                        Label("View Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } footer: {
                    Text("Hero Dirt \(AppInfo.versionString)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
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

    // MARK: - Feedback

    private enum FeedbackKind {
        case bug, idea
    }

    private func openIssue(kind: FeedbackKind) {
        Telemetry.signal(.feedbackOpened, ["kind": kind == .bug ? "bug" : "idea"])
        let body = kind == .bug
            ? "**What happened?**\n\n\n**What did you expect to happen?**\n\n\n---\n"
                + AppInfo.diagnosticsSummary
            : "**What would make Hero Dirt better for you?**\n\n"
        var components = URLComponents(string: "https://github.com/irodrigo17/hero-dirt-ios/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = components.url {
            openURL(url)
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

#Preview {
    AboutView()
}
