import Foundation

/// Mirrors Claude Code CLI's `--permission-mode` values.
///
/// See https://code.claude.com/docs/en/permission-modes for semantics.
public enum PermissionMode: String, CaseIterable, Sendable, Codable {
    case `default`
    case acceptEdits
    case plan
    case auto
    case bypassPermissions

    public var displayName: String {
        switch self {
        case .default: return "Ask"
        case .acceptEdits: return "Accept Edits"
        case .plan: return "Plan"
        case .auto: return "Auto"
        case .bypassPermissions: return "Bypass"
        }
    }

    public var systemImage: String {
        switch self {
        case .default: return "bolt.shield"
        case .acceptEdits: return "checkmark.shield"
        case .plan: return "eye"
        case .auto: return "wand.and.sparkles"
        case .bypassPermissions: return "bolt.shield.fill"
        }
    }

    /// When true, skip writing the PreToolUse hook settings and skip
    /// the `--allowedTools` pre-approval list — bypassPermissions mode
    /// disables the entire permission pipeline.
    public var skipsHookPipeline: Bool {
        self == .bypassPermissions
    }

    /// The value to pass to the CLI's `--permission-mode`, or nil when this isn't
    /// a real CLI mode. `default` needs no flag, and `auto` is Grove-only — it's
    /// implemented by auto-approving hook requests, so it must NOT be sent to the
    /// CLI (`--permission-mode auto` is invalid and silently falls back to asking).
    public var cliPermissionMode: String? {
        switch self {
        case .default, .auto: return nil
        case .acceptEdits, .plan, .bypassPermissions: return rawValue
        }
    }
}
