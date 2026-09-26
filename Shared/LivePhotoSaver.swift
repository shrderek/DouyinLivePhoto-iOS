import Foundation
import Photos
import AVFoundation
import CoreMedia

/// 把解析到的媒体保存到相册。
/// - video / image：直接存
/// - live：下载静帧 + 动图，给两者写入【匹配】的 assetIdentifier 后用 PHAssetCreationRequest 配对成真·实况图
///
/// 关键点（iOS 实况图配对硬要求）：
/// 静帧 JPG 的 XMP 里要有 `xmpNote:ContentIdentifier`，动图 MOV 的 metadata 里要有
/// `com.apple.quicktime.content-identifier`，且两者值必须一致。任缺其一，相册只会把它们当成
/// 独立的「图片 + 视频」，不会显示实况角标。这里两边都写同一串 UUID。
public final class LivePhotoSaver {
    public static let shared = LivePhotoSaver()
    private let downloader = MediaDownloader.shared
    private init() {}

    public func save(_ items: [MediaItem]) async throws {
        // 1) 先全部下载到本地临时文件（变更块里应尽量轻量）
        struct Local {
            let kind: MediaItem
            let still: URL
            let motion: URL?
        }
        var locals: [Local] = []
        for item in items {
            switch item {
            case .video(let url):
                let d = try await downloader.data(from: url)
                locals.append(Local(kind: item, still: write(d, ext: "mp4"), motion: nil))
            case .image(let url):
                let d = try await downloader.data(from: url)
                locals.append(Local(kind: item, still: write(d, ext: "jpg"), motion: nil))
            case .live(let still, let motion):
                let sd = try await downloader.data(from: still)
                let md = try await downloader.data(from: motion)
                // 同一个 identifier 同时写进 JPG(XMP) 与 MOV(udta)，才能完成配对
                let identifier = UUID().uuidString
                let stillURL = tagStillJPEG(sd, identifier: identifier)
                let motionURL = tagMotionMOV(md, identifier: identifier)
                locals.append(Local(kind: item, still: stillURL, motion: motionURL))
            }
        }

        // 2) 在照片库变更块里写入（live 用 .photo + .pairedVideo 配对）
        try await PHPhotoLibrary.shared().performChanges {
            for l in locals {
                let req = PHAssetCreationRequest.creationRequestForAsset()
                switch l.kind {
                case .video:
                    req.addResource(with: .video, fileURL: l.still, options: nil)
                case .image:
                    req.addResource(with: .photo, fileURL: l.still, options: nil)
                case .live:
                    guard let motion = l.motion else { break }
                    req.addResource(with: .photo, fileURL: l.still, options: nil)
                    req.addResource(with: .pairedVideo, fileURL: motion, options: nil)
                }
            }
        }
    }

    // MARK: - 工具

    private func write(_ data: Data, ext: String) -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent(UUID().uuidString + "." + ext)
        try? data.write(to: url)
        return url
    }

    /// 把静帧 JPG 写入匹配的 XMP ContentIdentifier（插入 APP1 段）。
    /// 这是实况图配对必不可少的一步——否则只能得到独立的图片。
    private func tagStillJPEG(_ data: Data, identifier: String) -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        // 不是合法 JPEG(FFD8 开头) 就原样写回
        guard data.count > 2, data[0] == 0xFF, data[1] == 0xD8 else {
            try? data.write(to: out)
            return out
        }
        let ns = "http://ns.adobe.com/xap/1.0/"
        let packet = xmpPacket(identifier: identifier)
        var payload = Data(ns.utf8)
        payload.append(0) // 命名空间以 null 结尾
        payload.append(packet)          // XMP 包
        let length = UInt16(payload.count + 2) // 长度字段本身计入

        var app1 = Data()
        app1.append(0xFF); app1.append(0xE1)            // APP1 marker
        app1.append(UInt8(length >> 8))
        app1.append(UInt8(length & 0xFF))
        app1.append(contentsOf: payload)

        var outData = Data()
        outData.append(data[0]); outData.append(data[1]) // SOI
        outData.append(contentsOf: app1)
        outData.append(contentsOf: data[2...])            // 其余原样跟随
        try? outData.write(to: out)
        return out
    }

    /// 把实况动图 MOV 写入匹配的 com.apple.quicktime.content-identifier（passthrough 导出）。
    private func tagMotionMOV(_ data: Data, identifier: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let src = dir.appendingPathComponent(UUID().uuidString + ".mov")
        let dst = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try? data.write(to: src)
        let asset = AVURLAsset(url: src)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return src }
        export.outputURL = dst
        export.outputFileType = .mov
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataIdentifier(rawValue: "com.apple.quicktime.content-identifier")
        item.value = identifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        export.metadata = [item]
        let sem = DispatchSemaphore(value: 0)
        export.exportAsynchronously { sem.signal() }
        sem.wait()
        if export.status == .completed, FileManager.default.fileExists(atPath: dst.path) {
            return dst
        }
        return src
    }

    /// 标准 Live Photo XMP 包（含 xmpNote:ContentIdentifier）
    private func xmpPacket(identifier: String) -> Data {
        let xml = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description xmlns:xmpNote="http://ns.adobe.com/xmp/1.0/">
           <xmpNote:ContentIdentifier>\(identifier)</xmpNote:ContentIdentifier>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        return Data(xml.utf8)
    }
}
