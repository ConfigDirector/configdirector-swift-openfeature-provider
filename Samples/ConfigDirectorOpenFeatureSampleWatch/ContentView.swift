import OpenFeature
import SwiftUI

struct ContentView: View {
    @State private var status = ProviderStatus.notReady
    @State private var context: (any EvaluationContext)?

    var body: some View {
        NavigationView {
            List {
                Section("Flags") {
                    FlagRows()
                }

                Section("Context") {
                    UserPicker()

                    ContextSummary(context: context)
                }
            }
            .navigationTitle(status.label)
        }
        .onReceive(ProviderEvents.onMain) { _ in
            status = OpenFeatureAPI.shared.getProviderStatus()
            context = OpenFeatureAPI.shared.getEvaluationContext()
        }
    }
}
