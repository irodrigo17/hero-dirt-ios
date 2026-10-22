import SwiftUI

struct SoilOverrideSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentOverride: SoilOverride?
    let onSave: (SoilOverride?) -> Void

    @State private var textureClass: SoilOverride.TextureClass
    @State private var exposure: SoilOverride.Exposure

    init(currentOverride: SoilOverride?, onSave: @escaping (SoilOverride?) -> Void) {
        self.currentOverride = currentOverride
        self.onSave = onSave
        _textureClass = State(initialValue: currentOverride?.textureClass ?? .loam)
        _exposure = State(initialValue: currentOverride?.exposure ?? .partial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Dirt", selection: $textureClass) {
                        ForEach(SoilOverride.TextureClass.allCases, id: \.self) { tc in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tc.displayName)
                                Text(tc.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(tc)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("What's the dirt like?")
                }

                Section {
                    Picker("Sun", selection: $exposure) {
                        ForEach(SoilOverride.Exposure.allCases, id: \.self) { exp in
                            Label(exp.displayName, systemImage: exp.icon).tag(exp)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How much sun does it get?")
                } footer: {
                    Text("You know your local trails best. These settings fine-tune how fast this spot dries out after rain.")
                }

                if currentOverride != nil {
                    Section {
                        Button("Reset to Automatic", role: .destructive) {
                            onSave(nil)
                        }
                    }
                }
            }
            .navigationTitle("Tune This Trail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(SoilOverride(textureClass: textureClass, exposure: exposure))
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    SoilOverrideSheet(currentOverride: SoilOverride(textureClass: .clayLoam, exposure: .shaded)) { _ in }
}
