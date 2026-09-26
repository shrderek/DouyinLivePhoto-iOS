import Foundation

/// 带浏览器 UA + Referer 下载抖音媒体（抖音 CDN 常校验 Referer）
public final class MediaDownloader {
    public static let shared = MediaDownloader()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://www.douyin.com/"
        ]
        session = URLSession(configuration: cfg)
    }

    public func data(from url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, _) = try await session.data(for: req)
        return data
    }
}
