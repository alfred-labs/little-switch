import LittleSwitchCommon
import LittleSwitchCore

package struct AppliedCodexSnapshot: Sendable {
    let configuration: CodexConfiguration
    let providers: [Provider]
    let signature: CodexManagedProfileSignature
}
