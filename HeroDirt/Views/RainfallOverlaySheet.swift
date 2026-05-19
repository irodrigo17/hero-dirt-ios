import SwiftUI

struct RainfallOverlaySheet: View {
    @Binding var isVisible: Bool
    @Binding var timeframe: RainfallTimeframe
    @Binding var opacity: Double
    var isLoading: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show rainfall overlay", isOn: $isVisible)
                }

                Section("Timeframe") {
                    Picker("Timeframe", selection: $timeframe) {
                        ForEach(RainfallTimeframe.allCases) { tf in
                            Text(tf.rawValue).tag(tf)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Opacity") {
                    HStack {
                        Image(systemName: "circle.dotted")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Slider(value: $opacity, in: 0.1...0.9, step: 0.1)
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("Legend") {
                    RainfallLegendView()
                        .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }
            .navigationTitle("Rainfall Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isLoading {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
