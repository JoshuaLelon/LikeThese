import Foundation
import AVFoundation
import FirebaseStorage

class VideoCacheService {
    static let shared = VideoCacheService()
    private let cache = NSCache<NSString, AVURLAsset>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Set up cache directory in the temporary directory
        cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("VideoCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure cache limits
        cache.countLimit = 10 // Maximum number of videos to cache
        cache.totalCostLimit = 500 * 1024 * 1024 // 500MB limit
        
        print("📼 VideoCacheService initialized at \(self.cacheDirectory.path)")
    }
    
    func cachedPlayerItem(for url: URL) -> AVPlayerItem? {
        let key = url.absoluteString as NSString
        guard let asset = cache.object(forKey: key) else { return nil }
        return AVPlayerItem(asset: asset)
    }
    
    func cacheAsset(_ asset: AVURLAsset, for url: URL) {
        let key = url.absoluteString as NSString
        cache.setObject(asset, forKey: key)
        print("📥 Cached asset for URL: \(url)")
    }
    
    func preloadVideo(url: URL) async throws -> AVPlayerItem {
        let cacheKey = url.absoluteString as NSString
        
        // Check memory cache first
        if let cachedAsset = cache.object(forKey: cacheKey) {
            print("✅ Found cached video in memory for URL: \(url)")
            return AVPlayerItem(asset: cachedAsset)
        }
        
        // Generate local cache path
        let fileName = url.lastPathComponent
        let localURL = cacheDirectory.appendingPathComponent(fileName)
        
        // Check disk cache
        if fileManager.fileExists(atPath: localURL.path) {
            print("✅ Found cached video on disk: \(localURL.path)")
            let asset = AVURLAsset(url: localURL)
            let playerItem = AVPlayerItem(asset: asset)
            cacheAsset(asset, for: url)
            return playerItem
        }
        
        // Get Firebase Storage reference and download URL
        print("🔑 Getting Firebase Storage signed URL for: \(url)")
        
        // Extract filename from URL path
        let filename = url.lastPathComponent
        print("📄 Extracted filename: \(filename)")
        
        // Get storage reference for video
        let storageRef = Storage.storage().reference().child("videos").child(filename)
        
        do {
            let signedURL = try await storageRef.downloadURL()
            print("✅ Got signed URL: \(signedURL)")
            
            // Download video using signed URL
            print("📥 Downloading video using signed URL")
            let (tempURL, response) = try await URLSession.shared.download(from: signedURL)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "VideoCacheService", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "VideoCacheService", code: httpResponse.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)",
                        "statusCode": httpResponse.statusCode
                    ])
            }
            
            // Move downloaded file to cache
            try? fileManager.removeItem(at: localURL) // Remove any existing file
            try fileManager.moveItem(at: tempURL, to: localURL)
            
            print("✅ Downloaded and cached video at: \(localURL.path)")
            
            // Create asset from local file
            let asset = AVURLAsset(url: localURL)
            let playerItem = AVPlayerItem(asset: asset)
            
            // Add error monitoring
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { notification in
                if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                    print("❌ Playback failed: \(error.localizedDescription)")
                }
            }
            
            cacheAsset(asset, for: url)
            return playerItem
            
        } catch {
            print("❌ Failed to download video: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            throw error
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("🗑 Cleared video cache")
    }
    
    private func cleanupOldCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            if contents.count > cache.countLimit {
                let sortedFiles = try contents.sorted {
                    let date1 = try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date()
                    let date2 = try $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date()
                    return date1 < date2
                }
                
                // Remove oldest files
                let filesToRemove = sortedFiles[0..<(contents.count - cache.countLimit)]
                for fileURL in filesToRemove {
                    try? fileManager.removeItem(at: fileURL)
                    print("🗑 Removed old cached video: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Failed to cleanup cache: \(error.localizedDescription)")
        }
    }
} 