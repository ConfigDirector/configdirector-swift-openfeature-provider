import OpenFeature
import SwiftUI

struct ContentView: View {
    @State private var status = ProviderStatus.notReady
    @State private var context: (any EvaluationContext)?

    var body: some View {
        HSplitView {
            List {
                Section("Context") {
                    UserPicker()
                        .pickerStyle(.segmented)
                        .labelsHidden()

                    ContextSummary(context: context)
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)

            List {
                Section {
                    FlagRows()
                } header: {
                    HStack {
                        Text("Flags")
                        Spacer()
                        ProviderStatusLabel(status: status)
                    }
                }
            }
            .frame(minWidth: 340)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onReceive(ProviderEvents.onMain) { _ in
            status = OpenFeatureAPI.shared.getProviderStatus()
            context = OpenFeatureAPI.shared.getEvaluationContext()
        }
    }
}
