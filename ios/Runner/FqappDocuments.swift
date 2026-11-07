import Flutter
import UIKit
import UniformTypeIdentifiers

/// Small wrapper around UIDocumentPickerViewController.
///
/// The picker keeps its delegate weakly, so the coordinator retains itself for
/// the lifetime of the presentation and drops the reference from the callback.
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
  private static var active: [DocumentPickerCoordinator] = []
  private var completion: (([URL]) -> Void)?
  private var exportCompletion: ((Bool) -> Void)?

  static func open(
    types: [UTType],
    asCopy: Bool = true,
    completion: @escaping ([URL]) -> Void
  ) {
    guard let presenter = UIApplication.shared.dshTopViewController else {
      completion([])
      return
    }
    let coordinator = DocumentPickerCoordinator()
    coordinator.completion = completion
    active.append(coordinator)
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
    picker.delegate = coordinator
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  static func export(url: URL, completion: @escaping (Bool) -> Void) {
    guard let presenter = UIApplication.shared.dshTopViewController else {
      completion(false)
      return
    }
    let coordinator = DocumentPickerCoordinator()
    coordinator.exportCompletion = completion
    active.append(coordinator)
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = coordinator
    presenter.present(picker, animated: true)
  }

  private func finish(_ urls: [URL]) {
    let callback = completion
    completion = nil
    DocumentPickerCoordinator.active.removeAll { $0 === self }
    callback?(urls)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    if let exportCompletion {
      self.exportCompletion = nil
      DocumentPickerCoordinator.active.removeAll { $0 === self }
      exportCompletion(true)
      return
    }
    finish(urls)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let exportCompletion {
      self.exportCompletion = nil
      DocumentPickerCoordinator.active.removeAll { $0 === self }
      exportCompletion(false)
      return
    }
    finish([])
  }
}

extension UIApplication {
  var dshTopViewController: UIViewController? {
    let scene = connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
      ?? scene?.windows.first?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
