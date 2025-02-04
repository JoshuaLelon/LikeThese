## Phase 1: "Hello World" & Firebase Setup ✅
### Checklist
[x] Create a new Xcode project for Swift (UIKit or SwiftUI).  
[x] Integrate Firebase SDK (Auth, Firestore, Storage) using Swift Package Manager.  
[x] Configure Firebase in AppDelegate (or SwiftUI App) to ensure connection.  
[x] Add a simple "Hello World" label or SwiftUI Text view to confirm the app runs.  

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