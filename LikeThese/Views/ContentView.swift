import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var videoManager = VideoManager.shared
    
    var body: some View {
        ZStack {
            if authService.isAuthenticated {
                InspirationsGridView(videoManager: videoManager)
                    .overlay(alignment: .topTrailing) {
                        signOutButton
                    }
                    .onAppear {
                        print("🔑 Auth State Check - isAuthenticated: true, currentUser: \(String(describing: Auth.auth().currentUser?.uid))")
                    }
            } else {
                LoginView()
                    .onAppear {
                        print("🔑 Auth State Check - isAuthenticated: false, currentUser: \(String(describing: Auth.auth().currentUser?.uid))")
                    }
            }
        }
    }
    
    private var signOutButton: some View {
        Button(action: {
            print("🔑 Sign Out Attempt - Before signOut - currentUser: \(String(describing: Auth.auth().currentUser?.uid))")
            try? authService.signOut()
            print("🔑 Sign Out Attempt - After signOut - currentUser: \(String(describing: Auth.auth().currentUser?.uid))")
            videoManager.cleanup(context: .dismissal)
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .foregroundColor(.white)
            .padding(8)
            .background(Color.red.opacity(0.8))
            .cornerRadius(15)
            .shadow(color: .red.opacity(0.3), radius: 5)
        }
        .padding()
    }
}

#Preview {
    ContentView()
} 