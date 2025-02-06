import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authService = AuthService()
    
    var body: some View {
        ZStack {
            if authService.isAuthenticated {
                InspirationsGridView()
                    .overlay(alignment: .topTrailing) {
                        signOutButton
                    }
            } else {
                LoginView()
            }
        }
    }
    
    private var signOutButton: some View {
        Button(action: {
            try? authService.signOut()
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