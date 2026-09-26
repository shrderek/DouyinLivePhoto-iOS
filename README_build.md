# 抖音下载 · 纯本地 iOS App（真·实况图）

无需服务器、无需 Mac 在桌上（编译交给 GitHub Actions 云 Mac），用你自己的免费 Apple ID 签名侧载。
满足：iOS 端输入抖音分享链接 → 下载**视频 / 图片 / 实况动图**，且实况图配对成真·实况（角标 + 长按动态）。

## 费用
- GitHub Actions 编译：**免费**（公开仓库无限时长；私有仓库每月免费额度足够偶发构建）。
- Apple 签名：**免费 Apple ID**（7 天有效、最多 3 台设备、10 个 App ID）。
- 你贴的「苹果签名安装助手」工具：在 Windows 生成免费证书 + 签名 + 扫码安装，**免费**。

整条链路 **0 元**。

## 三步产出 IPA（只需做一次，之后只在改代码时重跑）
1. 在 GitHub 新建一个**公开**仓库，把本目录（`ios-app/`）内容推上去。
2. 进仓库 **Actions → Build IPA (unsigned) → Run workflow**，等几分钟。
3. 在 Actions 运行结果里下载构件 `DouyinLivePhoto-unsigned`（即未签名 IPA）。

> 编译这一步本来卡你「没 Mac」——交给云 Mac 正好补上。编译报错会直接显示在 Actions 日志里。

## 在你 Windows 上签名 + 安装（免费证书工具）
1. 下载「苹果签名安装助手」（leapever.com），用你的 Apple ID 生成免费证书（填入 iPhone UDID）。
2. 选刚才下载的 `DouyinLivePhoto-unsigned.ipa` + 刚生成的证书 → 开始签名。
3. 点「生成二维码安装」，iPhone 相机扫码直装。
4. 首次打开去 **设置 → 通用 → VPN 与设备管理 → 信任**。

## 7 天续期
免费证书 7 天过期。用同一 Apple ID + 同一设备 UDID + 同一 Bundle ID 在工具里重走一遍，
对原 IPA 重签重装即可，又是 7 天（可常连电脑用工具自动重签）。

## 使用
- **主 App**：打开 App，粘贴抖音分享链接点「下载」。
  - 顶部「Cookie」框可选填：**填一次 → 点「保存 Cookie」即记到本机**，之后每次打开自动回填，长期生效。
  - 「重置」按钮：一键清空本机保存的 Cookie（输入框与存储都清掉）。
- **共享扩展**：抖音里点「分享 → 复制链接」，或在任意 App 选中链接 → 系统分享 → 选「抖音下载」→ 自动存相册（走匿名路径，不含 Cookie）。

## Cookie 安全说明（重要）
- **绝不上传仓库**：Cookie 只存在 **iPhone 本机沙盒（UserDefaults）**，物理位置在设备上，不在源码、不在编译出的 IPA、也不在 git。
- 本目录已加 `.gitignore`，`config.json` / `*.xcconfig` / `.env` 等本地配置一律被忽略，即使误放也不会被提交。
- **uifid 也不落盘**：`uifid` 头的值由代码在发请求时从你输入的 Cookie 里自动解析 `UIFID=` 得到，**绝不单独存储、没有独立输入框、不写任何文件**，请求结束即丢弃。它和 Cookie 一样只存在于本机内存，不会进仓库。
- 想彻底清除：App 里点「重置」，或直接在 iPhone 上删除本 App（UserDefaults 随 App 一并移除）。
- 不要为了「省事」把 Cookie / uifid 写进 `config.json` 再提交——那是唯一会泄的途径，请勿如此。

## 重要说明（诚实交代）
1. **未真机实测**：本工程由我手写，CI 只保证能编译通过；真机上的解析成功率与实况配对需你装好后验证。
   若 Actions 编译报错，把日志发我，我改。
2. **实况图配对是最易出问题的环节**：`LivePhotoSaver` 对动图 MOV 做了 best-effort 的 `assetIdentifier`
   写入，但静帧 JPG 的 XMP 配对与最终能否被相册识别为实况，需设备验证。
   - 若装好后实况图显示成「分开的静帧+视频」：可用 README 提到的 **App Store 免费实况图制作 App**
     手动把 `RENDER_DATA` 里的静帧+动图配对（兜底方案 C），或把问题反馈给我调写入逻辑。
3. **抖音反爬**：客户端直连 `www.douyin.com` 偶尔会返回验证页（RENDER_DATA 取不到）。
   最稳的解法是在 `DouyinParser.fetchHTML` 的 `httpAdditionalHeaders` 里加上你**自己登录 douyin.com 后的 Cookie**
   （从 Safari 开发者工具复制），仍完全本地、无第三方服务器。
4. **去水印不保证 100%**：优先取 `playApi`（通常无水印），取不到回退 `playAddr`（带水印），由抖音服务端决定。

## 代码结构
- `Shared/DouyinParser.swift` —— 链接解析 + RENDER_DATA 提取（对应之前 Python 后端的逻辑）
- `Shared/MediaDownloader.swift` —— 带 UA/Referer 下载
- `Shared/LivePhotoSaver.swift` —— PHAsset 保存 + 实况配对
- `DouyinLivePhoto/` —— 主 App（SwiftUI，粘贴链接入口）
- `DouyinLivePhotoShareExtension/` —— 共享扩展（接收分享链接）
- `project.yml` —— XcodeGen 配置（CI 用 `brew install xcodegen && xcodegen generate` 生成 xcodeproj）
- `.github/workflows/build-ipa.yml` —— 云 Mac 编译未签名 IPA
