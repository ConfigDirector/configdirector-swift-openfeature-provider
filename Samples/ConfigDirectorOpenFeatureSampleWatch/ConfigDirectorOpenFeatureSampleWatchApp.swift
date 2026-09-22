import ConfigDirectorOpenFeatureProvider
import OpenFeature
import SwiftUI

@main
struct ConfigDirectorOpenFeatureSampleWatchApp: App {
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
        ScrollView {
            Text("No client SDK key. Put one in Config.local.xcconfig and run the app again.")
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
