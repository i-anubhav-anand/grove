import Foundation
import AppKit

// MARK: - Attachment

public struct Attachment: Identifiable, Sendable {
    public let id: UUID
    public let type: AttachmentType
    public let name: String
    public let path: String
    public let fileSize: Int64?
    public let textContent: String?
    public let imageData: Data?

    public init(
        id: UUID = UUID(),
        type: AttachmentType,
        name: String,
        path: String = "",
        fileSize: Int64? = nil,
        textContent: String? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.path = path
        self.fileSize = fileSize
        self.textContent = textContent
        self.imageData = imageData
    }

    public enum AttachmentType: String, Sendable {
        case image
        case file
        case text
        case link
    }

    public var promptContext: String {
        if type == .text, let text = textContent {
            return "[Pasted text:\n\(text)\n]"
        }
        if type == .link {
            return "[Link: \(path)]"
        }
        return "[Attached \(type.rawValue): \(path)]"
    }
}

// MARK: - Image Block

/// A single image ready to send to the `claude` CLI as a base64 content block.
/// `sourceID` links back to the originating `Attachment` so the text prompt can
/// drop the redundant `[Attached image: …]` line for images sent this way.
public struct ImageBlock: Sendable {
    public let sourceID: UUID
    public let mediaType: String
    public let base64: String

    public init(sourceID: UUID, mediaType: String, base64: String) {
        self.sourceID = sourceID
        self.mediaType = mediaType
        self.base64 = base64
    }
}

// MARK: - Attachment Factory

public enum AttachmentFactory {

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic"
    ]

    public static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "csv", "tsv", "log", "json", "jsonl", "ndjson",
        "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "properties",
        "swift", "py", "js", "ts", "jsx", "tsx", "rb", "go", "rs", "java", "kt", "kts",
        "c", "h", "cpp", "hpp", "cc", "cxx", "cs", "m", "mm", "r", "lua", "pl", "pm",
        "php", "dart", "scala", "clj", "cljs", "ex", "exs", "erl", "hrl", "hs", "elm",
        "html", "htm", "css", "scss", "sass", "less", "vue", "svelte",
        "sh", "bash", "zsh", "fish", "bat", "cmd", "ps1", "psm1",
        "sql", "graphql", "gql", "proto", "thrift",
        "dockerfile", "makefile", "cmake", "gradle", "gemfile", "podfile",
        "gitignore", "gitattributes", "editorconfig", "eslintrc", "prettierrc",
        "lock", "sum", "mod", "resolved", "xcodeproj", "pbxproj", "plist",
        "tf", "hcl", "nix", "dhall",
        "tex", "bib", "sty",
        "pdf",
    ]

    public static func isSupportedExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return imageExtensions.contains(lower) || textExtensions.contains(lower)
    }

    public static func fromFileURL(_ url: URL) -> Attachment? {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let type: Attachment.AttachmentType = imageExtensions.contains(ext) ? .image : .file
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
        let imgData: Data? = type == .image ? (try? Data(contentsOf: url)) : nil

        return Attachment(
            type: type,
            name: name,
            path: url.path,
            fileSize: fileSize,
            imageData: imgData
        )
    }

    public static func resolvingClipboardImages(_ attachments: [Attachment]) -> (resolved: [Attachment], tempPaths: [String]) {
        var tempPaths: [String] = []
        let resolved = attachments.map { attachment -> Attachment in
            guard attachment.type == .image, attachment.path.isEmpty,
                  let data = attachment.imageData else { return attachment }
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("grove-img-\(UUID().uuidString.prefix(8)).png")
            guard (try? data.write(to: tmpURL)) != nil else { return attachment }
            tempPaths.append(tmpURL.path)
            return Attachment(id: attachment.id, type: .image, name: attachment.name,
                              path: tmpURL.path, fileSize: Int64(data.count), imageData: data)
        }
        return (resolved, tempPaths)
    }

    public static func fromURL(_ url: URL) -> Attachment {
        let domain = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        return Attachment(type: .link, name: domain, path: url.absoluteString)
    }

    public static let longTextThreshold = 200
    public static let maxTextLength = 100_000

    public static func fromLongText(_ text: String) -> Attachment {
        let truncated = text.count > maxTextLength ? String(text.prefix(maxTextLength)) : text
        let lineCount = truncated.components(separatedBy: .newlines).count
        let charCount = truncated.count
        let suffix = text.count > maxTextLength ? " (truncated)" : ""
        let name = "Pasted text (\(lineCount) lines, \(charCount) chars\(suffix))"

        return Attachment(type: .text, name: name, textContent: truncated)
    }

    // MARK: - Image Blocks

    /// Convert image attachments into base64 content blocks the `claude` CLI can render.
    /// Non-image attachments and images whose bytes can't be turned into a supported
    /// format are skipped (they keep their textual `[Attached …]` reference instead).
    public static func imageBlocks(from attachments: [Attachment]) -> [ImageBlock] {
        attachments.compactMap(imageBlock(for:))
    }

    public static func imageBlock(for attachment: Attachment) -> ImageBlock? {
        guard attachment.type == .image, let data = attachment.imageData else { return nil }
        if let mediaType = nativeImageMediaType(for: data) {
            return ImageBlock(sourceID: attachment.id, mediaType: mediaType, base64: data.base64EncodedString())
        }
        // Unsupported container (TIFF, BMP, HEIC, clipboard TIFF, …) — transcode to PNG.
        guard let png = pngData(from: data) else { return nil }
        return ImageBlock(sourceID: attachment.id, mediaType: "image/png", base64: png.base64EncodedString())
    }

    /// The Claude API accepts png, jpeg, gif, and webp. Detect by magic bytes rather than
    /// file extension — clipboard images are TIFF bytes regardless of the `.png` name we give them.
    static func nativeImageMediaType(for data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return nil }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" } // "GIF8"
        if bytes.count >= 12,
           bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),          // "RIFF"
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] {     // "WEBP"
            return "image/webp"
        }
        return nil
    }

    private static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
