## Phase 3: Data Model & Firestore Schema
### Checklist
[x] Create a Firestore database in the Firebase console.  
[x] Define collections for users, videos, and interactions based on your ER diagram.  
[ ] Add simple rules (e.g., read/write only if authenticated).  
[ ] Sketch out Swift data models (structs/classes) for user, video, and interaction using the ER Diagram below.

### File Structure Tree once implemented
LikeThese/
├── LikeThese.xcodeproj
├── LikeThese
│   ├── Models
│   │   ├── UserModel.swift
│   │   ├── VideoModel.swift
│   │   └── InteractionModel.swift
│   ├── Services
│   │   └── FirestoreService.swift
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- Pods/Firebase/README.md  
  • Reference for Firestore integration steps  
- TikTok-Clone/Controllers/Create Post/CreatePostVC.swift  
  • Shows how data (e.g., new posts) might be structured or posted to Firebase  
- TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift  
  • Demonstrates retrieving and displaying data in detail views

#### `Pods/Firebase/README.md`
````markdown:Pods/Firebase/README.md
# Firebase iOS Open Source Development [![Build Status](https://travis-ci.org/firebase/firebase-ios-sdk.svg?branch=master)](https://travis-ci.org/firebase/firebase-ios-sdk)

This repository contains a subset of the Firebase iOS SDK source. It currently
includes FirebaseCore, FirebaseABTesting, FirebaseAuth, FirebaseDatabase,
FirebaseFirestore, FirebaseFunctions, FirebaseInstanceID, FirebaseInAppMessaging,
FirebaseInAppMessagingDisplay, FirebaseMessaging, FirebaseRemoteConfig,
and FirebaseStorage.

The repository also includes GoogleUtilities source. The
[GoogleUtilities](GoogleUtilities/README.md) pod is a set of utilities used
by Firebase and other Google products.

Firebase is an app development platform with tools to help you build, grow, and
monetize your app. More information about Firebase can be found at
[https://firebase.google.com](https://firebase.google.com).

---

## Installation

See the three subsections below for details:

1. **Standard pod install**  
2. **Installing from GitHub**  
3. **Experimental Carthage** (iOS only)

### Standard pod install

Go to
[https://firebase.google.com/docs/ios/setup](https://firebase.google.com/docs/ios/setup).

### Installing from GitHub

For releases starting with 5.0.0, the source for each release is also deployed
to CocoaPods master and available via standard
[CocoaPods Podfile syntax](https://guides.cocoapods.org/syntax/podfile.html#pod).

These instructions can be used to access the Firebase repo at other branches,
tags, or commits.

**Accessing Firebase Source Snapshots**  
All official releases are tagged in this repo and available via CocoaPods.
To access a local source snapshot or an unreleased branch, use Podfile
directives like the following:
```
pod 'FirebaseCore', :git => 'https://github.com/firebase/firebase-ios-sdk.git', :branch => 'master'
pod 'FirebaseFirestore', :git => 'https://github.com/firebase/firebase-ios-sdk.git', :branch => 'master'
```

Or, if you've checked out the repo locally:
```
pod 'FirebaseCore', :path => '/path/to/firebase-ios-sdk'
pod 'FirebaseMessaging', :path => '/path/to/firebase-ios-sdk'
```

### Carthage (iOS only)

Instructions for the experimental Carthage distribution are at
[Carthage](Carthage.md).

### Rome

Instructions for installing binary frameworks via
[Rome](https://github.com/CocoaPods/Rome) are at [Rome](Rome.md).

---

## Development

To develop Firebase software in this repository, ensure that you have at least:
- Xcode 10.1 (or later)
- CocoaPods 1.7.2 (or later)
- [CocoaPods generate](https://github.com/square/cocoapods-generate)

For the pod you want to develop:
```
pod gen Firebase{name here}.podspec --local-sources=./ --auto-open
```
(You may need to run `pod repo update` first if the CocoaPods cache is out of date.)

Cloud Firestore has a self-contained Xcode project.
See [Firestore/README.md](Firestore/README.md).

### Adding a New Firebase Pod
See [AddNewPod.md](AddNewPod.md).

### Code Formatting
To ensure consistent formatting, run `./scripts/style.sh` before creating a PR.
You'll need `clang-format` and `swiftformat`.

### Running Unit Tests
Select a scheme and press Command-u to build a component and run its tests.

#### Viewing Code Coverage
After running `AllUnitTests_iOS`, execute:
```
xcov --workspace Firebase.xcworkspace --scheme AllUnitTests_iOS --output_directory xcov_output
```
Then `open xcov_output/index.html`.

### Running Sample Apps
You need valid `GoogleService-Info.plist` files for the sample apps. The Firebase
Xcode project has dummy files; replace them with real ones from
[the Firebase console](https://console.firebase.google.com/) for the sample apps
to work.

## Specific Component Instructions
### Firebase Auth
See the Auth Sample README in `Example/Auth/README.md` for instructions about
building and running the FirebaseAuth pod with sample apps and tests.

### Firebase Database
Make your database authentication rules [public] if you need to run Database
integration tests.

### Firebase Storage
Follow instructions in `FIRStorageIntegrationTests.m`
(Example/Storage/Tests/Integration/FIRStorageIntegrationTests.m) to run
Storage Integration tests.

#### Push Notifications
Push notifications can only be delivered to specially provisioned App IDs in the
developer portal. You must:
1. Change the sample app's bundle identifier to one you own in your Apple
   Developer account, and enable push notifications.
2. [Upload your APNs key/certificate to the Firebase console](https://firebase.google.com/docs/cloud-messaging/ios/certs).
3. Ensure your iOS device is registered in your Apple Developer portal.

#### iOS Simulator
Push notifications won't work on the iOS Simulator, only physical devices.

---

## Community Supported Efforts

We're grateful for the community interest and contributions to make Firebase
SDKs accessible on macOS and tvOS (community support only). For installation
on those platforms:
```
pod 'FirebaseCore'
pod 'FirebaseAuth'
pod 'FirebaseDatabase'
pod 'FirebaseFirestore'
pod 'FirebaseMessaging'
pod 'FirebaseRemoteConfig'
pod 'FirebaseStorage'
```
(plus any others you might need).

## Roadmap
See [Roadmap](ROADMAP.md) for planned directions.

## Contributing
See [Contributing](CONTRIBUTING.md).

## License
All code in this repository is under the
[Apache License, version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

Your use of Firebase is governed by the
[Terms of Service for Firebase Services](https://firebase.google.com/terms/).
```

#### `TikTok-Clone/Controllers/Create Post/CreatePostVC.swift`
`````swift:TikTok-Clone/Controllers/Create Post/CreatePostVC.swift
import UIKit
import FirebaseFirestore
import FirebaseStorage

// Example snippet that shows how a new post might be structured/created
// in Firestore. Adjust depending on your actual schema.

function uploadNewVideo(_ videoData: Data, metadata: [String: Any]) {
    let storageRef = Storage.storage().reference().child("videos/\(UUID().uuidString).mp4")
    storageRef.putData(videoData, metadata: nil) { (storageMetadata, error) in
        if let error = error {
            print("Error uploading video: \(error.localizedDescription)")
            return
        }
        storageRef.downloadURL { (url, error) in
            guard let downloadURL = url else {
                print("Failed to retrieve download URL: \(String(describing: error))")
                return
            }
            Firestore.firestore().collection("videos").addDocument(data: [
                "videoUrl": downloadURL.absoluteString,
                "metadata": metadata,
                "timestamp": Date()
            ]) { err in
                if let err = err {
                    print("Error storing video data: \(err.localizedDescription)")
                } else {
                    print("Video data stored successfully.")
                }
            }
        }
    }
}
`````

#### `TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift`
```swift:TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift
import UIKit
import FirebaseFirestore

// Example snippet showing how data might be retrieved and displayed.
// Adjust to your actual fields and UI.

function displayVideoDetails(_ videoDocumentID: String) {
    Firestore.firestore().collection("videos").document(videoDocumentID).getDocument { snapshot, error in
        if let error = error {
            print("Error fetching video details: \(error.localizedDescription)")
            return
        }
        guard let data = snapshot?.data() else {
            print("No data for this video.")
            return
        }
        // Do something with this data, e.g. update UI
        print("Fetched video data: \(data)")
    }
}
```


