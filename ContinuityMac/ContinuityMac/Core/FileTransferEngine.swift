import Foundation

/// Handles file transfers from Mac to Android device via ADB push.
final class FileTransferEngine: ObservableObject {
    static let shared = FileTransferEngine()
    private init() {}

    // MARK: - Published State

    @Published var isTransferring = false
    @Published var currentFileName: String? = nil
    @Published var transferProgress: Double = 0.0

    // MARK: - Transfer

    /// Sends a file to the Android device's Downloads folder.
    func sendFile(at url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isTransferring else {
            completion(.failure(TransferError.alreadyTransferring))
            return
        }

        DispatchQueue.main.async {
            self.isTransferring = true
            self.currentFileName = url.lastPathComponent
            self.transferProgress = 0.0
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let localPath = url.path
            let remotePath = "/sdcard/Download/\(url.lastPathComponent)"

            print("[FileTransfer] Pushing \(url.lastPathComponent) → \(remotePath)")

            let result = ADBBridge.shared.run(["push", localPath, remotePath])

            DispatchQueue.main.async {
                self.isTransferring = false
                self.currentFileName = nil
                self.transferProgress = 1.0

                if result.contains("error") || result.contains("failed") {
                    print("[FileTransfer] Failed: \(result)")
                    completion(.failure(TransferError.adbPushFailed(result)))
                } else {
                    print("[FileTransfer] Success: \(result)")
                    completion(.success(()))
                }
            }
        }
    }

    /// Sends multiple files sequentially.
    func sendFiles(at urls: [URL], completion: @escaping (Int, Int) -> Void) {
        var successCount = 0
        let group = DispatchGroup()

        for url in urls {
            group.enter()
            sendFile(at: url) { result in
                if case .success = result { successCount += 1 }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(successCount, urls.count)
        }
    }

    /// Pulls a file from the Android device to the Mac Downloads folder.
    func receiveFile(remotePath: String, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileName = (remotePath as NSString).lastPathComponent
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let localURL = downloadsURL.appendingPathComponent(fileName)

            let result = ADBBridge.shared.run(["pull", remotePath, localURL.path])

            DispatchQueue.main.async {
                if result.contains("error") || result.contains("failed") {
                    completion(.failure(TransferError.adbPullFailed(result)))
                } else {
                    completion(.success(localURL))
                }
            }
        }
    }
}

// MARK: - Errors

enum TransferError: LocalizedError {
    case alreadyTransferring
    case adbPushFailed(String)
    case adbPullFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyTransferring:
            return "A transfer is already in progress."
        case .adbPushFailed(let msg):
            return "Push failed: \(msg)"
        case .adbPullFailed(let msg):
            return "Pull failed: \(msg)"
        }
    }
}
