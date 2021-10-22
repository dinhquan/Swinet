//
//  ContentViewModel.swift
//  Swinet
//
//  Created by Quan on 10/21/21.
//

import Foundation
import Combine

class SwinetExamples: ObservableObject {

    func simpleGet() {
        Swinet.request("https://httpbin.org/get")
            .responseJSON { json in
                print(json)
            }
    }

    func errorHandling() {
        Swinet.request("https://domain.com/login", parameters: ["username": "test", "password": "test"])
            .responseDecodable(User.self, success: { user in
                print(user)
            }, failure: { error in
                print(error.errorDescription)
                print(error.statusCode as Any)
                print(error.data as Any)
            })
    }

    func postWithJsonBody() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer 398u99fsh9sdhf9shf9sdhf9shdf"
        ]
        let body = [
            "username": "quan",
            "password": "quan123"
        ]
        Swinet.request("https://httpbin.org/post",
                       method: .post,
                       body: body,
                       headers: headers)
            .responseDecodable(User.self, success: { user in
                print(user)
            }, failure: { error in
                print(error)
            })
    }

    func uploadFileWithFormData() {
        let formData = Swinet.FormData([
            "name": .string("quan"),
            "avatar": .file(url: URL(string: "<file path>")!)
        ])
        Swinet.formDataRequest("https://httpbin.org/post", formData: formData)
            .responseJSON { json in
                print(json)
            }
    }

    func downloadFile() {
        Swinet.request("https://httpbin.org/file")
            .responseFile(progress: { progress in
                print(progress)
            }, success: { fileUrl in
                print(fileUrl)
            }, failure: { error in
                print(error)
            })
    }

    func graphQL() {
        let query = """
        query HeroNameAndFriends($episode: String!) {
          hero(episode: $episode) {
            name
            friends {
              name
            }
          }
        }
        """
        let variables = ["episode": "JEDI"]
        Swinet.graphQLRequest("https://httpbin.org/graphql", query: query, variables: variables)
            .responseDecodable(User.self, success: { model in
                print(model)
            }, failure: { error in
                print(error)
            })
    }

    func combine() {
        var bag = Set<AnyCancellable>()
        Swinet.request("https://httpbin.org/get")
            .publishDecodable(User.self)
            .sink { error in
                print(error)
            } receiveValue: { model in
                print(model)
            }
            .store(in: &bag)

    }

    @available(iOS 15.0.0, *)
    @MainActor
    func fetchUser() async {
        do {
            let user = try await Swinet.request("https://domain.com/user").responseDecodable(User.self)
            print(user)
        } catch {
            print(error)
        }
    }

    struct User: Decodable {
        let username: String
        let email: String
    }
}
