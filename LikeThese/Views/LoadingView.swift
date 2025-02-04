import SwiftUI

struct LoadingView: View {
    let message: String?
    let isError: Bool
    
    init(message: String? = nil, isError: Bool = false) {
        self.message = message
        self.isError = isError
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(isError ? .red : .white)
            
            if let message = message {
                Text(message)
                    .foregroundColor(isError ? .red : .white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.7))
    }
}

#Preview {
    LoadingView(message: "Loading next video...", isError: false)
} 