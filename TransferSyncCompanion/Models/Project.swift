import Foundation

struct Project: Codable, Identifiable {
    let id: String
    let name: String
    let rootAssetId: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case rootAssetId = "root_asset_id"
    }
}
