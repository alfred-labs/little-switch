import Foundation

package struct ModelImageProbeChallenge: Sendable {
    enum Error: Swift.Error { case invalidColors, imageEncoding }

    static let palette = ModelImageProbeColor.allCases.map(\.rawValue)
    package let png: Data
    package let expectedColors: [String]

    package init(png: Data, expectedColors: [String]) {
        self.png = png
        self.expectedColors = expectedColors
    }

    package static func make() throws -> Self {
        let shuffled = palette.shuffled()
        let colors = (Array(shuffled.prefix(3)) + [palette[Int.random(in: palette.indices)]]).shuffled()
        return try make(colors: colors)
    }

    package static func make(colors: [String]) throws -> Self {
        let palette = colors.compactMap(ModelImageProbeColor.init(rawValue:))
        guard colors.count == 4, Set(palette).count >= 3, palette.count == colors.count else {
            throw Error.invalidColors
        }
        return Self(png: try ModelImageProbePNG.encode(colors: palette), expectedColors: colors)
    }
}
