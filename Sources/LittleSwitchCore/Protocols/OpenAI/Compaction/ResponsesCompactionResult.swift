import Foundation
import LittleSwitchCommon

package struct ResponsesCompactionResult: Sendable {
    package let itemJSON: Data
    package let usage: ResponsesUsage
}
