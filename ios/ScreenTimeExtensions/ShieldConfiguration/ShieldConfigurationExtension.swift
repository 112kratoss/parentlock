import Foundation
import ManagedSettings
import ManagedSettingsUI

// Scaffold only: add this file to a real Shield Configuration extension target in Xcode.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemChromeMaterialDark,
            backgroundColor: .black,
            icon: nil,
            title: ShieldConfiguration.Label(text: "ParentLock"),
            subtitle: ShieldConfiguration.Label(
                text: "This app is blocked right now."
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Ask Parent"),
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Go Back")
        )
    }
}
