import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        workoutConfiguration
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        workoutConfiguration
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        workoutConfiguration
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        workoutConfiguration
    }

    private var workoutConfiguration: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 1.0, green: 0.55, blue: 0.16, alpha: 1.0),
            icon: UIImage(systemName: "figure.strengthtraining.traditional"),
            title: ShieldConfiguration.Label(
                text: "筋トレしよう",
                color: .black
            ),
            subtitle: ShieldConfiguration.Label(
                text: "欲しがりません。痩せるまでは。先にスクワットを終わらせよう。",
                color: UIColor.black.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "筋トレする",
                color: .white
            ),
            primaryButtonBackgroundColor: .black,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "痩せるまで我慢",
                color: .black
            )
        )
    }
}
