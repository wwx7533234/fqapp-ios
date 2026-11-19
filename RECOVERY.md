# 换 Bundle ID 后书架 / 浏览记录丢失的恢复说明

> **先看结论**：本项目的本地数据是 **Hive + AES** 加密的。加密密钥存在 iOS
> Keychain 里，按 **Team ID + Bundle ID** 划分访问组。换 Bundle ID 后，新 App
> 看到的是新的 Keychain 组，读不到旧密钥；`EncryptedHive` 会把无法解密的
> `*_enc.hive` 当成空盒删除。数据本身可能还在旧容器/备份里，但必须同时找回
> **旧数据文件**和**旧 Keychain 密钥**，才能恢复。

这套流程不是“一个 IPA 帮所有人”的通用一键恢复。它需要旧 App 的数据容器或备份，
以及旧 App 仍留在设备 Keychain 中的密钥。请只在**你自己的设备和你自己的 Team**
上操作。

## 需要准备什么

1. 旧 App 的 `Documents` 数据（至少包含 `shelf_enc.hive`、`history_enc.hive`、
   `read_time_enc.hive` 等）。
2. 旧 App 的 Keychain 密钥（通常卸载 App 后仍会保留，但不保证）。
3. 旧 Bundle ID、旧 Team ID（Keychain access group 的前缀）。
4. 能重新签名安装一个**恢复构建**的 Xcode/Apple ID。

如果旧 App 已经删除且没有数据备份，或者 Keychain 被清理，**无法恢复**；
只有旧 Keychain 密钥而没有旧数据文件也不够。

## 第 1 步：在改 Bundle ID / 删除旧 App 之前备份数据

在旧 App 还安装着的时候运行：

```bash
./scripts/backup_ios_app_data.sh com.example.oldapp
```

脚本会用 `xcrun devicectl` 把旧 App 容器的 `Documents`（以及可读取的
`Library/Application Support`）复制到本机。备份目录会打印出来。

> 这个备份**不包含 Keychain 密钥**。密钥在设备的 Keychain 中，不在 App 沙盒文件里。

## 第 2 步：做一次恢复构建

以下用占位符表示你的真实信息：

```text
OLD_BUNDLE_ID   = com.example.oldapp
NEW_BUNDLE_ID   = com.example.newapp
TEAM_ID         = 你的 10 位 Team ID
OLD_GROUP       = TEAM_ID.OLD_BUNDLE_ID
NEW_GROUP       = TEAM_ID.NEW_BUNDLE_ID
```

### 2.1 添加 Keychain access group

在 Runner target 增加一个临时 entitlements 文件（例如
`ios/Runner/RunnerRecovery.entitlements`）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>keychain-access-groups</key>
  <array>
    <string>TEAM_ID.com.example.oldapp</string>
    <string>TEAM_ID.com.example.newapp</string>
  </array>
</dict>
</plist>
```

在 Runner 的 Build Settings 里设置：

```text
CODE_SIGN_ENTITLEMENTS = Runner/RunnerRecovery.entitlements
```

Team ID 可以从当前描述文件的
`Entitlements.application-identifier`（`TEAM_ID.com.example.newapp`）或
钥匙串里的 Apple Development 证书取得。免费 Personal Team 的开发描述文件
通常允许 `TEAM_ID.*` 的 Keychain 组；如果签名报 entitlement 错误，需要在
Xcode 的 Signing & Capabilities 中确认 Keychain Sharing 可用。

### 2.2 临时读取旧密钥并复制到新组

在 `lib/services/secure_key_provider.dart` 增加一个临时的存储实现：

```dart
class RecoverySecureKeyStorage implements SecureKeyStorage {
  const RecoverySecureKeyStorage();

  static const oldGroup = 'TEAM_ID.com.example.oldapp';
  static const _old = FlutterSecureStorage(
    iOptions: IOSOptions(groupId: oldGroup),
  );
  static const _new = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    final oldValue = await _old.read(key: key);
    if (oldValue != null) {
      await _new.write(key: key, value: oldValue);
      return oldValue;
    }
    return _new.read(key: key);
  }

  @override
  Future<void> write(String key, String value) =>
      _new.write(key: key, value: value);
}
```

把 `SecureKeyProvider` 的默认存储临时改为：

```dart
}) : _storage = storage ?? const RecoverySecureKeyStorage();
```

需要迁移的 Keychain 名称：

```text
fqapp_hive_encryption_key_v1
fqapp_device_pool_key_v1
```

### 2.3 安装恢复构建并恢复旧文件

1. 用新 Bundle ID 构建并安装恢复构建；
2. **先不要启动**新 App；
3. 把旧容器的 `Documents` 恢复到新容器：

```bash
./scripts/restore_ios_app_data.sh <第 1 步的备份目录> com.example.newapp
```

4. 启动 App。恢复构建会读取旧组的 Hive 密钥，复制到新组，并用它打开旧
   `*_enc.hive`；书架、历史、阅读时长应恢复；
5. 确认数据后，删除临时 entitlements 和 `RecoverySecureKeyStorage`，改回
   默认 `FlutterSecureKeyStorage`，重新构建。密钥已经复制到新组，普通构建
   可以继续使用。

> 不要用普通新构建直接打开旧加密盒子；`EncryptedHive` 在解密失败时会删除
> 该盒子。恢复构建和旧文件必须一起准备好。

## 第 3 步：预防

- **不要为了更新版本随意更换 Bundle ID**。换 ID 就是换 Keychain access group。
- 如果必须换，先备份旧容器，并保留旧 App 的 Keychain。
- 不要先删除旧 App 再验证新 App；确认书架、历史、阅读进度都正常后再删。
- 公开分享时使用中性占位 Bundle ID，不要把个人 Team ID 写进仓库。
- 签名 IPA 含描述文件/设备信息，**永远不要公开**；公开只发 unsigned IPA。
- 每个自签用户应使用自己的唯一 Bundle ID，并保持稳定。

## 相关源码

- `lib/services/secure_key_provider.dart`：Keychain 密钥的读取/创建
- `lib/services/encrypted_hive.dart`：加密盒打开、解密失败处理与旧明文迁移
- `scripts/backup_ios_app_data.sh`：按 App 容器备份 Documents
- `scripts/restore_ios_app_data.sh`：把 Documents 恢复到新容器

如果只是新安装，没有旧版数据，不需要执行以上恢复流程。
