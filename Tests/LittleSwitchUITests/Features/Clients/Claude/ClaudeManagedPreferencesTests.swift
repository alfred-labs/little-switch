import Testing

@testable import LittleSwitchUI

@Suite("Claude managed organization preference")
struct ClaudeManagedPreferencesTests {
    @Test("Only a forced, nonempty organization string or array blocks profiles")
    func organizationRestriction() {
        let uuid = "11111111-2222-4333-8444-555555555555"
        #expect(ClaudeManagedPreferences.restrictsOrganization(value: uuid, isForced: true))
        #expect(ClaudeManagedPreferences.restrictsOrganization(value: ["", uuid], isForced: true))
        for value: Any? in [nil, "", " \n", [String](), ["", " "], false, 42, ["unrelated": true]] {
            #expect(!ClaudeManagedPreferences.restrictsOrganization(value: value, isForced: true))
        }
        #expect(!ClaudeManagedPreferences.restrictsOrganization(value: uuid, isForced: false))
        #expect(!ClaudeManagedPreferences.restrictsOrganization(value: [uuid], isForced: false))
    }
}
