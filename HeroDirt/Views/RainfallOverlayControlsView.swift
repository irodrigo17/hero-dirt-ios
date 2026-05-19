import SwiftUI

struct RainfallOverlayControlsView: View {
    @Binding var isVisible: Bool
    @Binding var timeframe: RainfallTimeframe
    @Binding var opacity: Double

    @State private var isExpanded: Bool = false

    let isLoading: Bool

    var body: some View {
        toggleButton
            .overlay(alignment: .topTrailing) {
                if isExpanded {
                    controlPanel
                        .offset(x: -54)
                        .transition(
                            .move(edge: .trailing).combined(with: .opacity)
                        )
                }
            }
    }

    // MARK: - Toggle Button

    private var toggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: isVisible ? "cloud.rain.fill" : "cloud.rain")
                    .font(.system(size: 16))
                    .opacity(isLoading ? 0 : 1)
            }
            .frame(width: 44, height: 44)
        }
        .tint(isExpanded ? .blue : .primary)
        .background(
            .ultraThickMaterial,
            in: RoundedRectangle(cornerRadius: .cornerSmall)
        )
        .accessibilityLabel(
            isExpanded
                ? "Close rainfall overlay controls"
                : "Open rainfall overlay controls"
        )
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rainfall overlay")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Close")
            }

            Toggle("Enabled", isOn: $isVisible)

            Picker("Timeframe", selection: $timeframe) {
                ForEach(RainfallTimeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $opacity, in: 0.1...0.9, step: 0.1)
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            RainfallLegendView()
        }
        .padding(12)
        .frame(width: 260)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: .cornerMedium)
        )
    }
}

// MARK: - Bottom Sheet

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

// MARK: - Standalone Panel

struct RainfallControlPanelView: View {
    @Binding var isVisible: Bool
    @Binding var timeframe: RainfallTimeframe
    @Binding var opacity: Double
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rainfall overlay")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Close")
            }

            Toggle("Enabled", isOn: $isVisible)

            Picker("Timeframe", selection: $timeframe) {
                ForEach(RainfallTimeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $opacity, in: 0.1...0.9, step: 0.1)
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            RainfallLegendView()
        }
        .padding(12)
        .frame(width: 260)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: .cornerMedium)
        )
    }
}

// MARK: - Legend

struct RainfallLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("mm")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LinearGradient(
                stops: RainfallColorScale.gradientStops,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            HStack {
                ForEach(
                    Array(RainfallColorScale.stops.dropFirst().enumerated()),
                    id: \.offset
                ) { _, stop in
                    Text(stop.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    if stop.label != RainfallColorScale.stops.last?.label {
                        Spacer(minLength: 2)
                    }
                }
            }
        }
    }
}
