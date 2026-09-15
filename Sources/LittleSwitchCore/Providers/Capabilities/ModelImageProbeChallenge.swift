import Foundation

package struct ModelImageProbeChallenge: Sendable {
    enum Error: Swift.Error { case invalidColors, imageEncoding }

    static let palette = ["red", "green", "blue", "yellow", "black", "white"]
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
        guard colors.count == 4, Set(colors).count >= 3, colors.allSatisfy(palette.contains) else {
            throw Error.invalidColors
        }
        return Self(png: try ModelImageProbePNG.encode(colors: colors), expectedColors: colors)
    }
}
