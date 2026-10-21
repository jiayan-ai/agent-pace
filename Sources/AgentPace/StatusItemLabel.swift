import AppKit

/// Render the symbol and text as one template. AppKit then applies the menu
/// bar's contrast to the whole label, including highlighted and inactive states.
enum StatusItemLabel {
    static func image(for title: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.black])
        let textSize = text.size()
        let size = NSSize(width: 21 + ceil(textSize.width), height: 18)
        let symbol = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black]))
        let image = NSImage(size: size, flipped: false) { _ in
            symbol?.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
            text.draw(at: NSPoint(x: 21, y: floor((size.height - textSize.height) / 2)))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Agent Pace · \(title)"
        return image
    }
}
