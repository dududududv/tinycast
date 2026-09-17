import Foundation

private var failures = 0

private func check(_ description: String, _ condition: @autoclosure () -> Bool) {
    if condition() { return }
    failures += 1
    print("FAIL: \(description)")
}

let catalogURL = URL(fileURLWithPath: "Tinycast/Resources/Localizable.xcstrings")
let data = try Data(contentsOf: catalogURL)
let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
let strings = root?["strings"] as? [String: Any]

let requiredKeys = [
    "General", "Applications", "System Settings", "System Actions", "Commands", "Quicklinks", "AI",
    "OSS Upload", "File Search", "Notes", "Snippets", "Window Management", "Clipboard",
    "Emoji & Symbols", "Calendar", "Extensions", "Permissions", "Backup", "About", "Launcher",
    "Features", "Advanced", "Search applications…", "Search System Settings…",
    "Search system actions…", "Search commands…", "Custom Commands", "Enable custom commands",
    "Enable quicklinks", "Enable snippets", "Enable window management",
    "Search for apps and commands…", "Enable %@"
]

for key in requiredKeys {
    let entry = strings?[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    let chinese = localizations?["zh-Hans"] as? [String: Any]
    let unit = chinese?["stringUnit"] as? [String: Any]
    let value = unit?["value"] as? String
    check("\(key) has a Simplified Chinese translation", value != nil && value != key)
}

if failures == 0 {
    print("localization tests passed")
} else {
    exit(1)
}
