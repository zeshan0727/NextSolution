import SwiftUI

enum LedgerVisualTheme: String, CaseIterable, Identifiable {
    case classic = "Native Classic"
    case glass = "iOS 26 Glass Style"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .classic:
            return "Native iOS cards with maximum clarity and speed"
        case .glass:
            return "Layered translucent cards inspired by iOS 26"
        }
    }
}

private struct RecoveredSurfaceModifier: ViewModifier {
    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = LedgerVisualTheme.glass.rawValue
    let tint: Color
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if visualTheme == LedgerVisualTheme.classic.rawValue {
            content
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.7)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.30), lineWidth: 0.8)
                }
                .shadow(color: tint.opacity(0.16), radius: 14, y: 7)
        }
    }
}

extension View {
    func recoveredSurface(
        tint: Color = AppTheme.purple,
        cornerRadius: CGFloat = 22
    ) -> some View {
        modifier(RecoveredSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }
}
