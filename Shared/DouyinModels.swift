import Foundation

/// 解析出的单个媒体项
public enum MediaItem: Identifiable {
    case video(url: URL)
    case image(url: URL)
    case live(still: URL, motion: URL)

    public var id: String {
        switch self {
        case .video(let u): return "video:" + u.absoluteString
        case .image(let u): return "image:" + u.absoluteString
        case .live(let s, let m): return "live:" + s.absoluteString + "|" + m.absoluteString
        }
    }
}
