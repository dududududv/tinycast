import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        accessibilityTrusted ? "Granted" : "Not granted",
                        systemImage: accessibilityTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                } label: {
                    Text("Accessibility")
                    Text("Lets Tinycast paste a clipboard item into the app you were using.")
                }

                LabeledContent {
                    Button(
                        accessibilityTrusted
                            ? String(localized: "Open…") : String(localized: "Grant Access…")
                    ) {
                        Permissions.openAccessibilitySettings()
                    }
                } label: {
                    Text(
                        accessibilityTrusted
                            ? String(localized: "Manage in System Settings")
                            : String(localized: "Grant access")
                    )
                    Text("Opens Privacy & Security › Accessibility.")
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Access Tinycast needs to work with other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
    }
}
