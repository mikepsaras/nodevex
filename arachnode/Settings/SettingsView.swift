import SwiftUI

struct SettingsView: View {
    @Bindable var terminologyStore: TerminologyStore
    @Bindable var appearanceStore: AppearanceStore
    @Bindable var layoutPreferenceStore: LayoutPreferenceStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceStore.mode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
            Section("Layout") {
                Toggle("Show category regions", isOn: $layoutPreferenceStore.showCategoryRegions)
            }
            Section("Inbound") {
                TextField("Singular", text: $terminologyStore.terminology.inboundSingular)
                TextField("Plural", text: $terminologyStore.terminology.inboundPlural)
            }
            Section("Outbound") {
                TextField("Singular", text: $terminologyStore.terminology.outboundSingular)
                TextField("Plural", text: $terminologyStore.terminology.outboundPlural)
            }
            Section("Valence") {
                TextField("Positive", text: $terminologyStore.terminology.valencePositive)
                TextField("Negative", text: $terminologyStore.terminology.valenceNegative)
                TextField("Neutral", text: $terminologyStore.terminology.valenceNeutral)
            }
            HStack {
                Spacer()
                Button("Reset to defaults") {
                    terminologyStore.terminology = .default
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
    }
}
