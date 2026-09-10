import CoreGraphics

/// Pointer-to-slot math behind the menu's series chart: bars share the row
/// width equally, so one helper drives both the hover index and the band
/// behind the hovered bar.
enum MenuSeriesGeometry {
    /// Nearest slot to the pointer, clamped so a straggling move event past
    /// the last bar still names a real day.
    static func barIndex(at x: CGFloat, width: CGFloat, dayCount: Int) -> Int {
        guard width > 0, dayCount > 0 else {
            return 0
        }
        return min(max(Int(x / width * CGFloat(dayCount)), 0), dayCount - 1)
    }
}
