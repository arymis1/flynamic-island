import AppKit
import Combine
import ImageIO

final class YouTubeArtworkLoader: NSObject, URLSessionTaskDelegate {
    private var task: URLSessionDataTask?
    private var current = ""
    private var retry = Date.distantPast
    private var loading = false
    private let cache = NSCache<NSString, NSImage>()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    override init() { super.init(); cache.countLimit = 8 }
    static func allowedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              host == "i.ytimg.com" || host == "yt3.ggpht.com" || host == "lh3.googleusercontent.com" || host == "yt3.googleusercontent.com" else { return nil }
        return url
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { Self.allowedURL($0.absoluteString) } == nil ? nil : request)
    }
    func cancel() { task?.cancel(); task = nil; current = ""; loading = false; retry = .distantPast }
    func load(_ value: String, completion: @escaping (NSImage) -> Void) {
        guard let url = Self.allowedURL(value) else {
            cancel(); return
        }
        if current != value { cancel(); current = value }
        if let image = cache.object(forKey: value as NSString) { completion(image); return }
        guard !loading, Date() >= retry else { return }
        loading = true
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            var image: NSImage?
            if let response = response as? HTTPURLResponse, response.statusCode == 200,
               Self.allowedURL(response.url?.absoluteString ?? "") != nil,
               let data, data.count < 6 * 1024 * 1024,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            DispatchQueue.main.async {
                guard let self, self.current == value else { return }
                self.loading = false; self.task = nil; self.retry = Date().addingTimeInterval(10)
                if let image { self.cache.setObject(image, forKey: value as NSString); completion(image) }
            }
        }
        task?.resume()
    }
}
