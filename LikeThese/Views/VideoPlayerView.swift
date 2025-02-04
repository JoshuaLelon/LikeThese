import SwiftUI
import AVKit
import FirebaseStorage

struct VideoPlayerView: View {
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var isLoading: Bool = true
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .onTapGesture {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                    }
            }
            
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await loadRandomVideo()
        }
    }
    
    private func loadRandomVideo() async {
        isLoading = true
        do {
            let storageService = StorageService()
            let url = try await storageService.fetchRandomVideo()
            player = AVPlayer(url: url)
            isLoading = false
        } catch {
            print("Error loading video: \(error.localizedDescription)")
            isLoading = false
        }
    }
}

#Preview {
    VideoPlayerView()
} 