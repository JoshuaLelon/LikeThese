//
//  ContentView.swift
//  LikeThese
//
//  Created by Joshua Mitchell on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authService = AuthService()
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                // Main app content
                ZStack {
                    // Background gradient
                    LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2)]),
                                 startPoint: .topLeading,
                                 endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 30) {
                        // Welcome card
                        VStack(spacing: 15) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("Welcome Back!")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text(authService.currentUser?.email ?? "")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.1), radius: 10)
                        
                        // Sign out button
                        Button(action: {
                            try? authService.signOut()
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 200)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(15)
                            .shadow(color: .red.opacity(0.3), radius: 5)
                        }
                    }
                    .padding()
                }
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
}
