import UIKit
import WebKit

protocol BrowserPaneViewDelegate: AnyObject {
    func browserPaneRequestedFocus(_ pane: BrowserPaneView)
}

final class BrowserPaneView: UIView, UITextFieldDelegate, WKNavigationDelegate {
    weak var delegate: BrowserPaneViewDelegate?
    let webView: WKWebView
    private let addressField = UITextField()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var index: Int

    init(index: Int) {
        self.index = index
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) { config.mediaTypesRequiringUserActionForPlayback = [] }
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        setupUI()
        observeWebView()
        load("https://www.google.com")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeButton(_ symbol: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol), for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        return b
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.masksToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        addressField.borderStyle = .roundedRect
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.keyboardType = .URL
        addressField.returnKeyType = .go
        addressField.placeholder = "Browser \(index) – URL or search"
        addressField.delegate = self
        addressField.font = .systemFont(ofSize: 12)

        let back = makeButton("chevron.left", action: #selector(goBack))
        let forward = makeButton("chevron.right", action: #selector(goForward))
        let reload = makeButton("arrow.clockwise", action: #selector(reloadPage))
        let focus = makeButton("arrow.up.left.and.arrow.down.right", action: #selector(focusPane))

        let bar = UIStackView(arrangedSubviews: [back, forward, reload, addressField, focus])
        bar.axis = .horizontal
        bar.spacing = 4
        bar.alignment = .center

        [bar, progress, webView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            bar.heightAnchor.constraint(equalToConstant: 36),
            progress.leadingAnchor.constraint(equalTo: leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor),
            progress.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: progress.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    private func observeWebView() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
            DispatchQueue.main.async {
                self?.progress.progress = Float(web.estimatedProgress)
                self?.progress.isHidden = web.estimatedProgress >= 1.0
            }
        }
        titleObservation = webView.observe(\.url, options: [.new]) { [weak self] web, _ in
            DispatchQueue.main.async { self?.addressField.text = web.url?.absoluteString }
        }
    }

    func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let candidate: String
        if trimmed.contains(" ") || (!trimmed.contains(".") && !trimmed.hasPrefix("http")) {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            candidate = "https://www.google.com/search?q=\(encoded)"
        } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }
        guard let url = URL(string: candidate) else { return }
        webView.load(URLRequest(url: url))
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        load(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    @objc private func goBack() { if webView.canGoBack { webView.goBack() } }
    @objc private func goForward() { if webView.canGoForward { webView.goForward() } }
    @objc private func reloadPage() { webView.reload() }
    @objc private func focusPane() { delegate?.browserPaneRequestedFocus(self) }
}

final class BrowserGridViewController: UIViewController, BrowserPaneViewDelegate {
    private let scrollView = UIScrollView()
    private let rowsStack = UIStackView()
    private var panes: [BrowserPaneView] = []
    private var browserCount = 4
    private var focusedPane: BrowserPaneView?
    private weak var focusedRow: UIStackView?
    private var focusedIndex = 0
    private var focusedConstraints: [NSLayoutConstraint] = []
    private let countButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Next Multi Browser"
        navigationItem.largeTitleDisplayMode = .never
        setupToolbar()
        setupGrid()
        applyBrowserCount(browserCount)
    }

    private func setupToolbar() {
        countButton.setTitle("4 Browsers ▾", for: .normal)
        countButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        countButton.menu = makeCountMenu()
        countButton.showsMenuAsPrimaryAction = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: countButton)

        let homeAll = UIBarButtonItem(image: UIImage(systemName: "house"), style: .plain, target: self, action: #selector(homeAll))
        let reloadAll = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise.circle"), style: .plain, target: self, action: #selector(reloadAll))
        let sameURL = UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: self, action: #selector(loadSameURL))
        navigationItem.leftBarButtonItems = [homeAll, reloadAll, sameURL]
    }

    private func makeCountMenu() -> UIMenu {
        let values = [1,2,3,4,6,8,10,12,16,20]
        let actions = values.map { value in
            UIAction(title: "\(value) browsers", state: value == browserCount ? .on : .off) { [weak self] _ in
                self?.applyBrowserCount(value)
            }
        }
        return UIMenu(title: "Browser quantity", children: actions)
    }

    private func setupGrid() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
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

    private func applyBrowserCount(_ newCount: Int) {
        if focusedPane != nil { restoreFocusedPane() }
        browserCount = max(1, min(20, newCount))
        while panes.count < browserCount {
            let pane = BrowserPaneView(index: panes.count + 1)
            pane.delegate = self
            panes.append(pane)
        }
        rebuildRows()
        countButton.setTitle("\(browserCount) Browsers ▾", for: .normal)
        countButton.menu = makeCountMenu()
    }

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { row in
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        let visible = Array(panes.prefix(browserCount))
        let columns = traitCollection.horizontalSizeClass == .regular ? 3 : (view.bounds.width > view.bounds.height ? 3 : 2)
        var i = 0
        while i < visible.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            for j in 0..<columns {
                if i + j < visible.count {
                    let pane = visible[i + j]
                    row.addArrangedSubview(pane)
                    pane.heightAnchor.constraint(equalToConstant: traitCollection.horizontalSizeClass == .regular ? 360 : 300).isActive = true
                } else {
                    let spacer = UIView(); spacer.isHidden = true; row.addArrangedSubview(spacer)
                }
            }
            rowsStack.addArrangedSubview(row)
            i += columns
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.rebuildRows() }
    }

    func browserPaneRequestedFocus(_ pane: BrowserPaneView) {
        if focusedPane === pane { restoreFocusedPane(); return }
        if focusedPane != nil { restoreFocusedPane() }
        guard let row = pane.superview as? UIStackView, let idx = row.arrangedSubviews.firstIndex(of: pane) else { return }
        focusedPane = pane
        focusedRow = row
        focusedIndex = idx
        row.removeArrangedSubview(pane)
        pane.removeFromSuperview()
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Grid", style: .done, target: self, action: #selector(exitFocus))
    }

    @objc private func exitFocus() { restoreFocusedPane() }

    private func restoreFocusedPane() {
        guard let pane = focusedPane, let row = focusedRow else { return }
        NSLayoutConstraint.deactivate(focusedConstraints)
        focusedConstraints.removeAll()
        pane.removeFromSuperview()
        row.insertArrangedSubview(pane, at: min(focusedIndex, row.arrangedSubviews.count))
        scrollView.isHidden = false
        focusedPane = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: countButton)
    }

    @objc private func homeAll() {
        panes.prefix(browserCount).forEach { $0.load("https://www.google.com") }
    }

    @objc private func reloadAll() {
        panes.prefix(browserCount).forEach { $0.webView.reload() }
    }

    @objc private func loadSameURL() {
        let alert = UIAlertController(title: "Load URL in all browsers", message: "Enter one URL or search term.", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "https://example.com"; field.keyboardType = .URL; field.autocapitalizationType = .none }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Load All", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            self.panes.prefix(self.browserCount).forEach { $0.load(text) }
        })
        present(alert, animated: true)
    }
}
