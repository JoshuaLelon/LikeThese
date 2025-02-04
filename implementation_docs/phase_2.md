## Phase 2: Set up Auth
### Checklist
[x] Enable Email/Password sign-in from the Firebase console and link the iOS app to the Firebase project.  
[x] Add the FirebaseAuth dependency (via Swift Package Manager).  
[x] Update AppDelegate (or SwiftUI App) to configure Firebase and handle authentication states.  
[x] Create a simple "Sign Up" and "Log In" flow.  
[x] Implement basic "Create Account," "Log In," and "Log Out" in code using FirebaseAuth.  
[x] Testing: Confirm a new user can be created, can log in, and can log out successfully.

### File Structure Tree once implemented
LikeThese/
├── LikeThese.xcodeproj
├── Podfile
├── LikeThese
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── ContentView.swift
│   ├── Services
│   │   └── AuthService.swift
│   ├── Views
│   │   ├── LoginView.swift (or LoginViewController.swift)
│   │   └── SignUpView.swift (or SignUpViewController.swift)
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- Pods/FirebaseAuth/Firebase/Auth/README.md  
  • Contains setup notes and examples for FirebaseAuth  
- Pods/Firebase/README.md  
  • Discusses advanced data fetch (Firestore) while integrating Auth  
- TikTok-Clone/Controllers/Discover/DiscoverVC.swift  
  • Demonstrates how the UI updates after certain Auth-based changes  
- TikTok-Clone/Controllers/Notifications/NotificationsVC.swift  
  • Another example of triggering view state changes after Auth events

#### `Pods/FirebaseAuth/README.md`
```markdown:Pods/FirebaseAuth/README.md
# Placeholder for FirebaseAuth README

This file would typically describe set up notes and examples for
configuring FirebaseAuth in your iOS project:
- Enabling Email/Password sign-in
- Adding OAuth providers
- Handling user sessions and tokens

See official docs for details:
https://firebase.google.com/docs/auth
```

#### `Pods/Firebase/README.md`
```markdown:Pods/Firebase/README.md
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

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift
import UIKit
import FirebaseFirestore

// Another example of triggering view state changes after Auth events.
// Adjust based on your actual Auth flow or user state.

function handleAuthStatus() {
    // Suppose we have a user session; we might refresh
    // the view to show personalized content.

    Firestore.firestore().collection("videos").getDocuments { snapshot, error in
        if let error = error {
            print("Error refreshing videos: \(error.localizedDescription)")
            return
        }
        let documents = snapshot?.documents ?? []
        // Update the UI to reflect the newly fetched videos
        print("Refreshed content for user: \(documents.count) videos found.")
    }
}
```

#### `TikTok-Clone/Controllers/Notifications/NotificationsVC.swift`
```swift:TikTok-Clone/Controllers/Notifications/NotificationsVC.swift
import UIKit
import FirebaseAuth
import FirebaseFirestore

// Example snippet showing how notifications (or status changes) might be handled.
// Tailor this to your own needs, especially if notifications depend on a valid user session.

function handleUserNotifications() {
    guard let currentUser = Auth.auth().currentUser else {
        print("No logged-in user. Notifications might be restricted or shown differently.")
        return
    }

    Firestore.firestore().collection("notifications")
        .whereField("userId", isEqualTo: currentUser.uid)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching notifications: \(error.localizedDescription)")
                return
            }
            let documents = snapshot?.documents ?? []
            print("User has \(documents.count) notifications to review.")
            // Update UI accordingly
        }
}
```


#### Example Swift Snippet for Auth (AuthService.swift)
```swift
import FirebaseAuth
import UIKit

func createAccount(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
  Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
    if let user = authResult?.user {
      completion(.success(user))
    } else if let error = error {
      completion(.failure(error))
    }
  }
}

func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
  Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
    if let user = authResult?.user {
      completion(.success(user))
    } else if let error = error {
      completion(.failure(error))
    }
  }
}

func signOut() throws {
  try Auth.auth().signOut()
}
```

