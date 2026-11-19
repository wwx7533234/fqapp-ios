# fqapp iOS 移植说明

本文记录把 `fqapp-master`（Android / Flutter + Rust 项目）移植到 iPhone 的改动、
构建方式、验证结果和已知限制。

## 1. 关于“反编译”

你给的 `fqapp-master.zip` 是**开源工程的源代码**（Flutter + Dart + Rust），不是编译后的
APK/IPA，因此不存在需要反编译的目标。本次工作是把这份 Android 客户端源码**移植**为
iOS 客户端：新增 iOS Runner、把 Rust 核心编译成 iOS 可用的 XCFramework，并用 Swift
补齐 Android 侧原本由 Kotlin 提供的平台能力。

## 2. 运行环境

- 显示名称：**番茄小镇**（iOS `CFBundleDisplayName`、Android `android:label`、
  App 内首页品牌与「关于」页；内部工程名、Bundle ID 和 Dart package 仍为 fqapp，
  避免破坏签名与已有数据）

- Flutter 3.47.7 / Dart 3.13.5（工程基线写的是 Flutter 3.44.6 / Dart ^3.12.2，3.47.7 可构建）
- Xcode 27.0，iOS 15.0+
- Rust 1.99，目标 `aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`
- CocoaPods 1.15.2（系统 Ruby 2.6 下需要 `RUBYOPT=-rlogger`）

## 3. 架构

```
Flutter UI (lib/)
   │  flutter_rust_bridge（进程内 FFI）
   ▼
Rust 核心 fqapi_core（rust/ → ios/fqapi_core/fqapi_core.xcframework）
   │  设备注册 / 上游签名 / 本地回环 HTTP / 资源与缓存
   ▼
127.0.0.1 随机端口（iOS 用 port 0，避免与其它本机服务抢 8080）
```

Android 侧由 Kotlin 插件提供的通道，在 iOS 上由 `ios/Runner/` 里的 Swift 实现：

| 通道 | iOS 实现 |
| --- | --- |
| `fqapp/native_player` + events | `FqappPlayer.swift`：AVPlayer + FlutterTexture（视频帧） |
| `fqapp/system_tts` + events | `FqappTts.swift`：AVSpeechSynthesizer，中文音色 |
| `fqapp/reader` + events | `FqappReader.swift`：屏幕亮度会话、电量、常亮、字体导入 |
| `fqapp/local_books` / `fqapp/library_backup` / `fqapp/downloads` | `FqappFiles.swift`：文档选择器、备份 JSON、TXT 导出 |
| `fqapp/share` | `FqappPlugin.swift`：UIActivityViewController |
| `fqapp/eink-refresh` | 返回“不支持”（海信墨水屏私有接口仅 Android 有） |
| `fqapp/volume-key` | no-op（iOS 不允许应用拦截音量键） |

### CENC 短剧/听书在 iOS 上怎么解密

Android 用 ExoPlayer + C 流式解密数据源。AVPlayer 不能播放 CENC MP4，所以 iOS 走：

1. Dart `NativePlayer.create(url, keyHex)` 在 iOS 且 key 非空时调用 Rust 新 API
   `prepare_media`；
2. Rust 下载（或读取本地离线文件）并复用原有 CENC 解密实现，输出明文 MP4 到
   `Library/Caches/media_cache/`；
3. 原生 AVPlayer 播放 `file://` 明文文件，帧经 `AVPlayerItemVideoOutput` 送进
   Flutter Texture。

首次播放会等待整集下载+解密（通常几秒），换来无需在 Swift 里再实现一份 CENC 解析。
明文缓存位于 Caches 目录，不进 iCloud 备份，系统可回收；这是与 Android 流式解密的
已知差异。

## 4. 功能状态

| 功能 | 状态 |
| --- | --- |
| 首页推荐 / 分类 / 搜索 / 详情 / 评论 | ✅ 真机数据源在模拟器加载成功 |
| 小说阅读（分页、章节、排版） | ✅ 集成测试打开真实作品并渲染出正文页 |
| TXT 整本导出 | ✅ 集成测试写入 Documents/Downloads |
| 短剧 / 漫剧 / 听书播放（含 CENC） | ✅ 首页短剧 feed 内联播放已取到真实视频纹理；音频复用同一通道 |
| 系统朗读（中文 TTS） | ✅ 集成测试收到 `done` 事件 |
| 阅读亮度 / 常亮 | ✅ 亮度会话集成测试通过 |
| 字体导入 | ✅ 已实现（TTF/OTF/TTC，文档选择器），需手动选文件验证 |
| 分享 / 备份导出导入 | ✅ 已实现（系统分享面板 / 文档选择器），UI 交互未自动化 |
| 音量键翻页 | ❌ iOS 不提供应用级拦截，阅读页请用触屏 |
| 海信墨水屏整屏刷新 | ❌ 仅 Android 厂商接口 |
| 后台音频 / 锁屏控制 | ✅ 已接 AVAudioSession、Now Playing、远程命令；真机待验收 |

## 5. 构建

前置：

```bash
# Rust iOS 目标
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
# CocoaPods（系统 Ruby 2.6 的写法；已安装可跳过）
gem install ffi -v 1.15.5 --user-install
gem install cocoapods -v 1.15.2 --user-install
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"
export RUBYOPT="-rlogger"
```

> ⚠️ 工程不要放在 iCloud 同步的 `~/Documents` 下。file provider 会给
> `Flutter.framework` 目录写 `com.apple.FinderInfo`，导致 Flutter 的
> `codesign` 报 `resource fork, Finder information, or similar detritus not allowed`。
> 当前工程在 `~/fqapp-master-ios`。

```bash
cd ~/fqapp-master-ios
./scripts/build_rust_ios.sh          # 生成 ios/fqapi_core/fqapi_core.xcframework
cd ios && pod install && cd ..
flutter build ios --simulator --debug
flutter build ipa --release --no-codesign
```

产物：

- 模拟器 App：`build/ios/iphonesimulator/Runner.app`
- 未签名归档：`build/ios/archive/Runner.xcarchive`
- 打包后的未签名 IPA：`dist/fqapp-ios-unsigned.ipa`（见 `scripts/package_ios_artifacts.sh`）

## 6. 装到真机 iPhone

本机 Xcode 没有登录 Apple ID、也没有可用签名证书，所以本次只能产出**未签名 IPA**。
任选一种方式签名安装：

1. **Xcode（推荐，免费 Apple ID 也可）**
   - `open ios/Runner.xcworkspace`
   - Runner target → Signing & Capabilities → 勾选 Automatically manage signing，
     选择你的 Team；如冲突把 Bundle Identifier 改成唯一值（例如
     `com.你的名字.fqapp`）。
   - 连接 iPhone，选择设备后 Run。免费账号的证书 7 天过期，到期重签即可。
2. **Sideloadly / AltStore**
   - 把 `dist/fqapp-ios-unsigned.ipa` 拖入 Sideloadly，输入 Apple ID 签名后安装。

首次启动需要联网完成设备注册；之后可离线阅读已缓存内容。

## 7. 验证记录

- 模拟器 iPhone 18 Pro（iOS 27）冷启动成功，`backend.log` 显示
  `Rust core init returned: running` / `backend healthy`，首页从真实上游加载出内容。
- `integration_test/ios_smoke_test.dart`：
  - 首页/短剧/书架切换；
  - 远程 MP4 → AVPlayer → FlutterTexture（`firstFrame` + `videoSize`）；
  - 短剧 feed 内联播放出现真实 `drama_inline_texture_*` 且无重试错误；
  - AVSpeechSynthesizer `done` 事件；阅读亮度会话。
- `integration_test/ios_reader_test.dart`：真实作品详情 → 阅读页，
  `reader-page-surface` 出现；TXT 导出写入 `Documents/Downloads/ios-smoke.txt`。
- Rust `cargo test --lib media_cache::tests`：用离线 CENC 夹具验证
  `prepare_media` 解出的明文与独立实现一致，并验证缓存复用 / 无密钥直通。
- Dart 定向回归：`backend_service`、`native_player`、`reader_device`、
  `imported_book_store`、`system_tts` 共 68 个测试通过。
- `flutter analyze --no-pub` 仅剩仓库原有的 `reader_page.dart` 警告。

构建产物：

```text
dist/fqapp-ios-unsigned.ipa             13 MB   （需签名后安装）
dist/fqapp-ios-signed-personalteam.ipa  ~13 MB  （已用本机 Personal Team 签名，绑当前 iPhone）
dist/fqapp-ios-simulator.zip            74 MB   （模拟器直接安装）
dist/fqapp-ios-source.zip               23 MB   （完整源码，不含 build/ 与 Pods/）
dist/iOS签名安装图文教程.pdf              8 页   （签名+安装图文流程）
dist/signing-guide/guide.html                   （教程的可编辑 HTML 源）
dist/SHA256SUMS
dist/screenshots/                              （模拟器 + 真机运行截图）
```

### 真机安装结果（验证记录，已移除本机个人信息）

- 设备：iPhone（iOS 27 及以上），已配对并开启开发者模式
- Bundle ID：`com.weixiaoxun.tomatotown`（请改成你自己的唯一 ID）
- 签名：Apple Development（本机 Personal Team）
- 描述文件：免费账号 7 天有效；到期前重新运行安装脚本续签
- 安装/启动命令：`./scripts/install_to_iphone.sh`
- 到期续签：在同一台 Mac、同一 Apple ID 下重新执行上面的命令即可；
  覆盖安装不会清除 App 内的书架、进度和缓存（不要先删除 App）。
- 注：`dist/` 下的 IPA、截图和签名材料只保存在本机，不随仓库发布。
- 2026-11-18：原 `com.weixiaoxun.fqapp` 被 Apple 判定不可注册（App ID 冲突），
  已改用 `com.weixiaoxun.tomatotown`；旧 App 的 shelf/history/read_time 数据已迁移，
  新描述文件有效到 11 月 25 日。旧 App 已卸载，仅保留新 App。

### 一键续签（本机）

免费账号 7 天到期后，不需要 Agent，也不需要重新配置签名：

1. **双击桌面上的「续签番茄小镇.app」**（实际应用在
   `~/Applications/续签番茄小镇.app`）；
2. 按提示先**解锁 iPhone 并保持亮屏**；
3. 点“开始续签”后，窗口会实时显示 6 个步骤、总体进度和构建输出；
   构建期间窗口保持响应，不再出现“未响应”；
4. 程序自动完成 `pod install`（需要时）、Release 构建、自动签名、安装，
   并尝试启动 App；完成后显示描述文件到期时间、信任步骤或“重试续签”；
5. 若停在“待信任”，主按钮是“我已信任，重新检查”，点击后只做启动检查，
   不会重新构建；也可随时打开 `~/Library/Logs/fqapp/` 看完整日志。

终端等价入口：

```bash
cd ~/fqapp-master-ios
./renew.command              # 双击友好的终端版
./scripts/renew_fqapp.sh     # 纯脚本
```

如果移动了项目目录，或想重建桌面 App：

```bash
./scripts/build_renew_app.sh
```

前置条件：Mac 醒着、Xcode 仍登录着同一个 Apple ID、iPhone 已连接
（USB 或同一 Wi-Fi）、iPhone 解锁。程序不依赖本 Agent，也不会上传签名材料。

重新打包用 `scripts/package_ios_artifacts.sh`。

未执行：真机后台播放、字体选择器、分享面板的人工点击验收。

## 8. 许可

原项目为 GPL-3.0，内容来自第三方公开接口。请仅用于个人学习研究，不要上架 App Store
或分发内容资源。

### 换 Bundle ID 后数据恢复

换 Bundle ID 会改变 iOS Keychain access group，旧 Hive 密钥可能读不到。
如果已有书架/浏览记录，先备份旧容器再换 ID；恢复步骤见 [RECOVERY.md](RECOVERY.md)。
