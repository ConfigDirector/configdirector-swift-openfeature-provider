import OpenFeature
import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var status = ProviderStatus.notReady
    @State private var context: (any EvaluationContext)?
    @State private var selectedUser = SampleUser.configured

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
            FlagRow("temporary-feature-flag", default: false)
            FlagRow("permanent-kill-switch", default: true)
            FlagRow("integer-config", default: 10)
            FlagRow("day-of-the-week-config", default: "Friday")
            FlagRow("json-value-config", default: Value.structure([:]))
        } header: {
            HStack {
                Text("Flags")
                Spacer()
                Text(statusLabel)
                    .foregroundColor(status == .ready ? .green : .secondary)
            }
        }
    }

    private var contextSection: some View {
        Section("Context") {
            Picker("User", selection: userSelection) {
                ForEach(SampleUser.allCases) { user in
                    Text(user.label).tag(user)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ContextSummary(context: context)
        }
    }

    private var statusLabel: String {
        switch status {
        case .ready: "Ready"
        case .reconciling: "Reconciling…"
        case .error, .fatal: "Error"
        case .stale: "Stale"
        case .notReady: "Connecting…"
        }
    }

    private var userSelection: Binding<SampleUser> {
        Binding(
            get: { selectedUser },
            set: { user in
                selectedUser = user
                OpenFeatureAPI.shared.setEvaluationContext(evaluationContext: user.context)
            }
        )
    }
}
