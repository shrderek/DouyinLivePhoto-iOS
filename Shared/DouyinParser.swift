import Foundation

/// 在 iOS 本地解析抖音分享链接，无需任何服务器。
///
/// 主路径：复刻 PC 项目 douyin-monitor-2/http_req.py —— 带登录 Cookie + uifid + x-tt-argus 头，
/// 打 `https://www.douyin.com/aweme/v1/web/aweme/detail/` 拿结构化 JSON，绕开 argus 反爬预检页。
/// 已在 PC 项目对真链（aweme_id=7686856554679486129）实测通过：HTTP 200 / status_code=0，
/// 正确返回 3 张图（第 2 张带实况动图）。
///
/// 兜底：RENDER_DATA HTML 爬取（匿名真链常被 argus 挡死，仅作退化路径）。
public final class DouyinParser {
    public static let shared = DouyinParser()

    // ---- 复刻 PC 项目 http_req.py 的常量（已实测通过，勿自行编造）----
    private let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0"
    private let homeURL = "https://www.douyin.com/"
    private let detailPath = "/aweme/v1/web/aweme/detail/"
    private let commonParams: [(String, String)] = [
        ("device_platform", "webapp"), ("aid", "6383"), ("channel", "channel_pc_web"),
        ("update_version_code", "170400"), ("pc_client_type", "1"), ("pc_libra_divert", "Windows"),
        ("support_h265", "1"), ("support_dash", "0"), ("version_code", "290100"), ("version_name", "29.1.0"),
        ("cookie_enabled", "true"), ("screen_width", "1920"), ("screen_height", "1080"),
        ("browser_language", "zh-CN"), ("browser_platform", "Win32"), ("browser_name", "Edge"),
        ("browser_version", "130.0.0.0"), ("browser_online", "true"), ("engine_name", "Blink"),
        ("engine_version", "130.0.0.0"), ("os_name", "Windows"), ("os_version", "10"), ("cpu_core_num", "12"),
        ("device_memory", "8"), ("platform", "PC"), ("downlink", "10"), ("effective_type", "4g"),
        ("round_trip_time", "50"),
    ]

    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        session = URLSession(configuration: cfg)
    }

    // MARK: - 对外入口

    /// 输入分享链接，返回媒体项列表。
    /// - cookie: 登录 douyin.com 后的 Cookie 字符串（强烈建议带，绕过 argus）。
    /// - uifid: Cookie 里的 UIFID 值（可选）。
    /// - xTtArgus: argus 头，默认 "1"。
    public func items(fromShareURL urlString: String, cookie: String? = nil,
                      uifid: String = "", xTtArgus: String = "1") async throws -> [MediaItem] {
        // 主路径：JSON 接口（有 cookie 即稳，已实测）
        if let cookie = cookie, !cookie.isEmpty,
           let aid = try? await resolveAwemeID(urlString),
           let aweme = try? await fetchAwemeDetail(awemeID: aid, cookie: cookie, uifid: uifid, xTtArgus: xTtArgus) {
            let items = extractItems(from: aweme)
            if !items.isEmpty { return items }
        }
        // 兜底：RENDER_DATA HTML 爬取
        if let html = try? await fetchHTML(urlString, cookie: cookie),
           let render = extractRenderData(html) {
            return parseRenderData(render)
        }
        throw NSError(domain: "DouyinParser", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "解析失败：可能遇到抖音验证页。请在 App 设置里填入登录 douyin.com 的 Cookie（见 README_build.md）。"])
    }

    // MARK: - JSON 接口主路径

    private func resolveAwemeID(_ urlString: String) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(webUA, forHTTPHeaderField: "User-Agent")
        let (_, resp) = try await session.data(for: req)
        let final = (resp as? HTTPURLResponse)?.url?.absoluteString ?? urlString
        let pat = try NSRegularExpression(pattern: "\\d{15,20}")
        if let m = pat.firstMatch(in: final, range: NSRange(final.startIndex..., in: final)),
           let r = Range(m.range, in: final) {
            return String(final[r])
        }
        return nil
    }

    private func fetchAwemeDetail(awemeID: String, cookie: String, uifid: String, xTtArgus: String) async throws -> [String: Any]? {
        var comps = URLComponents(string: "https://www.douyin.com" + detailPath)!
        var q = commonParams.map { URLQueryItem(name: $0.0, value: $0.1) }
        q.append(URLQueryItem(name: "aweme_id", value: awemeID))
        comps.queryItems = q
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(webUA, forHTTPHeaderField: "User-Agent")
        req.setValue(homeURL, forHTTPHeaderField: "Referer")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        // PC 项目里 uifid 头的值 == Cookie 中的 UIFID=，自动从 cookie 提取（与 PC 逐字一致）
        var uifidToSend = uifid
        if uifidToSend.isEmpty, let rng = cookie.range(of: "UIFID=") {
            let rest = cookie[rng.upperBound...]
            let end = rest.firstIndex(of: ";") ?? rest.endIndex
            uifidToSend = String(rest[..<end]).trimmingCharacters(in: .whitespaces)
        }
        if !uifidToSend.isEmpty { req.setValue(uifidToSend, forHTTPHeaderField: "uifid") }
        req.setValue(xTtArgus, forHTTPHeaderField: "x-tt-argus")
        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let code = json["status_code"] as? Int, code != 0 { return nil }
        if let d = json["aweme_detail"] as? [String: Any] { return d }
        if let list = json["aweme_list"] as? [[String: Any]], let first = list.first { return first }
        return nil
    }

    private func extractItems(from aweme: [String: Any]) -> [MediaItem] {
        var items: [MediaItem] = []
        // 图文 / 实况优先（slides 帖的 video 字段只是轮播预览，不单独下）
        if let images = aweme["images"] as? [[String: Any]] {
            for im in images {
                let jpeg = pickJPEG(im["url_list"] as? [String])
                var motion: URL? = nil
                if let vm = im["video"] as? [String: Any],
                   let pa = vm["play_addr"] as? [String: Any],
                   let list = pa["url_list"] as? [String],
                   let s = list.first, let u = URL(string: s) { motion = u }
                if let m = motion, let still = jpeg {
                    items.append(.live(still: still, motion: m))
                } else if let still = jpeg {
                    items.append(.image(url: still))
                }
            }
        }
        if !items.isEmpty { return items }
        // 纯视频
        if let vid = aweme["video"] as? [String: Any], let u = bestVideoURL(from: vid) {
            items.append(.video(url: u))
        }
        return items
    }

    private func pickJPEG(_ list: [String]?) -> URL? {
        guard let list = list else { return nil }
        for u in list {
            if u.contains(".jpeg") || u.contains(".jpg"), let url = URL(string: u) { return url }
        }
        return list.first.flatMap { URL(string: $0) }
    }

    private func bestVideoURL(from vid: [String: Any]) -> URL? {
        var cands: [(Int, String)] = []
        if let br = vid["bit_rate"] as? [[String: Any]] {
            for b in br {
                if let pa = b["play_addr"] as? [String: Any],
                   let list = pa["url_list"] as? [String], let s = list.first {
                    cands.append(((b["bit_rate"] as? Int) ?? 0, s))
                }
            }
        }
        if let best = cands.max(by: { $0.0 < $1.0 })?.1, let u = URL(string: best) { return u }
        if let pa = vid["play_addr"] as? [String: Any],
           let list = pa["url_list"] as? [String], let s = list.first,
           let u = URL(string: s) { return u }
        return nil
    }

    // MARK: - RENDER_DATA 兜底

    private func fetchHTML(_ urlString: String, cookie: String?) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "DouyinParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "链接非法"])
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue(homeURL, forHTTPHeaderField: "Referer")
        if let cookie = cookie, !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, _) = try await session.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractRenderData(_ html: String) -> [String: Any]? {
        let pattern = #"<script\s+id="RENDER_DATA"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(m.range(at: 1), in: html) else { return nil }
        let encoded = String(html[range])
        guard let unescaped = encoded.removingPercentEncoding,
              let data = unescaped.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseRenderData(_ obj: Any) -> [MediaItem] {
        var items: [MediaItem] = []
        if let node = findVideoNode(obj), let u = bestVideoURL(node) {
            items.append(.video(url: u))
        }
        if let note = findImageNote(obj) {
            for im in note {
                let urls = (im["urlList"] as? [String]) ?? []
                if let still = urls.first.flatMap({ URL(string: $0) }) {
                    var motion: URL? = nil
                    if let vm = im["video"] as? [String: Any],
                       let vl = vm["urlList"] as? [String],
                       let ms = vl.first {
                        motion = URL(string: ms)
                    }
                    if let m = motion {
                        items.append(.live(still: still, motion: m))
                    } else {
                        items.append(.image(url: still))
                    }
                }
            }
        }
        return items
    }

    private func findVideoNode(_ obj: Any) -> [String: Any]? {
        if let d = obj as? [String: Any] {
            if d["playApi"] != nil || d["playAddr"] != nil { return d }
            for (_, v) in d { if let r = findVideoNode(v) { return r } }
        } else if let a = obj as? [Any] {
            for v in a { if let r = findVideoNode(v) { return r } }
        }
        return nil
    }

    private func bestVideoURL(_ node: [String: Any]) -> URL? {
        if let pa = node["playApi"] as? String, let u = URL(string: pa) { return u }
        if let arr = node["playAddr"] as? [[String: Any]],
           let first = arr.first,
           let list = first["urlList"] as? [String],
           let s = list.first,
           let u = URL(string: s) { return u }
        return nil
    }

    private func findImageNote(_ obj: Any) -> [[String: Any]]? {
        if let d = obj as? [String: Any] {
            if let imgs = d["images"] as? [[String: Any]] { return imgs }
            for (_, v) in d { if let r = findImageNote(v) { return r } }
        } else if let a = obj as? [Any] {
            for v in a { if let r = findImageNote(v) { return r } }
        }
        return nil
    }
}
