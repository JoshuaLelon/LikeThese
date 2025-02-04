import SwiftUI
import FirebaseCore

@main
struct LikeTheseApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
} 