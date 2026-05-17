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
                Section("Soil Type") {
                    Picker("Texture", selection: $textureClass) {
                        ForEach(SoilOverride.TextureClass.allCases, id: \.self) { tc in
                            Text(tc.rawValue).tag(tc)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Sun Exposure") {
                    Picker("Exposure", selection: $exposure) {
                        ForEach(SoilOverride.Exposure.allCases, id: \.self) { exp in
                            Label(exp.rawValue, systemImage: exp.icon).tag(exp)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if currentOverride != nil {
                    Section {
                        Button("Remove Override", role: .destructive) {
                            onSave(nil)
                        }
                    }
                }
            }
            .navigationTitle("Soil Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(SoilOverride(textureClass: textureClass, exposure: exposure))
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
