import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.Gauntlet.LikeThese", category: "VideoCacheService")

class VideoCacheService {
    static let shared = VideoCacheService()
    private let cache = NSCache<NSString, AVPlayerItem>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Set up cache directory in the temporary directory
        cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("VideoCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure cache limits
        cache.countLimit = 10 // Maximum number of videos to cache
        cache.totalCostLimit = 500 * 1024 * 1024 // 500MB limit
        
        logger.debug("📼 VideoCacheService initialized at \(self.cacheDirectory.path)")
    }
    
    func cachedPlayerItem(for url: URL) -> AVPlayerItem? {
        let key = url.absoluteString as NSString
        return cache.object(forKey: key)
    }
    
    func cachePlayerItem(_ playerItem: AVPlayerItem, for url: URL) {
        let key = url.absoluteString as NSString
        cache.setObject(playerItem, forKey: key)
        logger.debug("📥 Cached player item for URL: \(url)")
    }
    
    func preloadVideo(url: URL) async throws -> AVPlayerItem {
        if let cachedItem = cachedPlayerItem(for: url) {
            logger.debug("✅ Found cached video for URL: \(url)")
            return cachedItem
        }
        
        logger.debug("🔄 Preloading video from URL: \(url)")
        let asset = AVURLAsset(url: url)
        
        try await asset.loadValues(forKeys: ["playable"])
        
        guard asset.isPlayable else {
            let error = NSError(domain: "VideoCacheService", code: -1, 
                              userInfo: [NSLocalizedDescriptionKey: "Asset is not playable"])
            throw error
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        cachePlayerItem(playerItem, for: url)
        return playerItem
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        logger.debug("🗑 Cleared video cache")
    }
} 