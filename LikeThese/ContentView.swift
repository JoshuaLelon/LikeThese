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
                VideoPlayerView()
                    .overlay(alignment: .topTrailing) {
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
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
}
