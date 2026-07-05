import BSWFoundation
import Foundation

/// httpbingo.org endpoints used by the demo.
enum HTTPBin {
    enum Hosts: BSWFoundation.Environment {
        case production
        case development

        var baseURL: URL {
            switch self {
            case .production:
                return URL(string: "https://httpbingo.org")!
            case .development:
                return URL(string: "https://dev.httpbingo.org")!
            }
        }
    }

    enum API: Endpoint {
        case ip
        case orderPizza
        case upload(fileURL: URL)

        var path: String {
            switch self {
            case .upload:
                return "/post"
            case .orderPizza:
                return "/forms/post"
            case .ip:
                return "/ip"
            }
        }

        var method: HTTPMethod {
            switch self {
            case .upload:
                return .POST
            case .orderPizza:
                return .POST
            default:
                return .GET
            }
        }

        var parameterEncoding: HTTPParameterEncoding {
            switch self {
            case .orderPizza:
                return .json
            default:
                return .url
            }
        }

        var parameters: [String: Any]? {
            switch self {
            case .orderPizza:
                return [
                    "topping": ["peperoni", "olives"]
                ]
            default:
                return nil
            }
        }

        var fileToUpload: URL? {
            switch self {
            case .upload(let fileURL):
                return fileURL
            default:
                return nil
            }
        }
    }

    enum Responses {
        struct IP: Decodable, Sendable {
            let origin: String
        }
    }
}
