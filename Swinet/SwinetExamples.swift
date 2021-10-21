//
//  ContentViewModel.swift
//  Swinet
//
//  Created by Quan on 10/21/21.
//

import Foundation

class SwinetExamples: ObservableObject {

    func get() {
        Swinet.request("https://httpbin.org/get")
            .responseData { data in
                print(data)
            }
    }
}
