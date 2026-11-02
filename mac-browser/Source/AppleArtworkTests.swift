import AppKit

final class ArtworkFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var requestCount = 0
    static var fixture = Data()
    static var image = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requestCount += 1; Self.lock.unlock()
        let data = request.url!.host == "itunes.apple.com" ? Self.fixture : Self.image
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
}

@main enum AppleArtworkTests {
    static func main() {
        let correct = "https://is1-ssl.mzstatic.com/image/thumb/cover/100x100bb.jpg"
        func candidate(_ title: String = "Kya Baat Ay", artist: String = "Harrdy Sandhu", album: String = "Kya Baat Ay - Single", duration: Double = 179_444, artwork: String? = nil) -> [String: Any] {
            ["trackName": title, "artistName": artist, "collectionName": album,
             "trackTimeMillis": duration, "artworkUrl100": artwork ?? correct]
        }
        func data(_ rows: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: ["results": rows]) }
        func match(_ rows: [[String: Any]], album: String = "Kya Baat Ay - Single") -> URL? {
            AppleArtworkLoader.matchedArtwork(in: data(rows), title: "Kya Baat Ay", artist: "Harrdy Sandhu", album: album, duration: 179.4)
        }
        assert(match([candidate("Kya Baat Ay (DJ NYK Remix)"), candidate()])?.absoluteString == correct)
        assert(match([candidate()], album: "Kya Baat Ay")?.absoluteString == correct)
        assert(match([candidate(artist: "Harrdy Sandhu & Jaani")]) == nil)
        assert(match([candidate(album: "Other Compilation")]) == nil)
        assert(match([candidate(duration: 200_000)]) == nil)
        assert(match([candidate(artwork: "https://evil.example/image.jpg")]) == nil)
        assert(match([candidate(artwork: "http://is1-ssl.mzstatic.com/cover.jpg")]) == nil)
        assert(AppleArtworkLoader.allowedArtworkURL("https://mzstatic.com.evil.example/cover.jpg") == nil)
        assert(AppleArtworkLoader.allowedArtworkURL("https://user:password@is1-ssl.mzstatic.com/cover.jpg") == nil)
        assert(match([candidate(), candidate(album: "Other Compilation", artwork: "https://is1-ssl.mzstatic.com/other.jpg")], album: "") == nil)
        assert(AppleArtworkLoader.matchedArtwork(in: Data("invalid".utf8), title: "Kya Baat Ay", artist: "Harrdy Sandhu", album: "", duration: 179) == nil)

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        ArtworkFixtureProtocol.image = bitmap.representation(using: .png, properties: [:])!
        ArtworkFixtureProtocol.fixture = data([candidate()])
        func loader() -> AppleArtworkLoader {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ArtworkFixtureProtocol.self]
            return AppleArtworkLoader(configuration: configuration)
        }
        let coverLoader = loader()
        var loaded: NSImage?
        coverLoader.load(title: "Kya Baat Ay", artist: "Harrdy Sandhu", album: "Kya Baat Ay - Single", duration: 179.4) { loaded = $0 }
        let deadline = Date(timeIntervalSinceNow: 2)
        while loaded == nil && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        assert(loaded?.isValid == true && ArtworkFixtureProtocol.count == 2)
        let requests = ArtworkFixtureProtocol.count
        coverLoader.load(title: "Kya Baat Ay", artist: "Harrdy Sandhu", album: "Kya Baat Ay - Single", duration: 179.4) { assert($0 === loaded) }
        assert(ArtworkFixtureProtocol.count == requests) // cached cover never repeats the search
        let cancelled = loader()
        var staleCallback = false
        cancelled.load(title: "Kya Baat Ay", artist: "Harrdy Sandhu", album: "Kya Baat Ay - Single", duration: 179.4) { _ in staleCallback = true }
        cancelled.cancel()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        assert(!staleCallback)
        print("Apple artwork checks passed: exact song/artist/album matching, remix/edition rejection, URL restrictions, image decoding, memory cache, and cancelled request isolation.")
    }
}
