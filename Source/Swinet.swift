//
//  Swinet.swift
//  Swinet
//
//  Created by Quan on 10/18/21.
//

import Foundation
import Combine

struct Swinet {}

/// Internal types
extension Swinet {
    enum HttpMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case connect = "CONNECT"
        case head = "HEAD"
        case options = "OPTIONS"
        case patch = "PATCH"
        case trace = "TRACE"
    }

    enum NetworkError: Error {
        case invalidUrl
        case invalidBody
        case invalidJSONResponse
        case decodeFailure
    }

    enum RequestBody {
        case json([String: Any])
        case data(Data)
        case formData(FormData)

        func toData() throws -> Data? {
            switch self {
            case .json(let json):
                return try JSONSerialization.data(withJSONObject: json, options: [])
            case .data(let data):
                return data
            case .formData(let formData):
                return try formData.toData()
            }
        }
    }

    struct FormData {
        enum Value {
            case string(String)
            case file(url: URL)
        }

        private var values: [String: Value] = [:]

        init(_ values: [String: Value]) {
            self.values = values
        }

        mutating func append(key: String, value: String) {
            values[key] = .string(value)
        }

        mutating func append(key: String, fileUrl: URL) {
            values[key] = .file(url: fileUrl)
        }

        func toData() throws -> Data? {
            let boundary = "Boundary-\(UUID().uuidString)"
            var body = ""
            for (key, value) in values {
                body += "--\(boundary)\r\n"
                body += "Content-Disposition:form-data; name=\"\(key)\""
                switch value {
                case .string(let string):
                    body += "\r\n\r\n\(string)\r\n"
                case .file(let url):
                    let fileData = try Data(contentsOf: url)
                    let fileContent = String(data: fileData, encoding: .utf8) ?? ""
                    let fileName = url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent
                    body += "; filename=\"\(fileName)\"\r\n"
                      + "Content-Type: \"content-type header\"\r\n\r\n\(fileContent)\r\n"
                }
            }
            body += "--\(boundary)--\r\n";

            return body.data(using: .utf8)
        }
    }
}

/// Config
extension Swinet {
    struct Config {
        var timeOutInterval: Double
        var headers: [String: String]
    }

    static var config = Config(
        timeOutInterval: 60.0,
        headers: ["Content-Type": "application/json"]
    )
}

/// Request
extension Swinet {
    static func request(_ url: String,
                        method: HttpMethod = .get,
                        parameters: [String: String]? = nil,
                        body: [String: Any]? = nil,
                        headers: [String: String] = config.headers) -> Request {
        var requestBody: RequestBody? = nil
        if let body = body {
            requestBody = .json(body)
        }
        return request(url,
                       method: method,
                       parameters: parameters,
                       body: requestBody,
                       headers: headers)
    }

    static func request(_ url: String,
                        method: HttpMethod = .get,
                        parameters: [String: String]? = nil,
                        body: RequestBody? = nil,
                        headers: [String: String] = config.headers) -> Request {
        /// Build url with params
        var urlString = url

        if let params = parameters {
            var components = URLComponents()
            components.queryItems = params.map {
                 URLQueryItem(name: $0, value: $1)
            }
            urlString = "\(urlString)\(components.string ?? "")"
        }

        guard let fullUrl = URL(string: urlString) else {
            return Request(request: nil, requestError: .invalidUrl)
        }

        /// Create URLRequest
        var request = URLRequest(url: fullUrl)
        request.httpMethod = method.rawValue
        request.timeoutInterval = config.timeOutInterval

        /// Build headers
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        /// Build body
        if let body = body {
            do {
                request.httpBody = try body.toData()
            } catch {
                return Request(request: request, requestError: .invalidBody)
            }
        }

        return Request(request: request, requestError: nil)
    }
}

/// Response
extension Swinet {
    struct Request {
        let request: URLRequest?
        let requestError: NetworkError?

        init(request: URLRequest?, requestError: NetworkError?) {
            self.request = request
            self.requestError = requestError
        }

        /// Public methods

        func responseData(success: @escaping (_ result: Data) -> Void,
                          failure: @escaping (_ error: Error) -> Void) {
            responseClosure(type: Data.self, converter: { $0 }, success: success, failure: failure)
        }

        func responseString(success: @escaping (_ result: String) -> Void,
                            failure: @escaping (_ error: Error) -> Void) {
            responseClosure(type: String.self, converter: {
                String(decoding: $0, as: UTF8.self)
            }, success: success, failure: failure)
        }

        func responseJSON(success: @escaping (_ result: [String: Any]) -> Void,
                          failure: @escaping (_ error: Error) -> Void) {
            responseClosure(type: [String: Any].self, converter: {
                guard let json = try JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any] else {
                    throw NetworkError.invalidJSONResponse
                }
                return json
            }, success: success, failure: failure)
        }

        func responseDecodable<T: Decodable>(_ type: T.Type,
                                             success: @escaping (_ result: T) -> Void,
                                             failure: @escaping (_ error: Error) -> Void) {
            responseClosure(type: type, converter: {
                try JSONDecoder().decode(T.self, from: $0)
            }, success: success, failure: failure)
        }

        func responseData() -> AnyPublisher<Data, Error> {
            responsePublisher(type: Data.self, converter: { $0 })
        }

        func responseString() -> AnyPublisher<String, Error> {
            responsePublisher(type: String.self) {
                String(decoding: $0, as: UTF8.self)
            }
        }

        func responseJSON() -> AnyPublisher<[String: Any], Error> {
            responsePublisher(type: [String: Any].self) {
                guard let json = try JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any] else {
                    throw NetworkError.invalidJSONResponse
                }
                return json
            }
        }

        func responseDecodable<T: Decodable>(_ type: T.Type) -> AnyPublisher<T, Error> {
            responsePublisher(type: type) {
                try JSONDecoder().decode(T.self, from: $0)
            }
        }

        /// Private methods

        private func responseClosure<T>(type: T.Type,
                                        converter: @escaping (Data) throws -> T,
                                        success: @escaping (_ result: T) -> Void,
                                        failure: @escaping (_ error: Error) -> Void) {

            guard let request = request else {
                failure(requestError!)
                return
            }

            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard let data = data else {
                    failure(error!)
                    return
                }

                do {
                    let result = try converter(data)
                    success(result)
                } catch {
                    failure(error)
                }
            }

            task.resume()
        }

        private func responsePublisher<T>(type: T.Type, converter: @escaping (Data) throws -> T) -> AnyPublisher<T, Error>  {
            guard let request = request else {
                return Fail(error: requestError!)
                    .eraseToAnyPublisher()
            }

            return URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { result in
                    return try converter(result.data)
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }

        /*
        func responseDecodable<T: Decodable>(_ type: T.Type) async throws -> T {
            guard let request = request else {
                throw(requestError!)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        }
         */
    }
}

/// Cache
extension Swinet {
    struct Cacher {
        static func cache(url: String, data: Data) {
            let string = String(data: data, encoding: .utf8)
            UserDefaults.standard.set(string, forKey: url)
        }

        static func get(url: String) -> Data? {
            guard let string = UserDefaults.standard.string(forKey: url) else { return nil }
            guard let data = string.data(using: .utf8) else { return nil }
            return data
        }
    }
}
