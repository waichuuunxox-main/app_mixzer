import Foundation
import Yams

struct GuidelineEntry: Codable {
    let zh: String
    let en: String
}

struct Guidelines: Codable {
    let ui_ux: GuidelineEntry?
    let animation: GuidelineEntry?
    let routing: GuidelineEntry?
    let state_management: GuidelineEntry?
    let components: GuidelineEntry?
    let data_api: GuidelineEntry?
    let i18n: GuidelineEntry?
    let testing: GuidelineEntry?
    let performance: GuidelineEntry?
    let deployment: GuidelineEntry?
}

enum GuidelinesError: Error {
    case resourceNotFound
    case parseError(Error)
}

final class GuidelinesService {
    static func load(from url: URL) throws -> Guidelines {
        let text = try String(contentsOf: url, encoding: .utf8)
        do {
            let decoder = YAMLDecoder()
            let guidelines = try decoder.decode(Guidelines.self, from: text)
            return guidelines
        } catch {
            // Fall back to JSON decoding if YAML parse fails
            if let data = text.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(Guidelines.self, from: data)
                } catch {
                    throw GuidelinesError.parseError(error)
                }
            }
            throw GuidelinesError.parseError(error)
        }
    }
}
