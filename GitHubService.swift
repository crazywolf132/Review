class GitHubService {
    private let token: String
    private let session = URLSession.shared
    // Larger circular image processor with a higher resolution for menu items
    private let profileImageProcessor = RoundCornerImageProcessor(cornerRadius: 12, targetSize: CGSize(width: 24, height: 24), roundingCorners: .all, backgroundColor: .clear)

    init(token: String) {
        self.token = token
        
        // Configure Kingfisher with our settings
        let config = KingfisherManager.shared.downloader.sessionConfiguration
        var defaultHeaders = config.httpAdditionalHeaders ?? [:]
        defaultHeaders["Accept"] = "application/vnd.github+json"
        defaultHeaders["Authorization"] = "Bearer \(token)"
        defaultHeaders["X-GitHub-Api-Version"] = "2022-11-28"
        config.httpAdditionalHeaders = defaultHeaders
        KingfisherManager.shared.downloader.sessionConfiguration = config
        
        // Improve Kingfisher cache configuration
        ImageCache.default.diskStorage.config.expiration = .days(30) // Cache images for a month
        ImageCache.default.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024 // 100MB memory cache
        ImageCache.default.memoryStorage.config.expiration = .days(7) // Keep in memory for a week
        
        // Set up a cleanup schedule but don't clean on each init
        if !UserDefaults.standard.bool(forKey: "didCleanCacheToday") {
            ImageCache.default.cleanExpiredDiskCache()
            UserDefaults.standard.set(true, forKey: "didCleanCacheToday")
            
            // Reset the flag at midnight
            let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
            Timer.scheduledTimer(withTimeInterval: midnight.timeIntervalSinceNow, repeats: false) { _ in
                UserDefaults.standard.set(false, forKey: "didCleanCacheToday")
            }
        }
    }
    
    // Download author profile image from URL using Kingfisher
    func downloadProfileImage(from urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        // Create a unique identifier for this exact user avatar and size
        let cacheKey = "\(urlString)_24x24"
        
        // First check if the image is already in memory cache to avoid even the logging
        if let cachedImage = ImageCache.default.retrieveImageInMemoryCache(forKey: cacheKey) {
            completion(cachedImage)
            return
        }
        
        // Options for image loading - optimized for quality and performance
        let options: KingfisherOptionsInfo = [
            .processor(profileImageProcessor),
            .scaleFactor(NSScreen.main?.backingScaleFactor ?? 2.0),
            .cacheOriginalImage,
            .backgroundDecode,
            .diskCacheExpiration(.days(30)),
            .memoryCacheExpiration(.days(7)),
            .callbackQueue(.mainAsync),
            .cacheSerializer(FormatIndicatedCacheSerializer.png), // Force PNG for quality
            .diskCacheStrategy(.accessDate) // Prioritize recently used images
        ]
        
        // Use Kingfisher to download and cache the image with built-in processing
        KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            switch result {
            case .success(let value):
                completion(value.image)
            case .failure:
                completion(nil)
            }
        }
    }
} 