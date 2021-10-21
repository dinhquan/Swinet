//
//  ContentViewModel.swift
//  Swinet
//
//  Created by Quan on 10/21/21.
//

import Foundation

struct ResponseModel: Decodable {

}

class SwinetExamples: ObservableObject {

    func simpleGet() {
        Swinet.request("https://httpbin.org/get")
            .responseJSON { json in
                print(json)
            }
    }

    func errorHandling() {
        Swinet.request("https://httpbin.org/get")
            .responseDecodable(ResponseModel.self, success: { model in
                print(model)
            }, failure: { error in
                print(error.errorDescription)
                print("\(error.statusCode)")
                print("\(error.data)")
            })
    }


}
