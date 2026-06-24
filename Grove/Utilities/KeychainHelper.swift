import Foundation
import Security

enum KeychainHelper {

    // MARK: - Read (security CLI — reads items created by other apps without a popup)

    nonisolated static func read(service: String, account: String? = nil) -> Data? {
        var args = ["find-generic-password", "-s", service, "-w"]
        if let account {
            args.insert(contentsOf: ["-a", account], at: 1)
        }
        guard let output = runSecurity(args) else { return nil }
        return output.data(using: .utf8)
    }

    nonisolated static func readString(service: String, account: String? = nil) -> String? {
        var args = ["find-generic-password", "-s", service, "-w"]
        if let account {
            args.insert(contentsOf: ["-a", account], at: 1)
        }
        return runSecurity(args)
    }

    // MARK: - Read / Write / Delete (SecItem API — own app items)

    /// Reads an item this app created. Uses the SecItem API (not the `security`
    /// CLI) so the read comes from the Grove process the keychain ACL already
    /// trusts — no login-password popup. Use this for Grove's own items; use
    /// `read*` above only for items created by other apps.
    nonisolated static func readOwn(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func save(_ data: Data, service: String, account: String) throws {
        // Delete first so the item is always (re-)created by the current process.
        // SecItemUpdate preserves the old ACL (tied to the binary that created the
        // item), which causes a password prompt whenever a differently-signed binary
        // (ad-hoc builds, re-installs) tries to read it. By deleting and re-adding
        // we can attach a fresh ACL that allows any application on the unlocked Mac
        // to read the token without prompting — appropriate for a developer OAuth
        // token stored in the user's login keychain.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // SecAccessCreate with an empty trusted-applications list means
        // "all applications are trusted" on macOS — no per-app ACL prompt.
        var access: SecAccess?
        SecAccessCreate("Grove GitHub token" as CFString, [] as CFArray, &access)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        if let access { addQuery[kSecAttrAccess as String] = access }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
    }

    nonisolated static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }

    // MARK: - Private

    private nonisolated static func runSecurity(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    enum KeychainError: Error {
        case operationFailed(OSStatus)
    }
}
