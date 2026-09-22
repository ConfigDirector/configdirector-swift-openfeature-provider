import OpenFeature
import SwiftUI

struct ContentView: View {
    @State private var status = ProviderStatus.notReady
    @State private var context: (any EvaluationContext)?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Context")
                    .font(.headline)
                    .foregroundColor(.secondary)

                UserPicker()
                    .pickerStyle(.segmented)
                    .labelsHidden()

                ContextSummary(context: context)

                Spacer()
            }
            .frame(maxWidth: 600, alignment: .leading)

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Flags")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    ProviderStatusLabel(status: status)
                        .font(.headline)
                }

                FlagRows()

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(60)
        .onReceive(ProviderEvents.onMain) { _ in
            status = OpenFeatureAPI.shared.getProviderStatus()
            context = OpenFeatureAPI.shared.getEvaluationContext()
        }
    }
}
