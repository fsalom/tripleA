import Foundation

public struct Endpoint{
    public enum HTTPMethod{
        case get
        case post
        case patch
        case put
        case delete

        var rawValue: String{
            switch self {
            case .get: return "GET"
            case .post: return "POST"
            case .patch: return "PATCH"
            case .put: return "PUT"
            case .delete: return "DELETE"
            }
        }
    }

    public enum ContentType {
        case json
        case xml
        case image
        case form
        case custom(contentType: String)
        case defaultInMethod(_ method: HTTPMethod)
        case none

        public var rawValue: String? {
            switch self {
            case .json: return "application/json"
            case .xml: return "text/xml; charset=utf-8"
            case .image: return "image/jpeg"
            case .form: return "application/x-www-form-urlencoded"
            case .defaultInMethod(let method):
                if method == .post || method == .put || method == .patch {
                    return "application/json"
                }
                return nil
            case .custom(let contentType):
                return contentType
            case .none:
                return nil
            }
        }
    }

    var baseURL: String = ""
    var path: String
    var httpMethod: HTTPMethod
    var contentType: ContentType?
    var body: Data?
    var parameters: [String: Any] = [:]
    var query: [String: Any] = [:]
    var headers: [String: String]

    var request: URLRequest {
        guard var url = URL(string: baseURL + path) else { fatalError("Not a valid URL") }
        url = url.appending(parameters: query)
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpMethod = self.httpMethod.rawValue
        if let contentType = contentType {
            request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
        switch self.httpMethod {
        case .post, .patch, .put:
            switch self.contentType {
            case .json:
                request = setJSONEncoding(for: request, with: parameters)
            case .defaultInMethod(let method):
                if method == .post || method == .put || method == .patch {
                    request = setJSONEncoding(for: request, with: parameters)
                }
            default:
                break
            }
        default:
            break
        }
        if let body = body {
            request.httpBody = body
        }
        return request
    }

    public init(path: String,
                contentType: ContentType? = nil,
                httpMethod: HTTPMethod,
                body: Data? = nil,
                parameters: [String: Any] = [:],
                headers: [String: String] = [:],
                query: [String: Any] = [:]) {
        self.path = path
        self.httpMethod = httpMethod
        self.parameters = parameters
        self.contentType = contentType == nil ? .defaultInMethod(self.httpMethod) : contentType
        self.headers = headers
        self.body = body
        self.query = query
    }

    // MARK: - set JSON encoding parameters
    func setJSONEncoding(for request: URLRequest, with parameters: [String: Any]) -> URLRequest {
        var request = request
        guard let httpBody = try? JSONSerialization.data(withJSONObject: parameters, options: []) else {
            return request
        }
        request.httpBody = httpBody
        return request
    }

    // MARK: - set URL encoding parameters
    func setURLEncoding(for url: URL) -> URLRequest{
        var components = URLComponents(string: url.absoluteString)!
        components.queryItems = self.query.map { (key, value) in
            if value is Int{
                return URLQueryItem(name: key, value: "\(value)")
            }else{
                return URLQueryItem(name: key, value: value as? String)
            }
        }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return URLRequest(url: components.url!)
    }

    // MARK: - add additional headers
    mutating func addExtra(headers: [String: String]) {
        headers.forEach { key, value in
            self.headers[key] = value
        }
    }

    // MARK: - get URL with BASE_URL
    mutating func addBaseURLIfNeeded(url: String) {
        if self.baseURL.isEmpty {
            self.baseURL = url
        }
    }

    // MARK: - create a Data for body with params and image
    public mutating func createBody(with parameters: [String: Any],
                                    and image: Data?,
                                    for imageKey: String,
                                    boundary: String) {
        var body = Data()

        for (key, value) in parameters {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)

            if let string = value as? String {
                print("value type String: \(value) for key: \(key)")
                body.append(contentsOf: string.utf8)
                body.append(contentsOf: "\r\n".utf8)
            } else if let number = value as? NSNumber {
                print("value type number: \(value) for key: \(key)")
                body.append(contentsOf: number.stringValue.utf8)
                body.append(contentsOf: "\r\n".utf8)
            } else {
                print("unsupported value type: \(value) for key: \(key)")
                assertionFailure("Unsupported value type")
            }
            body.append(contentsOf: "\r\n".utf8)
        }

        let filename = "\(boundary).jpg"
        let mimetype = "image/jpg"
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        if let imageData = image {
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(imageKey)\"; filename=\"\(filename)\"\r\n".utf8)
            body.append(contentsOf: "Content-Type: \(mimetype)\r\n\r\n".utf8)
            body.append(imageData)
            body.append(contentsOf: "\r\n".utf8)
            body.append(contentsOf: "--\(boundary)--\r\n".utf8)
        }
        self.body = body
    }

    // MARK: - append new information
    public mutating func appendContentTobody(with parameters: [String: Any]? = [:],
                                             and image: Data?,
                                             for imageKey: String?,
                                             boundary: String) {
        guard var body = self.body else {
            assertionFailure("The body has not been initialized. Use `createBody` first.")
            return
        }

        if let parameters = parameters {
            for (key, value) in parameters {
                body.append(contentsOf: "--\(boundary)\r\n".utf8)   
                body.append(contentsOf: "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)

                if let string = value as? String {
                    print("value type String: \(value) for key: \(key)")
                    body.append(contentsOf: string.utf8)
                    body.append(contentsOf: "\r\n".utf8)
                } else if let number = value as? NSNumber {
                    print("value type number: \(value) for key: \(key)")
                    body.append(contentsOf: number.stringValue.utf8)
                    body.append(contentsOf: "\r\n".utf8)
                } else {
                    print("unsupported value type: \(value) for key: \(key)")
                    assertionFailure("Unsupported value type")
                }
                body.append(contentsOf: "\r\n".utf8)
            }
        }

        if let image = image, let imageKey = imageKey {
            let filename = "\(UUID().uuidString).jpg"
            let mimetype = "image/jpg"
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(imageKey)\"; filename=\"\(filename)\"\r\n".utf8)
            body.append(contentsOf: "Content-Type: \(mimetype)\r\n\r\n".utf8)
            body.append(image)
            body.append(contentsOf: "\r\n".utf8)
        }

        // Ensure the body ends correctly with the boundary
        body.append(contentsOf: "--\(boundary)--\r\n".utf8)
        self.body = body
    }

    // MARK: - create a Data for body with params and image
    public mutating func createBody(with parameters: [String: Any],
                                    and images: [Data],
                                    for imageKey: String,
                                    boundary: String) {
        var body = Data()

        for (key, value) in parameters {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)

            if let string = value as? String {
                print("value type String: \(value) for key: \(key)")
                body.append(contentsOf: string.utf8)
                body.append(contentsOf: "\r\n".utf8)
            } else if let number = value as? NSNumber {
                print("value type number: \(value) for key: \(key)")
                body.append(contentsOf: number.stringValue.utf8)
                body.append(contentsOf: "\r\n".utf8)
            } else {
                print("unsupported value type: \(value) for key: \(key)")
                assertionFailure("Unsupported value type")
            }
            body.append(contentsOf: "\r\n".utf8)
        }


        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        for image in images {
            let filename = "\(UUID().uuidString).jpg"
            let mimetype = "image/jpg"
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(imageKey)\"; filename=\"\(filename)\"\r\n".utf8)
            body.append(contentsOf: "Content-Type: \(mimetype)\r\n\r\n".utf8)
            body.append(image)
            body.append(contentsOf: "\r\n".utf8)
            body.append(contentsOf: "--\(boundary)--\r\n".utf8)

        }
        self.body = body
    }
}

fileprivate extension Data {
    mutating func appendString(_ string: String) {
        let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true)
        append(data!)
    }
}

fileprivate extension URL {
    func appending(_ queryItem: String, value: Any?) -> URL? {
        guard var urlComponents = URLComponents(string: absoluteString) else { return absoluteURL }
        var queryItems: [URLQueryItem] = urlComponents.queryItems ?? []

        if let value = value {
            if let array = value as? [Any] {
                for element in array {
                    if let stringValue = self.convertToString(element) {
                        queryItems.append(URLQueryItem(name: queryItem, value: stringValue))
                    }
                }
            } else if let stringValue = self.convertToString(value) {
                queryItems.append(URLQueryItem(name: queryItem, value: stringValue))
            }
        }

        urlComponents.queryItems = queryItems
        return urlComponents.url
    }

    func appending(parameters: [String: Any]?) -> URL {
        guard let parameters = parameters else { return self }
        var appendingUrl = self

        let sortedParameters = parameters.sorted { $0.key < $1.key }
        for (key, value) in sortedParameters {
            if let url = appendingUrl.appending(key, value: value) {
                appendingUrl = url
            }
        }
        return appendingUrl
    }

    private func convertToString(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        } else if let doubleValue = value as? Double {
            return String(doubleValue)
        } else if let floatValue = value as? Float {
            return String(floatValue)
        } else if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else {
            return nil
        }
    }
}
