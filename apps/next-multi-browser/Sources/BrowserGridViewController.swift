import UIKit
import WebKit

private final class SharedBrowserSession {
    static let shared = SharedBrowserSession()
    let dataStore = WKWebsiteDataStore.default()
    let processPool = WKProcessPool()
    private init() {}
}

protocol BrowserPaneViewDelegate: AnyObject {
    func browserPaneRequestedFocus(_ pane: BrowserPaneView)
}

final class BrowserPaneView: UIView, UITextFieldDelegate, WKNavigationDelegate, WKUIDelegate {
    weak var delegate: BrowserPaneViewDelegate?
    let webView: WKWebView

    private let addressField = UITextField()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let autoRefreshButton = UIButton(type: .system)
    private let index: Int
    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var autoRefreshTimer: Timer?
    private(set) var autoRefreshInterval: TimeInterval?
    private var paneIsActive = true

    init(index: Int) {
        self.index = index

        let config = WKWebViewConfiguration()
        config.websiteDataStore = SharedBrowserSession.shared.dataStore
        config.processPool = SharedBrowserSession.shared.processPool
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)

        setupUI()
        observeWebView()
        showReadyPage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        autoRefreshTimer?.invalidate()
        progressObservation?.invalidate()
        urlObservation?.invalidate()
    }

    private func makeButton(_ symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        layer.masksToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        addressField.borderStyle = .roundedRect
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.keyboardType = .URL
        addressField.returnKeyType = .go
        addressField.clearButtonMode = .whileEditing
        addressField.placeholder = "Browser \(index) – URL or search"
        addressField.delegate = self
        addressField.font = .systemFont(ofSize: 11)
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let back = makeButton("chevron.left", action: #selector(goBack))
        let forward = makeButton("chevron.right", action: #selector(goForward))
        let reload = makeButton("arrow.clockwise", action: #selector(reloadPage))
        let focus = makeButton("arrow.up.left.and.arrow.down.right", action: #selector(focusPane))

        autoRefreshButton.setImage(UIImage(systemName: "timer"), for: .normal)
        autoRefreshButton.showsMenuAsPrimaryAction = true
        autoRefreshButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        autoRefreshButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        updateAutoRefreshMenu()

        let bar = UIStackView(arrangedSubviews: [back, forward, reload, autoRefreshButton, addressField, focus])
        bar.axis = .horizontal
        bar.spacing = 2
        bar.alignment = .center

        [bar, progress, webView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            bar.heightAnchor.constraint(equalToConstant: 34),

            progress.leadingAnchor.constraint(equalTo: leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor),
            progress.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 1),

            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: progress.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    private func observeWebView() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.progress.progress = Float(webView.estimatedProgress)
                self.progress.isHidden = webView.estimatedProgress >= 1.0
            }
        }

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let value = webView.url?.absoluteString, !value.hasPrefix("about:") {
                    self.addressField.text = value
                }
            }
        }
    }

    private func showReadyPage() {
        let html = """
        <html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='font-family:-apple-system;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;height:90vh;margin:0'>
        <div style='text-align:center'><div style='font-size:24px;font-weight:700'>Browser \(index)</div><div style='margin-top:8px;color:#aaa'>Ready</div></div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let candidate: String
        if trimmed.contains(" ") || (!trimmed.contains(".") && !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://")) {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            candidate = components?.url?.absoluteString ?? "https://www.google.com"
        } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard let url = URL(string: candidate) else { return }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func setPaneActive(_ active: Bool) {
        paneIsActive = active
        if active {
            restartAutoRefreshTimer()
        } else {
            autoRefreshTimer?.invalidate()
            autoRefreshTimer = nil
        }
    }

    func applyAutoRefresh(_ interval: TimeInterval?) {
        autoRefreshInterval = interval
        updateAutoRefreshMenu()
        restartAutoRefreshTimer()
    }

    private func updateAutoRefreshMenu() {
        let choices: [(String, TimeInterval?)] = [
            ("Off", nil),
            ("1 minute", 60),
            ("2 minutes", 120),
            ("3 minutes", 180),
            ("5 minutes", 300),
            ("10 minutes", 600)
        ]

        let actions = choices.map { title, interval in
            UIAction(title: title, state: intervalsMatch(interval, autoRefreshInterval) ? .on : .off) { [weak self] _ in
                self?.applyAutoRefresh(interval)
            }
        }
        autoRefreshButton.menu = UIMenu(title: "This Browser Auto Refresh", children: actions)
        autoRefreshButton.accessibilityLabel = autoRefreshInterval == nil ? "Auto Refresh Off" : "Auto Refresh On"
    }

    private func intervalsMatch(_ lhs: TimeInterval?, _ rhs: TimeInterval?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) < 0.5
        default: return false
        }
    }

    private func restartAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        guard paneIsActive, let interval = autoRefreshInterval else { return }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, self.paneIsActive, self.webView.url != nil else { return }
            self.webView.reload()
        }
        autoRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        load(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }

    @objc private func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func reloadPage() {
        webView.reload()
    }

    @objc private func focusPane() {
        delegate?.browserPaneRequestedFocus(self)
    }
}

final class BrowserGridViewController: UIViewController, BrowserPaneViewDelegate {
    private let scrollView = UIScrollView()
    private let rowsStack = UIStackView()
    private let countButton = UIButton(type: .system)
    private let globalRefreshButton = UIButton(type: .system)

    private var panes: [BrowserPaneView] = []
    private var browserCount = 2
    private var focusedPane: BrowserPaneView?
    private var focusedConstraints: [NSLayoutConstraint] = []
    private var globalRefreshInterval: TimeInterval? = {
        let value = UserDefaults.standard.double(forKey: "NextMultiBrowser.globalRefreshSeconds")
        return value > 0 ? value : nil
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Next Multi Browser"
        setupToolbar()
        setupGrid()
        applyBrowserCount(browserCount)
    }

    private func setupToolbar() {
        countButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        countButton.showsMenuAsPrimaryAction = true

        globalRefreshButton.setImage(UIImage(systemName: "timer"), for: .normal)
        globalRefreshButton.showsMenuAsPrimaryAction = true
        globalRefreshButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        globalRefreshButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        updateGlobalRefreshMenu()

        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "house"), style: .plain, target: self, action: #selector(homeAll)),
            UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise.circle"), style: .plain, target: self, action: #selector(reloadAll)),
            UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: self, action: #selector(loadSameURL))
        ]
        installNormalRightItems()
    }

    private func installNormalRightItems() {
        let vpnItem = UIBarButtonItem(image: UIImage(systemName: "shield.lefthalf.filled"), style: .plain, target: self, action: #selector(openVPN))
        vpnItem.accessibilityLabel = "Free VPN Servers"
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: countButton),
            UIBarButtonItem(customView: globalRefreshButton),
            vpnItem
        ]
    }

    private func installFocusRightItems() {
        let gridItem = UIBarButtonItem(title: "Grid", style: .done, target: self, action: #selector(exitFocus))
        let vpnItem = UIBarButtonItem(image: UIImage(systemName: "shield.lefthalf.filled"), style: .plain, target: self, action: #selector(openVPN))
        navigationItem.rightBarButtonItems = [gridItem, UIBarButtonItem(customView: globalRefreshButton), vpnItem]
    }

    private func makeCountMenu() -> UIMenu {
        let actions = (1...20).map { value in
            UIAction(title: "\(value) browser\(value == 1 ? "" : "s")", state: value == browserCount ? .on : .off) { [weak self] _ in
                self?.applyBrowserCount(value)
            }
        }
        return UIMenu(title: "Browser quantity", children: actions)
    }

    private func updateGlobalRefreshMenu() {
        let choices: [(String, TimeInterval?)] = [
            ("Off", nil),
            ("1 minute", 60),
            ("2 minutes", 120),
            ("3 minutes", 180),
            ("5 minutes", 300),
            ("10 minutes", 600)
        ]
        let actions = choices.map { title, interval in
            UIAction(title: title, state: intervalsMatch(interval, globalRefreshInterval) ? .on : .off) { [weak self] _ in
                self?.setGlobalRefresh(interval)
            }
        }
        let current = globalRefreshInterval.map { formatMinutes($0) } ?? "Off"
        globalRefreshButton.menu = UIMenu(title: "All Browsers • \(current)", children: actions)
        globalRefreshButton.accessibilityLabel = "Global Auto Refresh \(current)"
    }

    private func intervalsMatch(_ lhs: TimeInterval?, _ rhs: TimeInterval?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) < 0.5
        default: return false
        }
    }

    private func formatMinutes(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return "\(minutes)m"
    }

    private func setGlobalRefresh(_ interval: TimeInterval?) {
        globalRefreshInterval = interval
        if let interval {
            UserDefaults.standard.set(interval, forKey: "NextMultiBrowser.globalRefreshSeconds")
        } else {
            UserDefaults.standard.removeObject(forKey: "NextMultiBrowser.globalRefreshSeconds")
        }
        panes.forEach { $0.applyAutoRefresh(interval) }
        updateGlobalRefreshMenu()
    }

    private func setupGrid() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.axis = .vertical
        rowsStack.spacing = 8
        rowsStack.alignment = .fill

        scrollView.addSubview(rowsStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rowsStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            rowsStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 8),
            rowsStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -8),
            rowsStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private func applyBrowserCount(_ requestedCount: Int) {
        if focusedPane != nil {
            restoreFocusedPane()
        }

        browserCount = max(1, min(20, requestedCount))

        while panes.count < browserCount {
            let pane = BrowserPaneView(index: panes.count + 1)
            pane.delegate = self
            pane.applyAutoRefresh(globalRefreshInterval)
            panes.append(pane)
        }

        for (index, pane) in panes.enumerated() {
            pane.setPaneActive(index < browserCount)
        }

        rebuildRows()
        countButton.setTitle("\(browserCount) ▾", for: .normal)
        countButton.menu = makeCountMenu()
    }

    private func removeExistingRows() {
        for case let row as UIStackView in rowsStack.arrangedSubviews {
            for child in row.arrangedSubviews {
                row.removeArrangedSubview(child)
                child.removeFromSuperview()
            }
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
    }

    private func rebuildRows() {
        guard focusedPane == nil else { return }
        removeExistingRows()

        let visible = Array(panes.prefix(browserCount))
        let isLandscape = view.bounds.width > view.bounds.height
        let columns: Int
        if browserCount == 1 {
            columns = 1
        } else if traitCollection.horizontalSizeClass == .regular {
            columns = isLandscape ? 4 : 3
        } else {
            columns = isLandscape ? 3 : 2
        }

        let rowHeight: CGFloat = traitCollection.horizontalSizeClass == .regular ? 360 : 300
        var index = 0

        while index < visible.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

            for column in 0..<columns {
                if index + column < visible.count {
                    row.addArrangedSubview(visible[index + column])
                } else {
                    let spacer = UIView()
                    spacer.isHidden = true
                    row.addArrangedSubview(spacer)
                }
            }

            rowsStack.addArrangedSubview(row)
            index += columns
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, self.focusedPane == nil else { return }
            self.rebuildRows()
        }
    }

    func browserPaneRequestedFocus(_ pane: BrowserPaneView) {
        if focusedPane === pane {
            restoreFocusedPane()
            return
        }

        if focusedPane != nil {
            restoreFocusedPane()
        }

        if let stack = pane.superview as? UIStackView {
            stack.removeArrangedSubview(pane)
        }
        pane.removeFromSuperview()

        focusedPane = pane
        scrollView.isHidden = true
        pane.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pane)

        focusedConstraints = [
            pane.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pane.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(focusedConstraints)
        installFocusRightItems()
    }

    @objc private func exitFocus() {
        restoreFocusedPane()
    }

    private func restoreFocusedPane() {
        guard let pane = focusedPane else { return }
        NSLayoutConstraint.deactivate(focusedConstraints)
        focusedConstraints.removeAll()
        pane.removeFromSuperview()
        focusedPane = nil
        scrollView.isHidden = false
        installNormalRightItems()
        rebuildRows()
    }

    @objc private func homeAll() {
        panes.prefix(browserCount).forEach { $0.load("https://www.google.com") }
    }

    @objc private func reloadAll() {
        panes.prefix(browserCount).forEach { $0.webView.reload() }
    }

    @objc private func loadSameURL() {
        let alert = UIAlertController(title: "Load in all browsers", message: "Enter a URL or search term.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Load All", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            self.panes.prefix(self.browserCount).forEach { $0.load(text) }
        })
        present(alert, animated: true)
    }

    @objc private func openVPN() {
        let controller = VPNGateViewController()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }
}
