import Foundation

struct APIDataResponse<T: Decodable>: Decodable {
    let data: T
}

struct APIErrorResponse: Decodable {
    let error: String
}
