import UIKit

/// 共享扩展：从系统分享面板接收抖音链接（URL 或文本），本地解析并保存
class ShareViewController: UIViewController, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        var found: String?
        let group = DispatchGroup()
        for provider in item.attachments ?? [] {
            if found != nil { break }
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { data, _ in
                    if let u = data as? URL { found = u.absoluteString }
                    else if let s = data as? String { found = s }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.text") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
                    if let s = data as? String { found = s }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            self.process(link: found, context: context)
        }
    }

    private func process(link: String?, context: NSExtensionContext) {
        guard let link = link, !link.trimmingCharacters(in: .whitespaces).isEmpty else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        Task {
            do {
                let items = try await DouyinParser.shared.items(fromShareURL: link)
                try await LivePhotoSaver.shared.save(items)
            } catch {
                // 失败也关闭面板，避免卡住；可在主 App 里重试看详细报错
            }
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
