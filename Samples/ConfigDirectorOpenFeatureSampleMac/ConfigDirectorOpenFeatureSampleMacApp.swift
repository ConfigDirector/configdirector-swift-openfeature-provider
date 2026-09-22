import ConfigDirectorOpenFeatureProvider
import OpenFeature
import SwiftUI

@main
struct ConfigDirectorOpenFeatureSampleMacApp: App {
    private let provider = SampleConfiguration.makeProvider()

    init() {
        guard let provider else { return }
        OpenFeatureAPI.shared.setProvider(provider: provider, initialContext: SampleConfiguration.context)
    }

    var body: some Scene {
        WindowGroup {
            if provider == nil {
                MissingSDKKeyView()
            } else {
                ContentView()
            }
        }
    }
}

struct MissingSDKKeyView: View {
    var body: some View {
        Text(
            """
            No client SDK key.

            Copy Config.local.example.xcconfig to Config.local.xcconfig, put your client SDK key \
            in it, and run the app again.
            """
        )
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(minWidth: 420, minHeight: 220)
    }
}
