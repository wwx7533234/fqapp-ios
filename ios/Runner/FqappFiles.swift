import CoreFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

/// File-facing channels used by the reader/library:
/// `fqapp/local_books`, `fqapp/library_backup` and `fqapp/downloads`.
final class FilesHost: NSObject {
  private let localBooks: FlutterMethodChannel
  private let backup: FlutterMethodChannel
  private let downloads: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    localBooks = FlutterMethodChannel(name: "fqapp/local_books", binaryMessenger: messenger)
    backup = FlutterMethodChannel(name: "fqapp/library_backup", binaryMessenger: messenger)
    downloads = FlutterMethodChannel(name: "fqapp/downloads", binaryMessenger: messenger)
    super.init()
    localBooks.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickBookFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pickBookFile(result: result)
    }
    backup.setMethodCallHandler { [weak self] call, result in
      self?.handleBackup(call, result: result)
    }
    downloads.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.saveText(call, result: result)
    }
  }

  // MARK: - Local books

  private func pickBookFile(result: @escaping FlutterResult) {
    var types: [UTType] = [.plainText]
    if let epub = UTType(filenameExtension: "epub") {
      types.append(epub)
    }
    DocumentPickerCoordinator.open(types: types) { urls in
      guard let url = urls.first else {
        result(nil)
        return
      }
      let name = url.lastPathComponent
      guard let data = try? Data(contentsOf: url) else {
        result(FlutterError(code: "read_failed", message: "无法读取所选文件", details: nil))
        return
      }
      let isTxt = name.lowercased().hasSuffix(".txt")
      if isTxt {
        guard let text = Self.decodeText(data) else {
          result(FlutterError(code: "decode_failed", message: "无法识别 TXT 编码", details: nil))
          return
        }
        result([
          "name": name,
          "text": text,
          "byteLength": data.count,
        ])
      } else {
        result([
          "name": name,
          "bytes": FlutterStandardTypedData(bytes: data),
          "byteLength": data.count,
        ])
      }
    }
  }

  private static func decodeText(_ data: Data) -> String? {
    if let text = String(data: data, encoding: .utf8) {
      return text
    }
    let gb18030 = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
      )
    )
    if let text = String(data: data, encoding: gb18030) {
      return text
    }
    return String(data: data, encoding: .utf16)
  }

  // MARK: - Library backup

  private func handleBackup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "saveBackup":
      let name = args["name"] as? String ?? "fqapp-backup.json"
      let data = (args["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "fqapp-backup-\(UUID().uuidString)",
        isDirectory: true
      )
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        DocumentPickerCoordinator.export(url: file) { saved in
          result(saved)
        }
      } catch {
        result(FlutterError(code: "write_failed", message: "无法写入备份文件", details: nil))
      }
    case "openBackup":
      DocumentPickerCoordinator.open(types: [.json]) { urls in
        guard let url = urls.first else {
          result(nil)
          return
        }
        guard let data = try? Data(contentsOf: url) else {
          result(FlutterError(code: "read_failed", message: "无法读取备份文件", details: nil))
          return
        }
        result(FlutterStandardTypedData(bytes: data))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - TXT export

  private func saveText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let name = Self.sanitize(args["fileName"] as? String ?? "book.txt")
    let text = args["text"] as? String ?? ""
    do {
      let documents = try FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = documents.appendingPathComponent("Downloads", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent(name)
      try text.data(using: .utf8)?.write(to: file, options: .atomic)
      result([
        "path": file.path,
        "public": false,
      ])
    } catch {
      result(FlutterError(code: "write_failed", message: "无法写入应用文稿目录", details: nil))
    }
  }

  private static func sanitize(_ raw: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
    let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "book.txt" : cleaned
  }
}
