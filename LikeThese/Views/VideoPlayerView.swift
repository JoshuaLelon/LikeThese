import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let url: URL
    let index: Int
    @ObservedObject var videoManager: VideoManager
    
    var body: some View {
        ZStack {
            VideoPlayer(player: videoManager.player(for: index))
                .onAppear {
                    videoManager.prepareVideo(url: url, for: index)
                }
                .onDisappear {
                    videoManager.cleanupVideo(for: index)
                }
        }
    }
}

#if DEBUG
struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(
            url: URL(string: "https://example.com/video.mp4")!,
            index: 0,
            videoManager: VideoManager()
        )
    }
}
#endif 