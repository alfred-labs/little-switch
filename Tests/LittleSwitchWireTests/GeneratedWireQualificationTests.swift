import LittleSwitchWire
import LittleSwitchWireContractFixtures
import Testing

@Suite("Automatic generated codec qualification")
struct GeneratedWireQualificationTests {
    @Test(arguments: WireGeneratedQualification.samples)
    func completeRoundTripOrExpectedError(_ sample: WireGeneratedSample) throws {
        let input = try JSONValue.parse(sample.input)
        if let expected = sample.expectedError {
            #expect(throws: expected, Comment(rawValue: sample.name)) {
                try sample.operation(input)
            }
        } else {
            #expect(try sample.operation(input) == input, Comment(rawValue: sample.name))
        }
    }
}
