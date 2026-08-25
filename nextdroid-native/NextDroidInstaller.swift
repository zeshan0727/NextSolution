final class NextDroidInstaller: NSObject, ObservableObject, URLSessionDownloadDelegate {
    enum Phase: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = Int64(NextDroidVMConfiguration.expectedISOSize)

    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NextDroid Android Installer"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init() {
        super.init()
        phase = Self.isInstalled ? .ready : .idle
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 7_200
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    deinit {
        session?.invalidateAndCancel()
    }

    static var isInstalled: Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: NextDroidVMConfiguration.configURL.path),
              let attributes = try? manager.attributesOfItem(atPath: NextDroidVMConfiguration.isoURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.uint64Value == NextDroidVMConfiguration.expectedISOSize
    }

    func startDownload() {
        guard downloadTask == nil else { return }
        progress = 0
        downloadedBytes = 0
        expectedBytes = Int64(NextDroidVMConfiguration.expectedISOSize)
        phase = .downloading
        UIApplication.shared.isIdleTimerDisabled = true
        let request = URLRequest(
            url: NextDroidVMConfiguration.downloadURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 120
        )
        let task = session.downloadTask(with: request)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
        progress = 0
    }

    func retry() {
        phase = Self.isInstalled ? .ready : .idle
    }

    func reportStartFailure(_ message: String) {
        phase = .failed(message)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : Int64(NextDroidVMConfiguration.expectedISOSize)
        DispatchQueue.main.async { [weak self] in
            self?.downloadedBytes = totalBytesWritten
            self?.expectedBytes = expected
            self?.progress = min(1, Double(totalBytesWritten) / Double(expected))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.phase = .verifying
            self?.progress = 1
        }

        do {
            try verifyISO(at: location)
            DispatchQueue.main.async { [weak self] in
                self?.phase = .installing
            }
            try installISO(at: location)
            DispatchQueue.main.async { [weak self] in
                self?.downloadTask = nil
                self?.phase = .ready
                UIApplication.shared.isIdleTimerDisabled = false
            }
        } catch {
            try? FileManager.default.removeItem(at: NextDroidVMConfiguration.virtualMachineURL)
            DispatchQueue.main.async { [weak self] in
                self?.downloadTask = nil
                self?.phase = .failed(error.localizedDescription)
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        DispatchQueue.main.async { [weak self] in
            guard self?.downloadTask != nil else { return }
            self?.downloadTask = nil
            self?.phase = .failed(error.localizedDescription)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func verifyISO(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
              size.uint64Value == NextDroidVMConfiguration.expectedISOSize else {
            throw InstallerError.invalidFileSize
        }
        let digest = try sha256(of: url)
        guard digest == NextDroidVMConfiguration.expectedISOSHA256 else {
            throw InstallerError.invalidChecksum
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func installISO(at temporaryURL: URL) throws {
        let manager = FileManager.default
        let vmURL = NextDroidVMConfiguration.virtualMachineURL
        let dataURL = NextDroidVMConfiguration.dataDirectoryURL

        try? manager.removeItem(at: vmURL)
        try manager.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try manager.moveItem(at: temporaryURL, to: NextDroidVMConfiguration.isoURL)

        guard manager.createFile(atPath: NextDroidVMConfiguration.dataDiskURL.path, contents: nil) else {
            throw InstallerError.cannotCreateDataDisk
        }
        let disk = try FileHandle(forWritingTo: NextDroidVMConfiguration.dataDiskURL)
        try disk.truncate(atOffset: 16 * 1_024 * 1_024 * 1_024)
        try disk.close()

        let configData = try PropertyListSerialization.data(
            fromPropertyList: NextDroidVMConfiguration.propertyList,
            format: .xml,
            options: 0
        )
        try configData.write(to: NextDroidVMConfiguration.configURL, options: .atomic)
    }

    private enum InstallerError: LocalizedError {
        case invalidFileSize
        case invalidChecksum
        case cannotCreateDataDisk

        var errorDescription: String? {
            switch self {
            case .invalidFileSize:
                return "The Android download has an unexpected size. Please download it again."
            case .invalidChecksum:
                return "Android image verification failed. Please download it again."
            case .cannotCreateDataDisk:
                return "NextDroid could not create the persistent Android data disk."
            }
        }
    }
}
