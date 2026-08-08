import SwiftUI

// Allows custom Color shorthand such as `.foregroundStyle(.nextOrange)`
// to compile consistently with the iOS 16 SwiftUI toolchain.
extension ShapeStyle where Self == Color {
    static var nextOrange: Color { Color.nextOrange }
}
