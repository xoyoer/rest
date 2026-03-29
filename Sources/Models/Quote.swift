import Foundation

struct Quote: Codable, Sendable {
    let en: String
    let zh: String
    let author: String?
}
