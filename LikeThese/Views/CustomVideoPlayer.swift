import SwiftUI
import AVKit

/// A SwiftUI-compatible container for AVPlayerViewController.
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("🎮 makeUIViewController called")
        let controller = AVPlayerViewController()
        controller.player = player
        // Hide built-in controls and let SwiftUI handle gestures
        controller.showsPlaybackControls = false
        // Disable controller's ability to intercept touches
        controller.view.isUserInteractionEnabled = false
        print("🎮 Created AVPlayerViewController with controls and touch disabled")
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        print("🎮 updateUIViewController called")
        uiViewController.player = player
    }
} 