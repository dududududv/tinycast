import Foundation
import Observation

@MainActor
@Observable
final class OSSSettingsStore {
    var configuration: OSSConfiguration {
        didSet { persist() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let configurationKey = "ossUploadConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration =
            defaults.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(OSSConfiguration.self, from: $0) }
            ?? OSSConfiguration()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.configurationKey)
    }
}
