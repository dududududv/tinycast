import SwiftUI

struct OSSSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(OSSSettingsStore.self) private var settings
    @State private var accessKeyID = ""
    @State private var accessKeySecret = ""
    @State private var hasCredentials = false
    @State private var credentialMessage: CredentialMessage?

    private var coordinator: OSSUploadCoordinator { core.ossUploadCoordinator }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            connectionSection(configuration: $settings.configuration)
            credentialsSection
            linkSection(configuration: $settings.configuration)
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCredentialStatus)
    }

    private func connectionSection(configuration: Binding<OSSConfiguration>) -> some View {
        Section {
            LabeledContent {
                TextField("Endpoint", text: configuration.endpoint)
                    .labelsHidden()
                    .frame(width: 300)
            } label: {
                Text("Endpoint")
                Text("The public HTTPS endpoint without the bucket name.")
            }
            LabeledContent {
                TextField("Region", text: configuration.region)
                    .labelsHidden()
                    .frame(width: 300)
            } label: {
                Text("Region")
                Text("The signing region, such as cn-hangzhou.")
            }
            LabeledContent {
                TextField("Bucket", text: configuration.bucket)
                    .labelsHidden()
                    .frame(width: 300)
            } label: {
                Text("Bucket")
                Text("Uploads use virtual-hosted OSS URLs.")
            }
        } header: {
            Text("OSS Connection")
        } footer: {
            Text("Use a RAM user limited to oss:PutObject and oss:GetObject for this bucket.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsSection: some View {
        Section {
            LabeledContent {
                TextField("AccessKey ID", text: $accessKeyID)
                    .labelsHidden()
                    .frame(width: 300)
            } label: {
                Text("AccessKey ID")
            }
            LabeledContent {
                SecureField(
                    "AccessKey Secret", text: $accessKeySecret,
                    prompt: Text(hasCredentials ? "Stored in Keychain" : "Required")
                )
                .labelsHidden()
                .frame(width: 300)
            } label: {
                Text("AccessKey Secret")
                if hasCredentials {
                    Text("Leave blank to keep the saved secret.")
                }
            }
            LabeledContent {
                Button(hasCredentials ? "Update Credentials" : "Save Credentials") {
                    saveCredentials()
                }
                .settingsEnabled(
                    !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasCredentials {
                    Button("Remove", role: .destructive) {
                        removeCredentials()
                    }
                }
            } label: {
                if let credentialMessage {
                    Label(credentialMessage.text, systemImage: credentialMessage.symbol)
                        .foregroundStyle(credentialMessage.style)
                } else {
                    Text(hasCredentials ? "Credentials saved" : "Credentials not saved")
                    Text("Secrets stay in your login Keychain.")
                }
            }
        } header: {
            Text("Credentials")
        }
    }

    private func linkSection(configuration: Binding<OSSConfiguration>) -> some View {
        Section {
            LabeledContent {
                TextField("Object prefix", text: configuration.objectPrefix)
                    .labelsHidden()
                    .frame(width: 300)
            } label: {
                Text("Object Prefix")
                Text("Files are organized by UTC date and given collision-safe names.")
            }
            Picker(selection: configuration.linkAccess) {
                Text("Signed, expiring link").tag(OSSLinkAccess.signed)
                Text("Public URL").tag(OSSLinkAccess.publicRead)
            } label: {
                Text("Link Access")
                Text("Choose signed links for private buckets.")
            }
            Picker(selection: configuration.linkExpiry) {
                ForEach(OSSLinkExpiry.allCases) { expiry in
                    Text(expiry.title).tag(expiry)
                }
            } label: {
                Text("Signed Link Lifetime")
                Text("Choose how long private links remain valid, up to seven days.")
            }
            .settingsEnabled(configuration.wrappedValue.linkAccess == .signed)
        } header: {
            Text("Uploaded Objects")
        }
    }

    private func loadCredentialStatus() {
        do {
            accessKeyID = try coordinator.storedAccessKeyID() ?? ""
            hasCredentials = try coordinator.hasStoredCredentials()
            credentialMessage = nil
        } catch {
            credentialMessage = .error(
                String(localized: "The login Keychain could not be accessed."))
        }
    }

    private func saveCredentials() {
        do {
            try coordinator.saveCredentials(
                accessKeyID: accessKeyID,
                accessKeySecret: accessKeySecret.isEmpty ? nil : accessKeySecret)
            accessKeySecret = ""
            hasCredentials = true
            credentialMessage = .success(String(localized: "Credentials saved to Keychain."))
        } catch {
            credentialMessage = .error(
                String(localized: "The credentials could not be saved to Keychain."))
        }
    }

    private func removeCredentials() {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Remove OSS credentials?"),
                    message: String(
                        localized: "Uploads will stop working until new credentials are saved."),
                    symbol: "key.slash", confirmTitle: String(localized: "Remove"),
                    confirmRole: .destructive)
            else { return }
            do {
                try coordinator.removeCredentials()
                accessKeyID = ""
                accessKeySecret = ""
                hasCredentials = false
                credentialMessage = .success(
                    String(localized: "Credentials removed from Keychain."))
            } catch {
                credentialMessage = .error(
                    String(localized: "The credentials could not be removed from Keychain."))
            }
        }
    }
}

private struct CredentialMessage {
    let text: String
    let symbol: String
    let style: AnyShapeStyle

    static func success(_ text: String) -> Self {
        Self(text: text, symbol: "checkmark.circle.fill", style: AnyShapeStyle(.green))
    }

    static func error(_ text: String) -> Self {
        Self(text: text, symbol: "exclamationmark.triangle.fill", style: AnyShapeStyle(.orange))
    }
}

private extension OSSLinkExpiry {
    var title: String {
        switch self {
        case .fifteenMinutes: return String(localized: "15 minutes")
        case .oneHour: return String(localized: "1 hour")
        case .sixHours: return String(localized: "6 hours")
        case .oneDay: return String(localized: "1 day")
        case .threeDays: return String(localized: "3 days")
        case .sevenDays: return String(localized: "7 days")
        }
    }
}
