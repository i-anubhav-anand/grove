import Foundation

/// Application Support directory scoped by the running bundle identifier.
/// Production (`com.grove.Grove`) keeps the historical `Grove` directory.
/// Any other bundle id (e.g. a dev build at `com.grove.Grove.dev`) maps to
/// `Grove.<suffix>` so alternate builds never share state with production.
public enum AppSupport {
    public static let bundleScopedURL: URL = {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return root.appendingPathComponent(directoryName, isDirectory: true)
    }()

    private static var directoryName: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.grove.Grove"
        if bundleID == "com.grove.Grove" { return "Grove" }
        let suffix = bundleID.split(separator: ".").last.map(String.init) ?? "dev"
        return "Grove.\(suffix)"
    }
}
