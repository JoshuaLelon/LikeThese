import SwiftUI
import FirebaseCore

@main
struct LikeTheseApp: App {
    init() {
        // Configure Firebase for the current environment
        FirebaseConfig.shared.configure()
        
        #if DEBUG
        // Set to .local to use emulators during development
        // FirebaseConfig.shared.environment = .local
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
} 