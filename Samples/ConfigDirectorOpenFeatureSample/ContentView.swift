import OpenFeature
import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var status = ProviderStatus.notReady
    @State private var context: (any EvaluationContext)?

    var body: some View {
        layout
            .onReceive(ProviderEvents.onMain) { _ in
                status = OpenFeatureAPI.shared.getProviderStatus()
                context = OpenFeatureAPI.shared.getEvaluationContext()
            }
    }

    @ViewBuilder
    private var layout: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                List {
                    contextSection
                }
                .frame(maxWidth: 340)

                Divider()

                List {
                    flagSection
                }
            }
        } else {
            List {
                flagSection
                contextSection
            }
        }
    }

    private var flagSection: some View {
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

    private var contextSection: some View {
        Section("Context") {
            UserPicker()
                .pickerStyle(.segmented)
                .labelsHidden()

            ContextSummary(context: context)
        }
    }
}
