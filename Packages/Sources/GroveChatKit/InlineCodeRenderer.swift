import SwiftUI
import GroveCore

// MARK: - CodePillAttribute

struct CodePillAttribute: CodableAttributedStringKey, TextAttribute {
    typealias Value = Bool
    static let name = "codePill"
}

// MARK: - Attribute Scope

extension AttributeScopes {
    struct GroveAttributes: AttributeScope {
        let codePill: CodePillAttribute
        var swiftUI: SwiftUIAttributes
    }
    var grove: GroveAttributes.Type { GroveAttributes.self }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.GroveAttributes, T>
    ) -> T { self[T.self] }
}

// MARK: - Renderer

struct CodePillRenderer: TextRenderer {
    var fill: Color
    var border: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[CodePillAttribute.self] != nil {
                    let rect = run.typographicBounds.rect
                    let pill = rect.insetBy(dx: -3, dy: -2)
                    context.fill(Path(roundedRect: pill, cornerRadius: 3), with: .color(fill))
                    context.stroke(Path(roundedRect: pill, cornerRadius: 3), with: .color(border), lineWidth: 0.5)
                }
                context.draw(run)
            }
        }
    }
}
