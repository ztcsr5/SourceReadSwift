#if DEBUG
import SwiftUI
import UIKit
import WebKit

/// Explicit diagnostic launch only. Release builds and normal reader routes never enter this window.
@MainActor
enum ReaderZoomExperiment {
    private static var window: ReaderZoomExperimentWindow?

    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--reader-zoom-isolation"), window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let root = ReaderZoomExperimentRoot()
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        navigation.delegate = root
        root.trace.navigation = navigation
        let experiment = ReaderZoomExperimentWindow(windowScene: scene)
        experiment.frame = scene.screen.bounds
        experiment.rootViewController = navigation
        experiment.trace = root.trace
        window = experiment
        experiment.makeKeyAndVisible()
        let readout = ReaderZoomExperimentReadout()
        readout.trace = root.trace
        readout.frame = CGRect(x: 20, y: experiment.bounds.height - 90, width: 280, height: 44)
        readout.autoresizingMask = [.flexibleTopMargin]
        experiment.addSubview(readout)
    }
}

@MainActor
private final class ReaderZoomExperimentRoot: UIViewController, UINavigationControllerDelegate {
    let trace = ReaderZoomExperimentTrace()
    private let cover = UIButton(type: .system)
    private let condition = UISegmentedControl(items: ["A", "B", "C"])
    private var page: ReaderZoomExperimentPage?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        condition.selectedSegmentIndex = 0
        condition.accessibilityIdentifier = "experiment.condition"
        condition.frame = CGRect(x: 24, y: 64, width: 280, height: 44)
        view.addSubview(condition)
        cover.frame = CGRect(x: 24, y: 128, width: 152, height: 202)
        cover.backgroundColor = .systemTeal
        cover.setTitle("打开对照页", for: .normal)
        cover.accessibilityIdentifier = "experiment.open"
        cover.addTarget(self, action: #selector(openPage), for: .touchUpInside)
        view.addSubview(cover)
    }

    @objc private func openPage() {
        guard #available(iOS 18.0, *), navigationController?.topViewController === self else { return }
        let selected = ["A", "B", "C"][condition.selectedSegmentIndex]
        trace.reset(condition: selected)
        let page = ReaderZoomExperimentPage(trace: trace, condition: selected)
        self.page = page
        trace.page = page
        let options = UIViewController.Transition.ZoomOptions()
        options.interactiveDismissShouldBegin = { [weak self, weak page] context in
            guard let self, let page else { return false }
            let accepted = self.trace.isReady && page.presentedViewController == nil
                && context.location.x <= ReaderEdgeTapPolicy.reservedLeadingWidth
            self.trace.zoomDecision(location: context.location, velocity: context.velocity,
                                    willBegin: context.willBegin, accepted: accepted)
            return accepted
        }
        page.preferredTransition = .zoom(options: options) { [weak self] _ in
            guard let self else { return nil }
            self.trace.record("source", ["id": String(describing: ObjectIdentifier(self.cover)),
                "width": self.cover.bounds.width, "height": self.cover.bounds.height])
            return self.cover
        }
        navigationController?.pushViewController(page, animated: true)
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        trace.record("navigationWillShow", ["destination": viewController === self ? "root" : "page", "animated": animated])
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        trace.record("navigationDidShow", ["destination": viewController === self ? "root" : "page", "animated": animated])
        if viewController === self { page?.tearDownSurface(); page = nil }
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        trace.record("animationDelegate", ["operation": operation.rawValue, "returned": "nil-system-transition"])
        return nil
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        trace.record("interactionDelegate", ["returned": "nil-system-transition"])
        return nil
    }
}

@MainActor
private final class ReaderZoomExperimentPage: UIViewController {
    let trace: ReaderZoomExperimentTrace
    let condition: String
    private var web: WKWebView?
    private var renderer: WebScrollReaderView.Coordinator?
    private var isVisible = false
    private var hasContent = false

    init(trace: ReaderZoomExperimentTrace, condition: String) {
        self.trace = trace
        self.condition = condition
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Created by the experiment") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if condition == "A" {
            let paragraph = UILabel(frame: CGRect(x: 20, y: 130, width: view.bounds.width - 40, height: 80))
            paragraph.text = "普通 UIViewController 对照页"
            paragraph.numberOfLines = 0
            paragraph.autoresizingMask = [.flexibleWidth]
            view.addSubview(paragraph)
            hasContent = true
        } else {
            mountWebReader()
        }
        let arm = UIButton(type: .system)
        arm.setTitle("开始记录", for: .normal)
        arm.frame = CGRect(x: 160, y: 64, width: 120, height: 44)
        arm.accessibilityIdentifier = "experiment.arm"
        arm.addTarget(self, action: #selector(armAttempt), for: .touchUpInside)
        view.addSubview(arm)
        let close = UIButton(type: .system)
        close.setTitle("返回对照首页", for: .normal)
        close.frame = CGRect(x: 20, y: 64, width: 140, height: 44)
        close.accessibilityIdentifier = "experiment.close"
        close.addTarget(self, action: #selector(closePage), for: .touchUpInside)
        view.addSubview(close)
    }

    private func mountWebReader() {
        let surface = WebScrollReaderView(
            sections: [WebReaderSection(chapterIndex: 0, title: "真实正文对照",
                paragraphs: (0..<60).map { "第\($0)段：测试采用生产 WebKit 正文渲染器、真实排版和已保存的段落位置。" })],
            contentFingerprint: "zoom-experiment-prose", fontSize: 20, lineSpacing: 8,
            pagePadding: 20, letterSpacing: 0, paragraphSpacing: 12, paragraphIndent: 40,
            titleSpacing: 16, footerHeight: 12, topInset: 130, textColor: .label,
            highlightColor: .yellow, currentParagraphIndex: -1, scrollTarget: 30,
            scrollRequestKey: "zoom-experiment-cursor", animatedScrollDuration: 0,
            textSelectionEnabled: false, prioritizesSystemEdgeReturn: true, onVisibleParagraph: { _ in },
            onPresented: { [weak self] in self?.verifyViewport() })
        let renderer = surface.makeCoordinator()
        let web = renderer.makeWebView(initialView: surface)
        self.renderer = renderer
        self.web = web
        web.frame = view.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // C changes exactly this participation flag; layout, DOM, source and transition remain the same.
        web.scrollView.panGestureRecognizer.isEnabled = condition != "C"
        trace.webPan = web.scrollView.panGestureRecognizer
        view.addSubview(web)
    }

    private func verifyViewport() {
        web?.evaluateJavaScript("""
            (() => { const r = document.querySelector('p[data-flat="30"]')?.getBoundingClientRect();
            return {visible: !!r && r.bottom > 130 && r.top < innerHeight,
                    top: r?.top ?? -1, bottom: r?.bottom ?? -1, height: innerHeight, scrollY: scrollY}; })()
            """) { [weak self] value, error in
            guard let self else { return }
            let geometry: [String: Any] = (value as? [String: Any]) ?? [:]
            self.trace.record("initialViewport", geometry)
            self.hasContent = error == nil && (geometry["visible"] as? Bool) == true
            self.trace.isReady = self.hasContent && self.isVisible
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        trace.record("pageDidAppear")
        trace.isReady = hasContent
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        trace.record("pageWillDisappear", ["movingFromParent": isMovingFromParent])
        transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] context in
            self?.trace.transitionCompleted(cancelled: context.isCancelled)
        }
    }

    @objc private func armAttempt() { trace.arm() }
    @objc private func closePage() {
        trace.stop()
        navigationController?.popViewController(animated: false)
    }

    func tearDownSurface() {
        if let web { renderer?.tearDown(webView: web) }
        renderer = nil
        web = nil
    }
}

@MainActor
private final class ReaderZoomExperimentReadout: UIView {
    weak var trace: ReaderZoomExperimentTrace?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "experiment.evidence"
        accessibilityLabel = "独立实验记录"
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Created by the experiment") }
    override var accessibilityValue: String? {
        get { trace?.summary }
        set {}
    }
}
#endif
