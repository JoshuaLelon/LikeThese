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