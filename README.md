# Swinet
Lightweight and Powerful HTTP Networking in Swift

## Motivation
When working with HTTP Networking, the first library developers think about could be [Alamofire](https://github.com/Alamofire/Alamofire). But `Alamofire` comes with a lot of files and some of its APIs aren't so much easier to use. `Swinet` is actually inspired a lot by Alamofire but so much more lightweight, easier to use with more straightforward and friendly APIs. Moreover `Swinet` supports closures-based, swift concurrency (async/await) and Combine which will be compatible with both old or modern iOS projects.

## Installation

### CocoaPods

[CocoaPods](https://cocoapods.org) is a dependency manager for Cocoa projects. For usage and installation instructions, visit their website. To integrate Alamofire into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
pod 'Swinet', '~> 1.0.0'
```

### Carthage

[Carthage](https://github.com/Carthage/Carthage) is a decentralized dependency manager that builds your dependencies and provides you with binary frameworks. To integrate Alamofire into your Xcode project using Carthage, specify it in your `Cartfile`:

```ogdl
github "https://github.com/dinhquan/Swinet" ~> 1.0.0
```

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. It is in early development, but Alamofire does support its use on supported platforms.

Once you have your Swift package set up, adding Alamofire as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/dinhquan/Swinet", .upToNextMajor(from: "1.0.0"))
]
```

## Usage

#### Simple Requests

```swift
Swinet.request("https://domain.com/api").responseJSON { json in
    print(json)
}
```

Error handling

```swift
struct User: Decodable {
    let username: String
    let email: String
}

Swinet.request("https://domain.com/login", method: .post, parameters: ["username": "test", "password": "test"])
    .responseDecodable(User.self, success: { user in
        print(user)
    }, failure: { error in
        print(error.errorDescription)
        print(error.statusCode as Any)
        print(error.data as Any)
    })
```

#### Combine
```swift
var bag = Set<AnyCancellable>()
Swinet.request("https://domain.com/user")
    .publishDecodable(User.self)
    .sink { error in
        print(error)
    } receiveValue: { model in
        print(model)
    }
    .store(in: &bag)
```

#### Swift Concurrency

```swift
@MainActor
func fetchUser() async {
    do {
        let user = try await Swinet.request("https://domain.com/user").responseDecodable(User.self)
        print(user)
    } catch {
        print(error)
    }
}
```

#### Form Data

```swift
let formData = Swinet.FormData([
    "name": .string("quan"),
    "avatar": .file(url: URL(string: "<file path>")!)
])
Swinet.formDataRequest("https://domain.com/upload", formData: formData)
    .responseJSON { json in
        print(json)
    }
```

#### Download File

```swift
Swinet.request("https://httpbin.org/file")
    .responseFile(progress: { progress in
        print(progress)
    }, success: { fileUrl in
        print(fileUrl)
    }, failure: { error in
        print(error)
    })
```

#### GraphQL

```swift
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
```
