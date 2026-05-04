import SwiftUI

struct SettingsView: View {
    @Bindable var store: TerminologyStore

    var body: some View {
        Form {
            Section("Inbound") {
                TextField("Singular", text: $store.terminology.inboundSingular)
                TextField("Plural", text: $store.terminology.inboundPlural)
            }
            Section("Outbound") {
                TextField("Singular", text: $store.terminology.outboundSingular)
                TextField("Plural", text: $store.terminology.outboundPlural)
            }
            Section("Valence") {
                TextField("Positive", text: $store.terminology.valencePositive)
                TextField("Negative", text: $store.terminology.valenceNegative)
                TextField("Neutral", text: $store.terminology.valenceNeutral)
            }
            HStack {
                Spacer()
                Button("Reset to defaults") {
                    store.terminology = .default
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
    }
}
