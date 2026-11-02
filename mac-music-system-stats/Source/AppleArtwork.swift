import AppKit
import ImageIO

private final class AppleArtworkNetworkPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        let allowed = url?.scheme == "https" && url?.user == nil && url?.password == nil
            && (url?.host?.lowercased() == "itunes.apple.com" || AppleArtworkLoader.allowedArtworkURL(url?.absoluteString ?? "") != nil)
        completionHandler(allowed ? request : nil)
    }
}

// Used only when Music's local queue and library expose no valid cover.
// Requests go to Apple's public catalog and artwork CDN, with no login/cookies.
final class AppleArtworkLoader {
    private struct SearchResponse: Decodable { let results: [Candidate] }
    private struct Candidate: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let trackTimeMillis: Double?
        let artworkUrl100: String?
    }
    private let session: URLSession
    private let cache = NSCache<NSString, NSImage>()
    private var task: URLSessionDataTask?
    private var currentKey = ""
    private var generation = 0
    private var inFlight = false
    private var retryAfter = 0.0
    private var nextSearchAt = 0.0

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 12
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: AppleArtworkNetworkPolicy(), delegateQueue: nil)
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 320 * 320 * 4
    }
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func normalizedAlbum(_ value: String) -> String {
        // Music sometimes omits the catalog's packaging suffix. Preserve all
        // edition/remix/remaster words rather than broadly matching any album.
        let suffix = #"\s+[-–—]\s+(Single|EP)$"#
        return normalized(value.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive]))
    }
    static func allowedArtworkURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.hasSuffix(".mzstatic.com") else { return nil }
        return url
    }
    static func matchedArtwork(in data: Data, title: String, artist: String, album: String, duration: Double) -> URL? {
        guard !normalized(title).isEmpty, !normalized(artist).isEmpty,
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        let matches = response.results.filter { item in
            guard normalized(item.trackName ?? "") == normalized(title),
                  normalized(item.artistName ?? "") == normalized(artist),
                  let milliseconds = item.trackTimeMillis, duration > 0,
                  abs(milliseconds / 1_000 - duration) <= 5 else { return false }
            return album.isEmpty || normalizedAlbum(item.collectionName ?? "") == normalizedAlbum(album)
        }.compactMap { allowedArtworkURL($0.artworkUrl100 ?? "") }
        // An unknown album with multiple different covers is ambiguous.
        guard let match = matches.first, Set(matches).count == 1 else { return nil }
        return match
    }
    func cancel() {
        generation += 1
        task?.cancel(); task = nil
        currentKey = ""; inFlight = false; retryAfter = 0
    }
    func load(title: String, artist: String, album: String, duration: Double, completion: @escaping (NSImage) -> Void) {
        guard !Self.normalized(title).isEmpty, !Self.normalized(artist).isEmpty, duration > 0 else { cancel(); return }
        let key = [title, artist, album, String(Int(duration))].joined(separator: "\u{1f}")
        if currentKey != key { cancel(); currentKey = key }
        if let image = cache.object(forKey: key as NSString) { completion(image); return }
        let now = ProcessInfo.processInfo.systemUptime
        guard !inFlight, now >= retryAfter, now >= nextSearchAt else { return }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US")]
        guard let url = components.url else { return }
        inFlight = true; nextSearchAt = now + 5
        let requestGeneration = generation
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            let response = response as? HTTPURLResponse
            let artworkURL = response?.statusCode == 200 && response?.url?.host == "itunes.apple.com"
                && (data?.count ?? Int.max) <= 1_048_576
                ? data.flatMap { Self.matchedArtwork(in: $0, title: title, artist: artist, album: album, duration: duration) } : nil
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration, self.currentKey == key else { return }
                guard let artworkURL else { self.finishFailure(); return }
                self.fetchImage(artworkURL, key: key, generation: requestGeneration, completion: completion)
            }
        }
        task?.resume()
    }
    private func fetchImage(_ url: URL, key: String, generation: Int, completion: @escaping (NSImage) -> Void) {
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            var decoded: NSImage?
            if let response = response as? HTTPURLResponse, response.statusCode == 200,
               Self.allowedArtworkURL(response.url?.absoluteString ?? "") != nil,
               let data, data.count <= 6 * 1_048_576,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) {
                decoded = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            DispatchQueue.main.async {
                guard let self, self.generation == generation, self.currentKey == key else { return }
                self.task = nil; self.inFlight = false
                guard let decoded else { self.retryAfter = ProcessInfo.processInfo.systemUptime + 30; return }
                self.cache.setObject(decoded, forKey: key as NSString, cost: 320 * 320 * 4)
                completion(decoded)
            }
        }
        task?.resume()
    }
    private func finishFailure() {
        task = nil; inFlight = false
        retryAfter = ProcessInfo.processInfo.systemUptime + 30
    }
}
