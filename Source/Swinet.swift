//
//  Swinet.swift
//  Swinet
//
//  Created by Quan on 10/18/21.
//

import Foundation
import Combine

struct Swinet {}

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
        case unknown
        case invalidUrl(_ url: String)
        case invalidBody(_ error: Error)
        case invalidJSONResponse(_ error: Error)
        case decodeFailure(_ error: Error)
        case responseFailure(_ error: Error, _ response: URLResponse?, _ data: Data?)

        var errorDescription: String {
            switch self {
            case .invalidUrl(let url):
                return "Invalid url: \(url)"
            case .decodeFailure(let error):
                return error.localizedDescription
            case .responseFailure(let error, _, _):
                return error.localizedDescription
            case .invalidBody(let error):
                return error.localizedDescription
            case .invalidJSONResponse(let error):
                return error.localizedDescription
            default:
                return localizedDescription
            }
        }

        var statusCode: Int? {
            switch self {
            case .responseFailure(_, let response, _):
                return (response as? HTTPURLResponse)?.statusCode
            default:
                return nil
            }
        }

        var data: Data? {
            switch self {
            case .responseFailure(_, _, let data):
                return data
            default:
                return nil
            }
        }
    }

    enum RequestBody {
        case json([String: Any]?)
        case data(Data)
        case formData(FormData)
        case graphQL(query: String, variables: [String: Any]?)

        func toData() throws -> Data? {
            switch self {
            case .json(let json):
                guard let json = json else { return nil }
                return try JSONSerialization.data(withJSONObject: json, options: [])
            case .data(let data):
                return data
            case .formData(let formData):
                return try formData.toData()
            case .graphQL(let query, let variables):
                return try dataFromGraphQL(query: query, variables: variables)
            }
        }

        private func dataFromGraphQL(query: String, variables: [String: Any]?) throws -> Data {
            var params = ["query": query]
            if let variables = variables,
               let variablesData = try? JSONSerialization.data(withJSONObject: variables, options: []),
               let variablesString = String(data: variablesData, encoding: .utf8) {
                params["variables"] = variablesString
            }

            let data = try JSONSerialization.data(withJSONObject: params, options: [])
            return data
        }
    }

    struct FormData {
        enum Value {
            case string(String)
            case file(url: URL)
        }

        private var values: [String: Value] = [:]

        init() {}

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

/// Request builder
extension Swinet {
    static func request(_ url: String,
                        method: HttpMethod = .get,
                        parameters: [String: String]? = nil,
                        body: [String: Any]? = nil,
                        headers: [String: String] = config.headers) -> Request {
        return request(url,
                       method: method,
                       parameters: parameters,
                       body: .json(body),
                       headers: headers)
    }

    static func formDataRequest(_ url: String,
                                method: HttpMethod = .get,
                                parameters: [String: String]? = nil,
                                formData: FormData,
                                headers: [String: String] = config.headers) -> Request {
        return request(url,
                       method: method,
                       parameters: parameters,
                       body: .formData(formData),
                       headers: headers)
    }

    static func graphQLRequest(_ url: String,
                                query: String,
                                variables: [String: Any]?,
                                headers: [String: String] = config.headers) -> Request {
        return request(url,
                       method: .post,
                       body: .graphQL(query: query, variables: variables),
                       headers: headers)
    }

    static func request(_ url: String,
                        method: HttpMethod = .get,
                        parameters: [String: String]? = nil,
                        body: RequestBody,
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
            return Request(request: nil, requestError: .invalidUrl(url))
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
        do {
            request.httpBody = try body.toData()
        } catch {
            return Request(request: request, requestError: .invalidBody(error))
        }

        return Request(request: request, requestError: nil)
    }
}

/// Response functions
extension Swinet {
    struct Request {
        let request: URLRequest?
        let requestError: NetworkError?

        init(request: URLRequest?, requestError: NetworkError?) {
            self.request = request
            self.requestError = requestError
        }

        /// Closure

        func responseData(on queue: DispatchQueue = DispatchQueue.main,
                          success: @escaping (_ result: Data) -> Void,
                          failure: @escaping (_ error: NetworkError) -> Void) {
            responseClosure(on: queue, type: Data.self, converter: { $0 }, success: success, failure: failure)
        }

        func responseData(on queue: DispatchQueue = DispatchQueue.main,
                          success: @escaping (_ result: Data) -> Void) {
            responseClosure(on: queue, type: Data.self, converter: { $0 }, success: success, failure: nil)
        }

        func responseString(on queue: DispatchQueue = DispatchQueue.main,
                            success: @escaping (_ result: String) -> Void,
                            failure: @escaping (_ error: NetworkError) -> Void) {
            responseClosure(on: queue, type: String.self, converter: {
                String(decoding: $0, as: UTF8.self)
            }, success: success, failure: failure)
        }

        func responseString(on queue: DispatchQueue = DispatchQueue.main,
                            success: @escaping (_ result: String) -> Void) {
            responseClosure(on: queue, type: String.self, converter: {
                String(decoding: $0, as: UTF8.self)
            }, success: success, failure: nil)
        }

        func responseJSON(on queue: DispatchQueue = DispatchQueue.main,
                          success: @escaping (_ result: Any) -> Void,
                          failure: @escaping (_ error: NetworkError) -> Void) {
            responseClosure(on: queue, type: Any.self, converter: {
                do {
                    return try JSONSerialization.jsonObject(with: $0, options: [])
                } catch {
                    throw NetworkError.invalidJSONResponse(error)
                }
            }, success: success, failure: failure)
        }

        func responseJSON(on queue: DispatchQueue = DispatchQueue.main,
                          success: @escaping (_ result: Any) -> Void) {
            responseClosure(on: queue, type: Any.self, converter: {
                do {
                    return try JSONSerialization.jsonObject(with: $0, options: [])
                } catch {
                    throw NetworkError.invalidJSONResponse(error)
                }
            }, success: success, failure: nil)
        }

        func responseDecodable<T: Decodable>(on queue: DispatchQueue = DispatchQueue.main,
                                             _ type: T.Type,
                                             success: @escaping (_ result: T) -> Void,
                                             failure: @escaping (_ error: NetworkError) -> Void) {
            responseClosure(on: queue, type: type, converter: {
                do {
                    return try JSONDecoder().decode(T.self, from: $0)
                } catch {
                    throw NetworkError.decodeFailure(error)
                }
            }, success: success, failure: failure)
        }

        func responseDecodable<T: Decodable>(on queue: DispatchQueue = DispatchQueue.main,
                                             _ type: T.Type,
                                             success: @escaping (_ result: T) -> Void) {
            responseClosure(on: queue, type: type, converter: {
                do {
                    return try JSONDecoder().decode(T.self, from: $0)
                } catch {
                    throw NetworkError.decodeFailure(error)
                }
            }, success: success, failure: nil)
        }

        func responseFile(on queue: DispatchQueue = DispatchQueue.main,
                          progress: ((_ progress: Double) -> Void)? = nil,
                          success: @escaping (_ url: URL) -> Void,
                          failure: @escaping (_ error: NetworkError) -> Void) {
            guard let request = request else {
                failure(requestError!)
                return
            }

            let downloader = Downloader()
            downloader.download(request,
                                success: success,
                                failure: failure,
                                progress: progress)
        }

        func responseFile(on queue: DispatchQueue = DispatchQueue.main,
                          progress: ((_ progress: Double) -> Void)? = nil,
                          success: @escaping (_ url: URL) -> Void) {
            guard let request = request else {
                return
            }

            let downloader = Downloader()
            downloader.download(request,
                                success: success,
                                failure: nil,
                                progress: progress)
        }

        func responseClosure<T>(on queue: DispatchQueue,
                                        type: T.Type,
                                        converter: @escaping (Data) throws -> T,
                                        success: @escaping (_ result: T) -> Void,
                                        failure: ((_ error: NetworkError) -> Void)?) {

            guard let request = request else {
                failure?(requestError!)
                return
            }

            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    queue.async {
                        failure?(.responseFailure(error, response, data))
                    }
                    return
                }
                guard let data = data else {
                    queue.async {
                        failure?(.responseFailure(error ?? NetworkError.unknown, response, data))
                    }
                    return
                }
                do {
                    let result = try converter(data)
                    queue.async {
                        success(result)
                    }
                } catch {
                    queue.async {
                        failure?(error as? NetworkError ?? .unknown)
                    }
                }
            }

            task.resume()
        }

        /// Combine

        func responseData(on queue: DispatchQueue = DispatchQueue.main) -> AnyPublisher<Data, Error> {
            responsePublisher(on: queue, type: Data.self, converter: { $0 })
        }

        func responseString(on queue: DispatchQueue = DispatchQueue.main) -> AnyPublisher<String, Error> {
            responsePublisher(on: queue, type: String.self) {
                String(decoding: $0, as: UTF8.self)
            }
        }

        func responseJSON(on queue: DispatchQueue = DispatchQueue.main) -> AnyPublisher<Any, Error> {
            responsePublisher(on: queue, type: Any.self) {
                do {
                    return try JSONSerialization.jsonObject(with: $0, options: [])
                } catch {
                    throw NetworkError.invalidJSONResponse(error)
                }
            }
        }

        func responseDecodable<T: Decodable>(on queue: DispatchQueue = DispatchQueue.main,
                                             _ type: T.Type) -> AnyPublisher<T, Error> {
            responsePublisher(on: queue, type: type) {
                try JSONDecoder().decode(T.self, from: $0)
            }
        }

        func responsePublisher<T>(on queue: DispatchQueue,
                                  type: T.Type,
                                  converter: @escaping (Data) throws -> T) -> AnyPublisher<T, Error>  {
            guard let request = request else {
                return Fail(error: requestError!)
                    .eraseToAnyPublisher()
            }

            return URLSession.shared
                .dataTaskPublisher(for: request)
                .tryMap { result in
                    return try converter(result.data)
                }
                .receive(on: queue)
                .eraseToAnyPublisher()
        }

        /// Swift concurrency

        @available(iOS 15.0.0, *)
        func responseData() async throws -> Data {
            guard let request = request else {
                throw(requestError!)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }

        @available(iOS 15.0.0, *)
        func responseString() async throws -> String {
            guard let request = request else {
                throw(requestError!)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(decoding: data, as: UTF8.self)
        }

        @available(iOS 15.0.0, *)
        func responseJSON() async throws -> Any {
            guard let request = request else {
                throw(requestError!)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            do {
                return try JSONSerialization.jsonObject(with: data, options: [])
            } catch {
                throw NetworkError.invalidJSONResponse(error)
            }
        }

        @available(iOS 15.0.0, *)
        func responseDecodable<T: Decodable>(_ type: T.Type) async throws -> T {
            guard let request = request else {
                throw(requestError!)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        }
    }
}

extension Swinet {
    class Downloader: NSObject, URLSessionDownloadDelegate {
        var progress: ((_ progress: Double) -> Void)? = nil

        func download(_ request: URLRequest,
                      success: @escaping (_ url: URL) -> Void,
                      failure: ((_ error: NetworkError) -> Void)?,
                      progress: ((_ progress: Double) -> Void)?) {
            self.progress = progress
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

            let task = session.downloadTask(with: request) { url, response, error in
                guard let url = url else {
                    failure?(.responseFailure(error ?? NetworkError.unknown, response, nil))
                    return
                }
                success(url)
            }
            task.resume()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let progress = (Double(totalBytesWritten)/Double(totalBytesExpectedToWrite))
            self.progress?(progress)
        }
    }
}
