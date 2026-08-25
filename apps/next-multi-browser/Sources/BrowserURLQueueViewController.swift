import UIKit

final class BrowserURLQueueViewController: UIViewController, UITextViewDelegate {
    typealias LoadBatchHandler = ([String]) -> Void

    private enum DefaultsKey {
        static let urls = "NextMultiBrowser.importedURLQueue.values"
        static let cursor = "NextMultiBrowser.importedURLQueue.cursor"
    }

    private static let featureIdentifier = "NMB_IMPORTED_URL_QUEUE_MANUAL_BATCHES_115"

    private let onLoadBatch: LoadBatchHandler
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let pasteButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let loadBatchButton = UIButton(type: .system)
    private let restartButton = UIButton(type: .system)

    private var savedURLs: [String] = []
    private var cursor = 0

    init(onLoadBatch: @escaping LoadBatchHandler) {
        self.onLoadBatch = onLoadBatch
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Imported URL Queue"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(confirmClear)
        )
        setupUI()
        restoreState()
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false

        let intro = UILabel()
        intro.text = "Paste any number of site links, one per line. Each tap loads the next batch of up to 20 links into randomly selected browser panes. The queue stops after the final link."
        intro.font = .preferredFont(forTextStyle: .subheadline)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        let editorContainer = UIView()
        editorContainer.backgroundColor = .secondarySystemGroupedBackground
        editorContainer.layer.cornerRadius = 14
        editorContainer.layer.borderWidth = 1
        editorContainer.layer.borderColor = UIColor.separator.cgColor

        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.keyboardType = .URL
        textView.delegate = self
        textView.accessibilityIdentifier = Self.featureIdentifier

        placeholderLabel.text = "https://example.com/page-1\nhttps://example.com/page-2"
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0

        [textView, placeholderLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            editorContainer.addSubview($0)
        }

        NSLayoutConstraint.activate([
            editorContainer.heightAnchor.constraint(equalToConstant: 260),
            textView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: editorContainer.topAnchor, constant: 7),
            textView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor, constant: -7),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -5),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8)
        ])

        configureButton(
            pasteButton,
            title: "Paste Clipboard",
            symbol: "doc.on.clipboard",
            style: .tinted,
            action: #selector(pasteClipboard)
        )
        configureButton(
            saveButton,
            title: "Save Queue",
            symbol: "tray.and.arrow.down",
            style: .tinted,
            action: #selector(saveQueue)
        )
        let editorActions = UIStackView(arrangedSubviews: [pasteButton, saveButton])
        editorActions.axis = .horizontal
        editorActions.distribution = .fillEqually
        editorActions.spacing = 10

        let statusCard = UIView()
        statusCard.backgroundColor = .secondarySystemGroupedBackground
        statusCard.layer.cornerRadius = 14
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.numberOfLines = 0
        progressView.trackTintColor = .tertiarySystemFill
        [statusLabel, progressView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            statusCard.addSubview($0)
        }
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 15),
            progressView.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            progressView.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -16)
        ])

        configureButton(
            loadBatchButton,
            title: "Load Next Random Batch",
            symbol: "shuffle",
            style: .filled,
            action: #selector(loadNextBatch)
        )
        loadBatchButton.accessibilityHint = "Loads each queued link once and advances queue progress."

        configureButton(
            restartButton,
            title: "Restart Queue",
            symbol: "arrow.counterclockwise",
            style: .gray,
            action: #selector(restartQueue)
        )

        let footer = UILabel()
        footer.text = "Duplicate lines are removed when saved. Loading is manual, and no link repeats automatically. Your queue and progress remain saved after closing the app."
        footer.font = .preferredFont(forTextStyle: .footnote)
        footer.textColor = .secondaryLabel
        footer.numberOfLines = 0

        [intro, editorContainer, editorActions, statusCard, loadBatchButton, restartButton, footer].forEach {
            content.addArrangedSubview($0)
        }

        scrollView.addSubview(content)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private enum ButtonStyle {
        case filled
        case tinted
        case gray
    }

    private func configureButton(
        _ button: UIButton,
        title: String,
        symbol: String,
        style: ButtonStyle,
        action: Selector
    ) {
        var configuration: UIButton.Configuration
        switch style {
        case .filled:
            configuration = .filled()
        case .tinted:
            configuration = .tinted()
        case .gray:
            configuration = .gray()
        }
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        configuration.cornerStyle = .large
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    private func restoreState() {
        savedURLs = UserDefaults.standard.stringArray(forKey: DefaultsKey.urls) ?? []
        cursor = min(
            UserDefaults.standard.integer(forKey: DefaultsKey.cursor),
            savedURLs.count
        )
        textView.text = savedURLs.joined(separator: "\n")
        updateUI()
    }

    @discardableResult
    private func synchronizeQueueFromEditor() -> Bool {
        let cleaned = BrowserURLQueue.cleanedURLs(from: textView.text)
        guard !cleaned.isEmpty else {
            showMessage(
                title: "No Links Found",
                message: "Paste at least one site link, with one link on each line."
            )
            return false
        }
        if cleaned != savedURLs {
            savedURLs = cleaned
            cursor = 0
        }
        persistState()
        textView.text = savedURLs.joined(separator: "\n")
        updateUI()
        return true
    }

    private func persistState() {
        UserDefaults.standard.set(savedURLs, forKey: DefaultsKey.urls)
        UserDefaults.standard.set(cursor, forKey: DefaultsKey.cursor)
    }

    private func updateUI() {
        placeholderLabel.isHidden = !textView.text.isEmpty
        let total = savedURLs.count
        let remaining = max(0, total - cursor)
        if total == 0 {
            statusLabel.text = "No imported links"
            progressView.progress = 0
            loadBatchButton.isEnabled = false
            restartButton.isEnabled = false
        } else if remaining == 0 {
            statusLabel.text = "Queue complete • \(total) of \(total) links loaded"
            progressView.progress = 1
            loadBatchButton.isEnabled = false
            restartButton.isEnabled = true
        } else {
            let nextCount = min(remaining, BrowserURLQueue.batchLimit)
            statusLabel.text = "\(remaining) of \(total) links remaining • next batch: \(nextCount)"
            progressView.progress = Float(cursor) / Float(total)
            loadBatchButton.isEnabled = true
            restartButton.isEnabled = cursor > 0
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        let cleaned = BrowserURLQueue.cleanedURLs(from: textView.text)
        if cleaned != savedURLs {
            statusLabel.text = cleaned.isEmpty
                ? "No imported links"
                : "\(cleaned.count) unsaved link\(cleaned.count == 1 ? "" : "s") • progress will restart"
            progressView.progress = 0
            loadBatchButton.isEnabled = !cleaned.isEmpty
            restartButton.isEnabled = false
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func pasteClipboard() {
        guard let value = UIPasteboard.general.string, !value.isEmpty else {
            showMessage(title: "Clipboard Empty", message: "Copy your site links, then try Paste Clipboard again.")
            return
        }
        textView.text = value
        textViewDidChange(textView)
    }

    @objc private func saveQueue() {
        guard synchronizeQueueFromEditor() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @objc private func loadNextBatch() {
        guard synchronizeQueueFromEditor() else { return }
        guard let batch = BrowserURLQueue.nextBatch(from: savedURLs, cursor: cursor) else {
            showMessage(
                title: "Queue Complete",
                message: "Restart the queue if you want to run the saved links again."
            )
            return
        }
        cursor = batch.nextCursor
        persistState()
        updateUI()
        let urls = batch.urls
        dismiss(animated: true) { [onLoadBatch] in
            onLoadBatch(urls)
        }
    }

    @objc private func restartQueue() {
        guard !savedURLs.isEmpty else { return }
        cursor = 0
        persistState()
        updateUI()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @objc private func confirmClear() {
        guard !savedURLs.isEmpty || !textView.text.isEmpty else { return }
        let alert = UIAlertController(
            title: "Clear URL Queue?",
            message: "This removes the saved links and queue progress.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.savedURLs = []
            self.cursor = 0
            self.textView.text = ""
            UserDefaults.standard.removeObject(forKey: DefaultsKey.urls)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.cursor)
            self.updateUI()
        })
        present(alert, animated: true)
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
