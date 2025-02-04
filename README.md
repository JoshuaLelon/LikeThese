# Implementation Checklist

## Phase 1: "Hello World" & Firebase Setup
### Checklist
[ ] Create a new Xcode project for Swift (UIKit or SwiftUI).  
[ ] Integrate Firebase SDK (Auth, Firestore, Storage) using CocoaPods or Swift Package Manager.  
[ ] Configure Firebase in AppDelegate (or SwiftUI App) to ensure connection.  
[ ] Add a simple "Hello World" label or SwiftUI Text view to confirm the app runs.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese.xcodeproj
├── Podfile
├── LikeThese
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   └── (other Swift/UI files)
├── README.md
└── (supporting files and folders, e.g. Pods)

### Files from another repository to use for inspiration:

- Pods/Firebase/CoreOnly/README.md  
  • Explains using CocoaPods for a basic Firebase setup  
- Pods/Firebase/README.md  
  • Details how to integrate core Firebase services into iOS projects  
- TikTok.xcodeproj/project.pbxproj  
  • Shows how to structure or group new features in Xcode

#### `Pods/Firebase/CoreOnly/README.md`
````markdown:Pods/Firebase/CoreOnly/README.md
# Firebase APIs for iOS

Simplify your iOS development, grow your user base, and monetize more
effectively with Firebase services.

Much more information can be found at [https://firebase.google.com](https://firebase.google.com).

## Install a Firebase SDK using CocoaPods

Firebase distributes several iOS specific APIs and SDKs via CocoaPods.
You can install the CocoaPods tool on macOS by running the following command
from the terminal:
```
sudo gem install cocoapods
```
More info in the [Getting Started guide](https://guides.cocoapods.org/using/getting-started.html#getting-started).

## Add a Firebase SDK to your iOS app

CocoaPods is used to install and manage dependencies in existing Xcode projects.

1.  Create an Xcode project, and save it to your local machine.
2.  Create a file named `Podfile` in your project directory. This file defines
    your project's dependencies, and is commonly referred to as a Podspec.
3.  Open `Podfile`, and add your dependencies. A simple Podspec is shown here:

    ```
    platform :ios, '8.0'
    pod 'Firebase'
    ```

4.  Save the file.

5.  Open a terminal and `cd` to the directory containing the Podfile.

    ```
    cd <path-to-project>/project/
    ```

6.  Run the `pod install` command. This will install the SDKs specified in the
    Podspec, along with any dependencies they may have.

    ```
    pod install
    ```

7.  Open your app's `.xcworkspace` file to launch Xcode. Use this file for all
    development on your app.

8.  You can also install other Firebase SDKs by adding subspecs in the
    Podfile. For example:
    ```
    pod 'Firebase/Analytics'
    pod 'Firebase/Auth'
    pod 'Firebase/Firestore'
    pod 'Firebase/Storage'
    ```
````

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
````

#### `TikTok.xcodeproj/project.pbxproj`
```plaintext:TikTok.xcodeproj/project.pbxproj
/* Begin PBXProject section */
	E9F7F2992505C1D000D2ED5E /* Project object */ = {
		isa = PBXProject;
		attributes = {
			LastSwiftUpdateCheck = 1160;
			LastUpgradeCheck = 1160;
			ORGANIZATIONNAME = "Osaretin Uyigue";
			TargetAttributes = {
				E9F7F2A02505C1D000D2ED5E = {
					CreatedOnToolsVersion = 11.6;
				};
			};
		};
		buildConfigurationList = E9F7F29C2505C1D000D2ED5E /* Build configuration list for PBXProject "TikTok" */;
		compatibilityVersion = "Xcode 9.3";
		developmentRegion = en;
		hasScannedForEncodings = 0;
		knownRegions = (
			en,
			Base,
		);
		mainGroup = E9F7F2982505C1D000D2ED5E;
		productRefGroup = E9F7F2A22505C1D000D2ED5E /* Products */;
		projectDirPath = "";
		projectRoot = "";
		targets = (
			E9F7F2A02505C1D000D2ED5E /* TikTok */,
		);
	};
/* End PBXProject section */
/* Some lines omitted for brevity */
```

## Phase 2: Set up Auth
### Checklist
[ ] Enable Email/Password sign-in from the Firebase console and link the iOS app to the Firebase project.  
[ ] Add the FirebaseAuth dependency (via CocoaPods or Swift Package Manager).  
[ ] Update AppDelegate (or SwiftUI App) to configure Firebase and handle authentication states.  
[ ] Create a simple "Sign Up" and "Log In" flow (e.g., two SwiftUI Views or UIKit ViewControllers).  
[ ] Implement basic "Create Account," "Log In," and "Log Out" in code using FirebaseAuth.  
[ ] Testing: Confirm a new user can be created, can log in, and can log out successfully.

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

## Phase 3: Data Model & Firestore Schema
### Checklist
[ ] Create a Firestore database in the Firebase console.  
[ ] Define collections for users, videos, and interactions based on your ER diagram.  
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

## Phase 4: Seeding the Database
### Checklist
[ ] Create a small script or function that writes sample user documents and video documents to Firestore.  
[ ] Test retrieval of sample data in the app.  
[ ] Confirm data seeds appear in the Firestore console.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Services
│   │   ├── FirestoreSeed.swift
│   │   └── FirestoreService.swift (extended)
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Create Post/CreatePostVC.swift  
  • Code for uploading data to Firebase (useful pattern for a seeding script)  
- TikTok-Clone/Controllers/Discover/DiscoverVC.swift  
  • Showcases how lists of content are fetched from Firebase and displayed  
- Pods/FirebaseAuth/README.md  
  • If your database-seeding depends on authenticated user roles or requires user context


#### `TikTok-Clone/Controllers/Create Post/CreatePostVC.swift`
```swift:TikTok-Clone/Controllers/Create Post/CreatePostVC.swift
// (Repeated or similar snippet from above; can be repurposed for seeding the database.)
function seedInitialVideos() {
    // Example usage: uploading multiple sample videos for the initial seed.
    // ...
}
```

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
import UIKit
import FirebaseFirestore

// Example snippet to fetch a list of "seeded" videos from Firestore and display them.

function loadSeededVideos() {
    Firestore.firestore().collection("videos").getDocuments { snapshot, error in
        if let error = error {
            print("Error fetching seeded videos: \(error.localizedDescription)")
            return
        }
        let documents = snapshot?.documents ?? []
        for doc in documents {
            print("Found seeded video with ID: \(doc.documentID) data: \(doc.data())")
        }
    }
}
```

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


## Phase 5: Implement Pause & Play (Single Video Playback)
### Checklist
[ ] Integrate a basic video player (e.g., AVPlayer).  
[ ] Add tap gesture on the video so it can pause/resume.  
[ ] Retrieve video from Firebase Storage.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlayerView.swift
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Create Post/CreatePostVC.swift  
  • Illustrates how AVPlayer might be configured (for short video clips)  
- TikTok-Clone/Controllers/Details/TikTokDetailsVC.swift  
  • Demonstrates continuous playback flow and possible pause/resume logic

#### `TikTok-Clone/Controllers/Create Post/CreatePostVC.swift`
```swift:TikTok-Clone/Controllers/Create Post/CreatePostVC.swift
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
```

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









## Phase 6: Video Replacement (Swipe Up)
### Checklist
[ ] When user swipes up, fetch a replacement video from Firestore.  
[ ] Update the UI to show the new video in place.  
[ ] Optionally record an interaction document in Firestore to track the skip event.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlaybackView.swift (extends swipe gestures)
│   ├── Services
│   │   └── FirestoreService.swift (add fetchReplacementVideo)
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Discover/DiscoverVC.swift or TikTok-Clone/Controllers/Sounds/SoundsVC.swift  
  • Show how vertical/horizontal swipe gestures can be implemented and trigger new data loads  
- TikTok-Clone/Controllers/Notifications/NotificationsVC.swift  
  • Useful for refreshing view data after an interaction (similar to replacing a video)

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
import UIKit
import FirebaseFirestore

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




## Phase 7: Autoplay
### Checklist
[ ] Track the end of the current video and automatically load the next recommended video from Firestore.  
[ ] Seamlessly replay or skip to next content upon video completion.  
[ ] Optionally store "autoplay" events in Firestore (for analytics).  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlaybackView.swift (handle onVideoEnd -> fetchNextVideo)
│   ├── Services
│   │   └── FirestoreService.swift (add fetchNextRecommendedVideo)
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:

#### `TikTok-Clone/Controllers/VideoPlayer/VideoPlaybackVC.swift`
```swift:TikTok-Clone/Controllers/VideoPlayer/VideoPlaybackVC.swift
import UIKit
import AVKit
import FirebaseFirestore

// Example snippet for automatically loading the next recommended video
// when the current video finishes. You could attach this logic to a
// completion observer on AVPlayer or AVPlayerItem.

function handleVideoPlayback(url: URL) {
    let playerItem = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: playerItem)
    let playerLayer = AVPlayerLayer(player: player)
    // Add playerLayer to the view's layer...
    player.play()

    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: playerItem,
        queue: .main
    ) { [weak self] _ in
        self?.fetchNextRecommendedVideo()
    }
}

function fetchNextRecommendedVideo() {
    Firestore.firestore().collection("videos")
        .order(by: "timestamp", descending: true)
        .limit(to: 1)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching next video: \(error.localizedDescription)")
                return
            }
            guard let document = snapshot?.documents.first,
                  let data = document.data()["videoUrl"] as? String,
                  let videoURL = URL(string: data) else {
                print("No more videos found.")
                return
            }
            print("Autoplaying next video: \(document.documentID)")
            // Play or load this next video
        }
}
```

#### `TikTok-Clone/Services/Analytics/PlaybackAnalytics.swift`
```swift:TikTok-Clone/Services/Analytics/PlaybackAnalytics.swift
import FirebaseFirestore
import FirebaseAuth
import Foundation

// Example snippet for storing autoplay events whenever
// a video completes and the next one automatically loads.

function logAutoplayEvent(currentVideoId: String, nextVideoId: String?) {
    guard let userId = Auth.auth().currentUser?.uid else {
        print("User not logged in. Skipping analytics logging.")
        return
    }
    var payload: [String: Any] = [
        "userId": userId,
        "currentVideoId": currentVideoId,
        "timestamp": Date()
    ]
    if let nextVideo = nextVideoId {
        payload["nextVideoId"] = nextVideo
    }
    Firestore.firestore().collection("autoplayEvents").addDocument(data: payload) { error in
        if let error = error {
            print("Error logging autoplay event: \(error.localizedDescription)")
        } else {
            print("Autoplay event logged successfully.")
        }
    }
}
```


## Phase 8: Previously Watched (Swipe Down)
### Checklist
[ ] Maintain a stack or queue that records the user's watch history.  
[ ] On swipe down, pop or shift the stack to reload the previously watched video.  
[ ] Display the previous video quickly from local cache or Firestore.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── VideoPlaybackView.swift (handle swipe down event)
│   ├── Services
│   │   └── HistoryManager.swift
│   └── (other Swift/UI files)
└── (remaining project files)

#### `TikTok-Clone/Services/Playback/PlaybackHistoryManager.swift`
```swift:TikTok-Clone/Services/Playback/PlaybackHistoryManager.swift
import Foundation
import FirebaseFirestore

// Example manager to track a user's watch history in a queue-like structure.
// You could store record IDs in Firestore or keep an in-memory queue first.

private var watchHistory: [String] = [] // Simplified; use a better data model.

func recordWatchedVideo(_ videoId: String) {
  watchHistory.append(videoId)
  // Optionally persist to Firestore if needed:
  // Firestore.firestore().collection("watchHistory").addDocument(data: [
  //   "videoId": videoId,
  //   "timestamp": Date()
  // ])
}

func getPreviousVideo() -> String? {
  guard watchHistory.count > 1 else { return nil }
  // Remove the last watched, then return the new last item
  _ = watchHistory.popLast()
  return watchHistory.last
}
```

#### `TikTok-Clone/Controllers/Playback/PlaybackViewController.swift`
```swift:TikTok-Clone/Controllers/Playback/PlaybackViewController.swift
import UIKit
import AVKit

// Example logic to handle "swipe down" for the previous video.
// Adjust or connect to your UI framework's gesture callbacks.

function setupSwipeDownGesture() {
  let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown(_:)))
  swipeDown.direction = .down
  view.addGestureRecognizer(swipeDown)
}

@objc
function handleSwipeDown(_ gesture: UISwipeGestureRecognizer) {
  guard let previousVideoId = getPreviousVideo() else {
    print("No previous video in history.")
    return
  }
  // Load previous video. For instance:
  // Firestore or local cache -> fetch metadata -> play video
  print("Loading previous video with ID: \(previousVideoId)")
}
```

## Phase 9: Inspirations Board
### Checklist
[ ] Implement a 2x2 grid view for recommended videos.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── InspirationsGridView.swift
│   └── (other Swift/UI files)
└── (remaining project files)

### Files from another repository to use for inspiration:
- TikTok-Clone/Controllers/Discover/DiscoverVC.swift  
  • Implementation details for a grid or collection-based UI  

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
import UIKit
import FirebaseFirestore

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

## Phase 10: Multiswipe
### Checklist
[ ] Support single-swipe to remove a single video.  
[ ] Support multi-swipe gestures to remove multiple videos at once.  
[ ] For each removal, call Firestore to fetch new recommended videos.  
[ ] Update the grid in real time.  

### File Structure Tree once implemented
LikeThese/
├── LikeThese
│   ├── Views
│   │   └── InspirationsGridView.swift (extend multi-swipe logic)
│   ├── Services
│   │   └── FirestoreService.swift (handle multiple fetch requests)
│   └── (other Swift/UI files)
└── (remaining project files)

#### `TikTok-Clone/Controllers/Discover/DiscoverVC.swift`
```swift:TikTok-Clone/Controllers/Discover/DiscoverVC.swift
import UIKit
import FirebaseFirestore

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

# User Stories
## Pause and Play:
"As a user, I want to pause and resume a playing video by tapping anywhere on it during playback."

## Video Replacement:
"As a user, I want the system to replace the video I'm watching when I swipe up."

## Autoplay:
"As a user, I want the system to populate a new video when the current one ends."

## Previously Watched:
"As a user, I want to be able to swipe down from the current video to revisit the previous video."

## Inspirations
"As a user, I want an Inspirations board—a dynamic 2x2 grid of videos that guide and refine my recommendations based on what I keep or swipe away. I want to switch between the current video and the board by either swiping right on the playing video or tapping on a video in the grid."

## Multiswipe:
"As a user, I want to replace one video at a time by swiping it up AND replace multiple videos at the same time by holding between two videos or in the center of the 2x2 grid and swiping up. I want the system to replace them with new videos based on the ones I've left on the grid."

# Flow Diagram
## Updated Flow Diagram
```
graph LR
    Start --> Decision{Sign Up or Log In?}
    Decision --> SignUp[Create Account]
    SignUp --> OpenApp[Open App]
    Decision --> LogIn[Log In]
    LogIn --> OpenApp

    OpenApp --> InspirationsBoard[View Inspirations Board]
    InspirationsBoard --> SelectVideo[Select Video to Play]
    SelectVideo --> PlayVideo[Watch Video]
    PlayVideo --> PauseResume[Pause/Resume Playback]
    PlayVideo --> SwipeUp[Swipe Up to Replace Video]
    PlayVideo --> AutoplayNext[Autoplay Next Video]
    PlayVideo --> SwipeDown[Swipe Down to Previous Video]
    PlayVideo --> BackToGrid[Swipe Right to Return to Inspirations Board]
    BackToGrid --> InspirationsBoard
    SwipeUp --> FetchNewVideo[Fetch Replacement Video]
    FetchNewVideo --> UpdateGrid[Update Grid with New Video]

    InspirationsBoard --> Multiswipe[Multiswipe Action]
    Multiswipe --> MultiswipeIndividual[Swipe Individual Video]
    Multiswipe --> MultiswipeLeft[Swipe Left Videos]
    Multiswipe --> MultiswipeRight[Swipe Right Videos]
    Multiswipe --> MultiswipeTop[Swipe Top Videos]
    Multiswipe --> MultiswipeBottom[Swipe Bottom Videos]
    Multiswipe --> MultiswipeAll[Swipe All Videos]

    MultiswipeIndividual --> FetchNewVideo
    MultiswipeLeft --> FetchLeftVideos[Fetch New Left Videos]
    MultiswipeRight --> FetchRightVideos[Fetch New Right Videos]
    MultiswipeTop --> FetchTopVideos[Fetch New Top Videos]
    MultiswipeBottom --> FetchBottomVideos[Fetch New Bottom Videos]
    MultiswipeAll --> FetchMultipleNewVideos[Fetch All New Videos]

    FetchLeftVideos --> UpdateGrid
    FetchRightVideos --> UpdateGrid
    FetchTopVideos --> UpdateGrid
    FetchBottomVideos --> UpdateGrid
    FetchMultipleNewVideos --> UpdateGrid

    UpdateGrid --> Logout[Log Out]
    Logout --> End
```

## Updated Sequence Diagram
```
sequenceDiagram
    participant User
    participant App
    participant FirebaseAuth
    participant Firestore
    participant Storage

    User->>App: Launch app
    App->>User: Show "Sign Up" or "Log In" screen

    alt Create Account
        User->>App: Sign Up
        App->>FirebaseAuth: Submit user signup credentials
        FirebaseAuth-->>App: Return session token
        App->>User: Account created and session active
    end

    alt Log In
        User->>App: Log In
        App->>FirebaseAuth: Submit user login credentials
        FirebaseAuth-->>App: Return session token
        App->>User: Session active (successful login)
    end

    User->>App: View Inspirations Board
    App->>Firestore: Fetch Inspirations grid videos
    Firestore-->>App: Return video recommendations

    User->>App: Tap video to play
    App->>Storage: Stream video from Firebase Storage
    User->>App: Tap to pause/play
    User->>App: Swipe up to replace video
    App->>Firestore: Request new video recommendation
    Firestore-->>App: Return new video
    App->>User: Display new video in grid
    User->>App: Swipe down to revisit previous video
    App->>Firestore: Fetch previous video
    Firestore-->>App: Return previous video
    App->>User: Display previous video
    User->>App: Swipe right to return to Inspirations board
    App->>User: Display Inspirations grid

    User->>App: Multiswipe action
    App->>Firestore: Fetch multiple new recommendations
    Firestore-->>App: Return multiple new videos
    App->>User: Update grid with new videos

    User->>App: Log Out
    App->>FirebaseAuth: End session token
    FirebaseAuth-->>App: Confirm logout
    App->>User: Return to launch or sign-in screen
```

# ER Diagram
```
erDiagram
    USER {
        string userId
        string name
        string email
    }

    VIDEO {
        string videoId
        string videoFilePath "Firebase Storage path for video"
        string thumbnailFilePath "Firebase Storage path for thumbnail image"
    }

    INTERACTION {
        string interactionId
        string userId
        datetime timestamp
    }

    %% Parent for video interactions
    VIDEO_INTERACTION {
        string videoInteractionId
        string sourceVideoId
        string destinationVideoId
        string interactionType "rewind or skip"
    }

    %% Subtypes of swap interactions
    SINGLE_SWAP_INTERACTION {
        string singleSwapInteractionId
        string sourceVideoId
        string destinationVideoId
        string position "topLeft, bottomLeft, topRight, bottomRight"
    }

    DOUBLE_SWAP_INTERACTION {
        string doubleSwapInteractionId
        string sourceVideoId1
        string destinationVideoId1
        string sourceVideoId2
        string destinationVideoId2
        string swapType "topTwo, bottomTwo, leftTwo, rightTwo"
    }

    QUADRUPLE_SWAP_INTERACTION {
        string quadrupleSwapInteractionId
        string sourceVideoId1
        string destinationVideoId1
        string sourceVideoId2
        string destinationVideoId2
        string sourceVideoId3
        string destinationVideoId3
        string sourceVideoId4
        string destinationVideoId4
    }

    %% Relationships
    USER ||--o{ INTERACTION : "records"
    INTERACTION ||--o{ VIDEO_INTERACTION : "specializes"
    INTERACTION ||--o{ SINGLE_SWAP_INTERACTION : "specializes"
    INTERACTION ||--o{ DOUBLE_SWAP_INTERACTION : "specializes"
    INTERACTION ||--o{ QUADRUPLE_SWAP_INTERACTION : "specializes"
    VIDEO ||--o{ VIDEO_INTERACTION : "involves"
    VIDEO ||--o{ SINGLE_SWAP_INTERACTION : "replaces"
    VIDEO ||--o{ DOUBLE_SWAP_INTERACTION : "replaces"
    VIDEO ||--o{ QUADRUPLE_SWAP_INTERACTION : "replaces"
```

# Summary of Project
This project is a TikTok-like application built in Swift, with Firebase (Auth, Firestore, and Storage) powering user login, data, and video streaming. Unlike traditional video apps, it emphasizes user control and assisted learning through a 2x2 "Inspirations" grid. Users both shape and refine the recommendation system by swiping individual or multiple videos, curating a personalized algorithm bubble. The above phases guide you from a simple Firebase "Hello World" to a fully featured learning-centric TikTok clone that supports pause/resume, autoplay, video replacement, swiping down for previously watched content, and a dynamic grid for content discovery and multi-swipe gestures.

# Longer Summary of Project
Imagine TikTok, but redesigned from the ground up for **learners and curious minds** who crave more control over their content recommendations. This app is built around a dynamic and interactive **Inspirations grid**, designed to give users **direct feedback and control over the algorithm** that shapes their video discovery journey. Whether they're watching documentaries, tutorials, or thought-provoking discussions, these users have a **wide variety of interests** and **want to consciously curate their algorithm bubble**.

This app doesn't just recommend videos based on vague notions of what users like—it gives them **the power to actively shape** what content is shown through intuitive gestures and interactions.

## **The Inspirations Grid**

The app introduces a **2x2 grid interface** that serves as both a **recommendation engine** and a **discovery tool**. Each video on the grid represents a potential learning opportunity, and the user can **consciously train the algorithm** by interacting with these videos:

- **Swipe Control:** Users can hold and swipe away individual videos they're not interested in. When a video is removed, it's replaced by a **new recommendation** that is **less like what they disliked** and **more like what they left on the grid**.
- **Multiswipe Gestures:** Users can hold between two videos or in the center of the grid to **replace multiple videos at once**. This feature is ideal for quickly resetting or refining the grid when users aren't satisfied with the current suggestions.
- **Algorithm with User-Centric Control:** Unlike traditional platforms where the algorithm dictates the content, this app ensures that the **user drives the recommendation process**. The system will have a **vague sense of general preferences**, but users can refine and override these suggestions with ease. The result is an experience that balances **algorithmic convenience** with **human oversight**.

The **Inspirations grid** helps users **create their own algorithm bubble**—one that reflects their eclectic interests without limiting them to narrow content silos.

---

## **A Seamless History**

The app is designed to allow users to **seamlessly revisit previous videos** through an intuitive swipe-based navigation system:

- **Swipe Up:** Loads the next video recommendation, continuing the discovery process without interruption.
- **Swipe Down:** Brings back the previously watched video, allowing users to quickly review content they found valuable or missed.

This feature ensures that users can **rewind their learning journey** with ease, eliminating the frustration of losing track of interesting videos. Whether they want to go back to rewatch part of a tutorial or rediscover an engaging documentary, the app makes it easy to **explore and revisit their personalized video history**.

---

## **Focused Video Playback**

Once a user taps on a video, they enter **full playback mode**, where they can immerse themselves in the content. During playback, the user can:

- **Pause/Resume:** Tap anywhere on the screen to pause or resume the video.
- **Swipe Up:** Discard the video and return to the grid, with a new video immediately replacing it based on their refined preferences.
- **Autoplay:** If the user watches a video to completion, the system automatically queues the next video, ensuring a **continuous learning experience** tailored to their current session.

This simple yet powerful flow allows users to stay focused on **content they find meaningful** without unnecessary distractions.

---

## **Niche Market and Value Proposition**

This app is designed for **learners**—people who watch videos to **explore a variety of topics, deepen their understanding, and satisfy their curiosity**. Whether they're interested in math, history, technology, art, or philosophy, these users are always on the lookout for **engaging, high-quality content** that aligns with their interests.

The **value proposition** of this app lies in its **balance between algorithm-driven discovery and user control**:

- **Tailored content:** Users benefit from a recommendation engine that adapts to their preferences while still offering enough diversity to discover new ideas.
- **Convenience of swiping:** Users can navigate and curate their experience quickly through simple swipe gestures.
- **Control over the algorithm:** Unlike traditional platforms that heavily rely on opaque recommendation systems, this app gives users the **power to decide what the algorithm learns**.

This combination makes the app perfect for **Renaissance individuals**—people who enjoy learning across a wide range of disciplines and don't want to be confined to one type of content.

---

## **Example Use Case**

**Alex**, a history enthusiast who also loves learning about science and art, opens the app to explore new content during their free time.

- **Step 1:** On the Inspirations grid, Alex sees four videos: one about ancient Egypt, one on quantum mechanics, one about impressionist art, and one on space exploration. They immediately swipe away the video on quantum mechanics because they've already seen similar content today.
- **Step 2:** The app replaces the swiped video with a new suggestion—a video about the construction of medieval cathedrals, which Alex finds intriguing.
- **Step 3:** They tap on the cathedral video to start watching. Halfway through, they pause to take notes and then resume playback.
- **Step 4:** After watching the video to the end, the app automatically queues up another video on gothic architecture, continuing the flow of discovery.
- **Step 5:** Later, Alex swipes down to revisit the video on space exploration and finish watching it.

By the end of the session, the app has adjusted its recommendations based on Alex's interactions, ensuring that future content aligns with their learning interests.

---

## **Why This App Matters**

In a world dominated by platforms that rely on **black-box algorithms** to dictate what users see, this app **puts control back into the hands of the learner**. It acknowledges that while algorithms can be useful, they should **serve the user**—not the other way around.

The app matters because:

- It respects the diverse and evolving nature of curiosity by offering **a wide range of content that users can consciously shape**.
- It eliminates the frustration of being trapped in an algorithm-driven content loop by allowing users to **break free and redefine their recommendations** at any time.
- It encourages **active learning** by making it easy to revisit previous content, refine future suggestions, and maintain focus on topics that matter.

For **lifelong learners and knowledge seekers**, this app is more than a recommendation engine—it's a **personalized learning companion** designed to grow alongside them.

# Tech Stack
Frontend
Language: Swift
Framework: SwiftUI (or UIKit as needed)

Backend Services (via Firebase)
The backend is designed to handle user authentication, data storage, video recommendations, and serverless logic using Firebase. Firebase's serverless nature simplifies infrastructure management while allowing for scalability and rapid development.

Authentication & User Management
Decision: Firebase Auth
Supports email/password authentication.

Database Management
Decision: Firestore (NoSQL, real-time updates for user progress and interactions)
Purpose: Stores user interactions, video metadata, watch history, and swiped-away content to inform personalized recommendations.
Data Model: The database will store session-specific information (videos watched, videos swiped away) as well as long-term preference data.

Media Storage & Video Processing
Decision: Firebase Cloud Storage (for video files and thumbnails)
Purpose: Provides reliable media storage and access for video playback.

Backend Logic
Decision: Firebase Cloud Functions (serverless backend)
Purpose: Handles video processing, recommendation logic, AI-driven features, and integration with external APIs.
Description: Manages compute-intensive tasks like processing video interactions or dynamically updating the Inspirations grid based on swiping patterns.
Provides flexibility to integrate future AI models or external APIs without architectural changes.

## Development Requirements

- Python 3.9 or higher (required for xcode-build-server)
- Xcode and related development tools