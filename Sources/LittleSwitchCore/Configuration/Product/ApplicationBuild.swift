import Foundation

public enum ApplicationBuild {
    public static let infoDictionaryKey = "LSBuildTag"
    public static let developmentTag = "development"

    public static func tag(infoDictionary: [String: Any]?) -> String {
        guard let tag = infoDictionary?[infoDictionaryKey] as? String,
            !tag.isEmpty
        else {
            return developmentTag
        }
        return tag
    }

    public static var currentTag: String {
        tag(infoDictionary: Bundle.main.infoDictionary)
    }
}
