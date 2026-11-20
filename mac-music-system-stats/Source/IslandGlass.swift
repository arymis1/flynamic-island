import SwiftUI

/// A single native glass surface. Readability comes from the center backing
/// in IslandView, leaving the perimeter transparent rather than drawing a rim.
struct IslandGlassChrome: ViewModifier {
    let expanded: Bool
    let shape: UnevenRoundedRectangle

    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(expanded ? .clear : .identity, in: shape)
        } else {
            content
        }
    }
}
