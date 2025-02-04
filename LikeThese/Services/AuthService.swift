import FirebaseAuth
import FirebaseFirestore

public enum AuthError: Error {
    case signUpFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
}

@MainActor
public class AuthService: ObservableObject {
    @Published public var currentUser: User?
    @Published public var isAuthenticated = false
    private var handle: AuthStateDidChangeListenerHandle?
    
    public init() {
        currentUser = Auth.auth().currentUser
        isAuthenticated = currentUser != nil
        
        // Store the handle so we can remove the listener later if needed
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isAuthenticated = user != nil
        }
    }
    
    deinit {
        // Remove the listener when the service is deallocated
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    public func signUp(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = result.user
            isAuthenticated = true
            
            // Create user document in Firestore
            try await Firestore.firestore().collection("users").document(result.user.uid).setData([
                "email": email,
                "createdAt": Date()
            ])
        } catch {
            throw AuthError.signUpFailed(error.localizedDescription)
        }
    }
    
    public func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = result.user
            isAuthenticated = true
        } catch {
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }
    
    public func signOut() throws {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            throw AuthError.signOutFailed(error.localizedDescription)
        }
    }
} 