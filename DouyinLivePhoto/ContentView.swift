import SwiftUI

/// Cookie 持久化键：仅存于本机 UserDefaults（App 沙盒），绝不写入源码/仓库
private let cookieStoreKey = "douyin_cookie"

struct ContentView: View {
    @State private var link = ""
    /// 用 @AppStorage 把 cookie 存进本机 UserDefaults，关掉 App 也保留，重装/卸载即清除
    @AppStorage(cookieStoreKey) private var storedCookie = ""
    /// 输入框里的临时文本（未点「保存」前不影响已存值）
    @State private var cookieInput = ""
    @State private var status = "粘贴抖音分享链接后点「下载」"

    var body: some View {
        VStack(spacing: 16) {
            Text("抖音下载").font(.title).padding(.top, 40)

            TextField("抖音分享链接", text: $link)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)

            SecureField("可选：登录 douyin.com 的 Cookie（仅本机保存）", text: $cookieInput)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .textContentType(.URL)
                .autocapitalization(.none)
                .onAppear { cookieInput = storedCookie }   // 打开 App 自动回填已保存的 cookie

            Text("Cookie 只存在你的 iPhone 本地，不会上传到任何服务器或代码仓库。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(storedCookie.isEmpty ? "保存 Cookie" : "更新 Cookie") {
                    storedCookie = cookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    status = storedCookie.isEmpty ? "已清空已保存的 Cookie" : "Cookie 已保存到本机 ✓"
                }
                .buttonStyle(.bordered)
                .disabled(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("重置", role: .destructive) {
                    cookieInput = ""
                    storedCookie = ""
                    status = "Cookie 已重置，本机记录已清除"
                }
                .buttonStyle(.bordered)
                .disabled(storedCookie.isEmpty && cookieInput.isEmpty)
            }

            if !storedCookie.isEmpty {
                Label("Cookie 已保存在本机", systemImage: "checkmark.shield.fill")
                    .font(.footnote)
                    .foregroundColor(.green)
            }

            Button("下载") { Task { await download() } }
                .buttonStyle(.borderedProminent)

            Text(status)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    func download() async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "请先粘贴链接"; return }
        status = "解析中…"
        // 输入框有填就用输入框的，否则用已保存的（输入一次长期生效）
        let raw = cookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = raw.isEmpty ? storedCookie : raw
        do {
            let items = try await DouyinParser.shared.items(
                fromShareURL: trimmed,
                cookie: effective.isEmpty ? nil : effective
            )
            status = "解析到 \(items.count) 个媒体，下载中…"
            try await LivePhotoSaver.shared.save(items)
            status = "已保存到相册 ✓"
        } catch {
            status = "失败：\(error.localizedDescription)"
        }
    }
}
