import SwiftUI
import GroveCore

/// Tags an inline-code run so `CodePillRenderer` draws a rounded bubble behind it.
/// Conforms to AttributedStringKey (to set on the string) and TextAttribute (to
/// read back in the renderer).
enum CodePillAttribute: AttributedStringKey, TextAttribute {
    typealias Value = Bool
    static let name = "codePill"
}

/// Draws a rounded, subtly-bordered "bubble" behind inline-code runs while keeping
/// the paragraph in a single selectable, wrapping `Text`. macOS 15+ (`TextRenderer`).
struct CodePillRenderer: TextRenderer {
    var fill: Color
    var border: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[CodePillAttribute.self] != nil {
                    let rect = run.typographicBounds.rect.insetBy(dx: -3, dy: -1.5)
                    let shape = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(shape, with: .color(fill))
                    context.stroke(shape, with: .color(border), lineWidth: 0.6)
                }
                context.draw(run)
            }
        }
    }
}
