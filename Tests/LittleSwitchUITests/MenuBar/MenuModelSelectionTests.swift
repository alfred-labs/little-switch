import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Menu model selection")
struct MenuModelSelectionTests {
    private let options = [
        MenuModelOption(id: "none", label: "Not assigned", mapping: nil),
        MenuModelOption(
            id: "zai",
            label: "z.ai/glm-4.7",
            mapping: ModelMapping(providerID: UUID(), modelID: "glm-4.7")
        ),
        MenuModelOption(
            id: "ollama",
            label: "ollama/xlarge",
            mapping: ModelMapping(providerID: UUID(), modelID: "xlarge")
        ),
    ]

    @Test("Steps move by one and wrap around both ends")
    func stepping() {
        #expect(MenuModelSelection.step(options: options, from: options[0], by: 1) == options[1])
        #expect(MenuModelSelection.step(options: options, from: options[1], by: -1) == options[0])
        #expect(MenuModelSelection.step(options: options, from: options[2], by: 1) == options[0])
        #expect(MenuModelSelection.step(options: options, from: options[0], by: -1) == options[2])
    }

    @Test("Larger strides land modulo the list length")
    func largerStrides() {
        #expect(MenuModelSelection.step(options: options, from: options[0], by: 4) == options[1])
        #expect(MenuModelSelection.step(options: options, from: options[1], by: -4) == options[0])
    }

    @Test("An unknown or missing selection steps in from the matching end")
    func unknownSelection() {
        let removed = MenuModelOption(
            id: "removed",
            label: "Removed provider/model",
            mapping: ModelMapping(providerID: UUID(), modelID: "gone")
        )
        #expect(MenuModelSelection.step(options: options, from: nil, by: 1) == options[0])
        #expect(MenuModelSelection.step(options: options, from: nil, by: -1) == options[2])
        #expect(MenuModelSelection.step(options: options, from: removed, by: 1) == options[0])
        #expect(MenuModelSelection.step(options: options, from: removed, by: -1) == options[2])
    }

    @Test("An empty list has nothing to step to")
    func emptyOptions() {
        #expect(MenuModelSelection.step(options: [], from: options[0], by: 1) == nil)
    }
}
