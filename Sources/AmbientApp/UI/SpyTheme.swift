import SwiftUI

/// Visual language of the HUD: dark glass, phosphor cyan lines, amber intel.
enum SpyTheme {
    static let accent = Color(red: 0.35, green: 0.93, blue: 1.0)       // phosphor cyan
    static let accentDim = accent.opacity(0.35)
    static let intel = Color(red: 1.0, green: 0.72, blue: 0.25)        // amber
    static let alert = Color(red: 1.0, green: 0.33, blue: 0.36)
    static let panel = Color(red: 0.02, green: 0.05, blue: 0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)

    static let cardWidth: CGFloat = 344
    static let cornerTick: CGFloat = 10

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Four L-shaped corner brackets around a rect.
struct CornerBrackets: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(length, rect.width / 2, rect.height / 2)
        // top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // top-right
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // bottom-left
        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return path
    }
}

/// Faint CRT scanlines.
struct Scanlines: View {
    var spacing: CGFloat = 3
    var opacity: Double = 0.035

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(opacity)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
