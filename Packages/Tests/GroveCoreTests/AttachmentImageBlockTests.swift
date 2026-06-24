import Testing
import Foundation
import AppKit
@testable import GroveCore

@Suite("AttachmentImageBlock")
struct AttachmentImageBlockTests {

    // Magic-byte prefixes for the formats the Claude API accepts natively.
    private static let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let jpegMagic = Data([0xFF, 0xD8, 0xFF, 0xE0])
    private static let gifMagic = Data("GIF89a".utf8)
    private static let webpMagic = Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
                                         0x57, 0x45, 0x42, 0x50])

    @Test func detectsNativeMediaTypesByMagicBytes() {
        #expect(AttachmentFactory.nativeImageMediaType(for: Self.pngMagic) == "image/png")
        #expect(AttachmentFactory.nativeImageMediaType(for: Self.jpegMagic) == "image/jpeg")
        #expect(AttachmentFactory.nativeImageMediaType(for: Self.gifMagic) == "image/gif")
        #expect(AttachmentFactory.nativeImageMediaType(for: Self.webpMagic) == "image/webp")
    }

    @Test func rejectsNonImageBytes() {
        #expect(AttachmentFactory.nativeImageMediaType(for: Data("not an image".utf8)) == nil)
        #expect(AttachmentFactory.nativeImageMediaType(for: Data([0x00, 0x01])) == nil)
    }

    @Test func passesNativeFormatThroughUnchanged() {
        let attachment = Attachment(type: .image, name: "shot.png", imageData: Self.pngMagic)
        let block = AttachmentFactory.imageBlock(for: attachment)
        #expect(block?.mediaType == "image/png")
        #expect(block?.sourceID == attachment.id)
        #expect(block?.base64 == Self.pngMagic.base64EncodedString())
    }

    @Test func transcodesUnsupportedContainerToPNG() throws {
        // Clipboard images arrive as TIFF bytes (named ".png"); they must become real PNG.
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        #expect(AttachmentFactory.nativeImageMediaType(for: tiff) == nil)

        let attachment = Attachment(type: .image, name: "clipboard.png", imageData: tiff)
        let block = try #require(AttachmentFactory.imageBlock(for: attachment))
        #expect(block.mediaType == "image/png")
        let decoded = try #require(Data(base64Encoded: block.base64))
        #expect(AttachmentFactory.nativeImageMediaType(for: decoded) == "image/png")
    }

    @Test func skipsNonImageAndDatalessAttachments() {
        let text = Attachment(type: .text, name: "notes", textContent: "hi")
        let imageNoData = Attachment(type: .image, name: "broken.png")
        #expect(AttachmentFactory.imageBlock(for: text) == nil)
        #expect(AttachmentFactory.imageBlock(for: imageNoData) == nil)
    }

    @Test func imageBlocksFiltersToImagesOnly() {
        let attachments = [
            Attachment(type: .image, name: "a.png", imageData: Self.pngMagic),
            Attachment(type: .text, name: "b", textContent: "x"),
            Attachment(type: .image, name: "c.jpg", imageData: Self.jpegMagic),
        ]
        let blocks = AttachmentFactory.imageBlocks(from: attachments)
        #expect(blocks.count == 2)
        #expect(blocks.map(\.mediaType) == ["image/png", "image/jpeg"])
    }
}
