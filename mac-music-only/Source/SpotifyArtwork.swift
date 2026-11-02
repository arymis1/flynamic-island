import AppKit
import ImageIO

final class SpotifyArtworkLoader {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private let cache = NSCache<NSString, NSImage>()
    private var task: URLSessionDataTask?
    private var currentURL = ""
    private var retryAfter = 0.0
    private var inFlight = false
    init() { cache.countLimit = 8; cache.totalCostLimit = 8 * 640 * 640 * 4 }
    static func allowedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              host == "i.scdn.co" || host == "mosaic.scdn.co" || host.hasSuffix(".spotifycdn.com") else { return nil }
        return url
    }
    func cancel() {
        task?.cancel(); task = nil; currentURL = ""; inFlight = false; retryAfter = 0
    }
    func load(_ value: String, completion: @escaping (NSImage) -> Void) {
        guard let url = Self.allowedURL(value) else { cancel(); return }
        if currentURL != value { cancel(); currentURL = value }
        if let image = cache.object(forKey: value as NSString) { completion(image); return }
        guard !inFlight, ProcessInfo.processInfo.systemUptime >= retryAfter else { return }
        inFlight = true
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            var image: NSImage?
            if let response = response as? HTTPURLResponse, response.statusCode == 200,
               Self.allowedURL(response.url?.absoluteString ?? "") != nil,
               let data, data.count <= 6 * 1024 * 1024,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            DispatchQueue.main.async {
                guard let self, self.currentURL == value else { return }
                self.inFlight = false; self.task = nil
                self.retryAfter = ProcessInfo.processInfo.systemUptime + 10
                if let image {
                    self.cache.setObject(image, forKey: value as NSString, cost: 640 * 640 * 4)
                    completion(image)
                }
            }
        }
        task?.resume()
    }
}
