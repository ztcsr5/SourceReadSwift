import UIKit

/// Keeps only a visible bitmap; the collection view owns page order and geometry.
final class ComicStripImageCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    private let zoom = ComicZoomScrollView(frame: .zero)
    private let zoomController = ComicPageZoomView.Coordinator()
    private let status = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private let refreshAddresses = UIButton(type: .system)
    var onTap: (() -> Void)?
    var onRetry: (() -> Void)?
    var onRefreshAddresses: (() -> Void)?
    var onZoomChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        zoom.delegate = zoomController
        zoomController.installGestures(on: zoom)
        zoomController.onFitTap = { [weak self] _ in self?.onTap?() }
        zoomController.onZoomChanged = { [weak self] in self?.onZoomChanged?($0) }
        contentView.addSubview(zoom)
        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(tappedBackground))
        backgroundTap.cancelsTouchesInView = false
        backgroundTap.delegate = self
        contentView.addGestureRecognizer(backgroundTap)
        status.axis = .vertical
        status.spacing = 12
        status.alignment = .center
        message.numberOfLines = 3
        message.textAlignment = .center
        message.textColor = .white
        message.font = .preferredFont(forTextStyle: .subheadline)
        spinner.color = .white
        retry.setTitle("重新加载这一页", for: .normal)
        retry.addTarget(self, action: #selector(retryPage), for: .touchUpInside)
        refreshAddresses.setTitle("重新获取图片地址", for: .normal)
        refreshAddresses.addTarget(self, action: #selector(refreshPageAddresses), for: .touchUpInside)
        for item in [spinner, message, retry, refreshAddresses] { status.addArrangedSubview(item) }
        for button in [retry, refreshAddresses] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.tintColor = .white
        }
        contentView.addSubview(status)
        status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            status.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        onZoomChanged?(false)
        onTap = nil
        onRetry = nil
        onRefreshAddresses = nil
        onZoomChanged = nil
        zoom.resetImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        zoom.frame = contentView.bounds
    }

    func configure(image: UIImage?, page: Int, failure: ComicImageFailure?, reducesMotion: Bool) {
        zoomController.reducesMotion = reducesMotion
        zoom.isHidden = image == nil
        status.isHidden = image != nil
        accessibilityIdentifier = "comic.page.\(page)"
        if let image {
            spinner.stopAnimating()
            zoom.setImage(image)
            zoom.artwork.accessibilityLabel = "第 \(page) 页漫画"
            zoom.artwork.accessibilityIdentifier = "comic.image.\(page)"
        } else {
            retry.isHidden = failure == nil
            refreshAddresses.isHidden = failure?.canRefreshAddress != true
            spinner.isHidden = failure != nil
            if failure == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
            message.text = failure.map { "第 \(page) 页：\($0.message)" } ?? "正在加载第 \(page) 页"
        }
    }

    @objc private func retryPage() { onRetry?() }
    @objc private func refreshPageAddresses() { onRefreshAddresses?() }
    @objc private func tappedBackground() { if zoom.isHidden { onTap?() } }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }
}

final class ComicStripFooterCell: UICollectionViewCell {
    private let button = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.tintColor = .white
        button.accessibilityIdentifier = "comic.chapterBoundary"
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(activate), for: .touchUpInside)
        contentView.addSubview(button)
    }

    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() { super.layoutSubviews(); button.frame = contentView.bounds.insetBy(dx: 16, dy: 8) }

    func configure(title: String, isEnabled: Bool, action: @escaping () -> Void) {
        button.setTitle(title, for: .normal)
        button.isEnabled = isEnabled
        self.action = action
    }

    @objc private func activate() { action?() }
}
