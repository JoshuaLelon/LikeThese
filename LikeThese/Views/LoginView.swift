import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @StateObject private var authService = AuthService()
    @State private var email = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)]),
                             startPoint: .topLeading,
                             endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                VStack(spacing: 25) {
                    // Logo/Title area
                    VStack(spacing: 10) {
                        Text("Welcome Back!")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Sign in to continue")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 50)
                    
                    // Input fields
                    VStack(spacing: 20) {
                        // Email field
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.gray)
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(15)
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
                        
                        // Password field
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(15)
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    
                    // Sign in button
                    Button(action: signIn) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.blue)
                            
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(height: 50)
                    .padding(.horizontal)
                    .disabled(isLoading || !isValidForm)
                    .opacity(isValidForm ? 1 : 0.6)
                    
                    // Sign up link
                    NavigationLink(destination: SignUpView()) {
                        Text("Don't have an account? ")
                            .foregroundColor(.secondary) +
                        Text("Sign Up")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .padding(.top)
                }
                .padding()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isValidForm: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }
    
    private func signIn() {
        isLoading = true
        
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch let error as AuthError {
                switch error {
                case .signInFailed(let message):
                    errorMessage = message
                    showError = true
                default:
                    errorMessage = "An unknown error occurred"
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
} 