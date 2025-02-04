import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @StateObject private var authService = AuthService()
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)]),
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                // Title area
                VStack(spacing: 10) {
                    Text("Create Account")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Sign up to get started")
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
                            .textContentType(.newPassword)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(15)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
                    
                    // Confirm Password field
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.gray)
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(15)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
                }
                .padding(.horizontal)
                
                // Password requirements
                if !password.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        PasswordRequirementRow(text: "At least 6 characters", isMet: password.count >= 6)
                        PasswordRequirementRow(text: "Passwords match", isMet: !confirmPassword.isEmpty && password == confirmPassword)
                    }
                    .padding(.horizontal)
                }
                
                // Sign up button
                Button(action: signUp) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.blue)
                        
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Sign Up")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(height: 50)
                .padding(.horizontal)
                .disabled(isLoading || !isValidForm)
                .opacity(isValidForm ? 1 : 0.6)
                
                // Sign in link
                Button(action: { dismiss() }) {
                    Text("Already have an account? ")
                        .foregroundColor(.secondary) +
                    Text("Sign In")
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
    
    private var isValidForm: Bool {
        !email.isEmpty && 
        !password.isEmpty && 
        !confirmPassword.isEmpty && 
        password == confirmPassword &&
        password.count >= 6 &&
        email.contains("@")
    }
    
    private func signUp() {
        guard isValidForm else { return }
        isLoading = true
        
        Task {
            do {
                try await authService.signUp(email: email, password: password)
                dismiss()
            } catch let error as AuthError {
                switch error {
                case .signUpFailed(let message):
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

struct PasswordRequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SignUpView()
} 