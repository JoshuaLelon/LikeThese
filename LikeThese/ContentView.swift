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
    @State private var isFirebaseConfigured = false
    
    var body: some View {
        VStack {
            Text("Hello World!")
                .font(.largeTitle)
            
            // Simple Firebase verification
            Text(isFirebaseConfigured ? "Firebase is configured!" : "Checking Firebase...")
                .foregroundColor(isFirebaseConfigured ? .green : .orange)
        }
        .onAppear {
            // Simple check if Firebase is configured
            isFirebaseConfigured = (Auth.auth() != nil)
        }
    }
}

#Preview {
    ContentView()
}
