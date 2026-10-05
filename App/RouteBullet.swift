import SwiftUI
import TrainTimerCore

/// The MTA route "bullet": a colored circle, a diamond for express variants, a pill for SIR.
struct RouteBullet: View {
    let style: RouteStyle
    var size: CGFloat = 18

    var body: some View {
        Text(style.symbol)
            .font(.system(size: size * (style.symbol.count > 1 ? 0.45 : 0.62), weight: .bold))
            .foregroundStyle(style.usesDarkText ? Color.black : Color.white)
            .frame(width: style.symbol.count > 1 ? size * 1.6 : size, height: size)
            .background { shape.fill(Color(rgb: style.color)) }
            .accessibilityLabel(style.isExpress ? "\(style.symbol) express" : style.symbol)
    }

    private var shape: AnyShape {
        if style.isExpress {
            AnyShape(Rectangle().rotation(.degrees(45)).scale(0.74))
        } else {
            AnyShape(Capsule())
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
