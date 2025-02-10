import FirebaseCore
import FirebaseFunctions

enum FirebaseEnvironment: String {
    case production
    case development
    case local
    
    var useEmulator: Bool {
        self == .local
    }
    
    var emulatorHost: String {
        "localhost"
    }
    
    var emulatorPort: Int {
        5001
    }
    
    static var current: FirebaseEnvironment {
        // Check for environment variable or build setting
        if let envString = ProcessInfo.processInfo.environment["FIREBASE_ENV"] {
            return FirebaseEnvironment(rawValue: envString.lowercased()) ?? .development
        }
        
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

class FirebaseConfig {
    static let shared = FirebaseConfig()
    
    var environment: FirebaseEnvironment = .current
    
    private init() {}
    
    func configure() {
        FirebaseApp.configure()
        
        if environment.useEmulator {
            print("🔧 Using Firebase emulator at \(environment.emulatorHost):\(environment.emulatorPort)")
            Functions.functions().useEmulator(withHost: environment.emulatorHost, port: environment.emulatorPort)
        } else {
            print("🚀 Using Firebase \(environment)")
        }
    }
    
    func functions() -> Functions {
        let functions = Functions.functions()
        if environment.useEmulator {
            print("📡 Using emulated functions at \(environment.emulatorHost):\(environment.emulatorPort)")
        }
        return functions
    }
} 