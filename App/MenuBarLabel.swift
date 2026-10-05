import AppKit
import SwiftUI
import TrainTimerCore

/// The menu bar item: each upcoming route's colored bullet and its minutes, like the dropdown's rows.
/// Shows a tram icon while there's nothing to count down to.
struct MenuBarLabel: View {
    let arrivals: [MenuBarArrival]

    var body: some View {
        if arrivals.isEmpty {
            Image(systemName: "tram.fill")
        } else {
            Image(nsImage: Self.image(for: arrivals))
                .accessibilityLabel(arrivals.map { "\($0.route.symbol) \($0.minutes)" }.joined(separator: ", "))
        }
    }

    private static let bulletSize: CGFloat = 15
    private static let bulletToMinutes: CGFloat = 3
    private static let betweenArrivals: CGFloat = 7

    /// Status items are template images by default, which would flatten the bullets to one color.
    /// This one keeps its colors, and draws the minutes when the menu bar draws it, so `labelColor`
    /// picks up the menu bar's own light or dark appearance.
    private static func image(for arrivals: [MenuBarArrival]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .medium)
        let items = arrivals.map { arrival in
            (bullet: bulletImage(arrival.route), minutes: arrival.minutes as NSString)
        }
        let widths = items.map { item in
            item.bullet.size.width + bulletToMinutes + item.minutes.size(withAttributes: [.font: font]).width
        }
        let height = max(bulletSize, ceil(font.ascender - font.descender))
        let width = ceil(widths.reduce(0, +) + betweenArrivals * CGFloat(items.count - 1))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            var x: CGFloat = 0
            for (item, itemWidth) in zip(items, widths) {
                let bullet = item.bullet.size
                item.bullet.draw(in: NSRect(x: x, y: (height - bullet.height) / 2, width: bullet.width, height: bullet.height))
                // Center the digits' cap height on the bullet rather than the whole line box.
                let baseline = (height - font.capHeight) / 2
                item.minutes.draw(at: NSPoint(x: x + bullet.width + bulletToMinutes, y: baseline + font.descender), withAttributes: attributes)
                x += itemWidth + betweenArrivals
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    @MainActor
    private static func bulletImage(_ route: RouteStyle) -> NSImage {
        let renderer = ImageRenderer(content: RouteBullet(style: route, size: bulletSize))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage()
    }
}
