# NOTICE — 来源、版权与修改说明

本仓库是 **[ch6vip/fqapp](https://github.com/ch6vip/fqapp)** 的**非官方 iOS 移植版**。
上游项目是一个面向 Android 的 Flutter + Rust 内容聚合客户端。

- 上游仓库：<https://github.com/ch6vip/fqapp>
- 上游许可证：**GNU General Public License v3.0**（见 `LICENSE`）
- 上游版权：Copyright (C) 2026 ch6vip
- 本仓库基于的源码快照：`e43762d0ba9b192b5e8cb7db24a5b6e06f2216e3`
- 上游 README（原样保留）：`README-UPSTREAM.md`

## 本仓库的修改

本项目不是上游官方版本，和上游作者没有隶属或授权关系。主要修改：

1. 新增完整 iOS Runner（`ios/`），把 Rust 核心编译为 `fqapi_core.xcframework`
   并通过 flutter_rust_bridge 在 iOS 进程内运行。
2. 用 Swift 重写 Android Kotlin 平台通道：
   - `FqappPlayer.swift`：AVPlayer + FlutterTexture；
   - `FqappTts.swift`：AVSpeechSynthesizer；
   - `FqappReader.swift`：屏幕亮度、电量、常亮、字体导入；
   - `FqappFiles.swift` / `FqappDocuments.swift`：文档选择器、备份、TXT 导出；
   - `FqappPlugin.swift`：通道注册与系统分享。
3. 新增 Rust `rust/src/api/media_cache.rs`：iOS 上把 CENC 媒体解密到缓存后交给
   AVPlayer（Android 仍走 ExoPlayer 流式解密）。
4. 新增 iOS 构建/签名脚本：`scripts/build_rust_ios.sh`、
   `scripts/install_to_iphone.sh`、`scripts/package_ios_artifacts.sh`。
5. 显示名称改为 **番茄小镇**；内部 Dart package、Bundle ID 前缀和工程名仍为 `fqapp`。
6. 新增 iOS 移植说明 `IOS_PORT.md` 与集成测试 `integration_test/`。

## 许可

本仓库整体继续以 **GPL-3.0** 发布。上游代码的版权归原作者所有；本仓库的移植修改
同样按 GPL-3.0 授权。分发本仓库或其修改版时，请保留本 NOTICE、`LICENSE` 和上游来源说明。

## 免责声明

本项目仅供学习与研究交流，不内置、不分发任何内容资源；在线内容来自第三方公开接口，
版权归原权利方所有。本项目与内容提供方无关联，未获其授权。请勿上架 App Store 或
分发内容资源。
