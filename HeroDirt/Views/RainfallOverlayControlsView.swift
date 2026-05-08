import UIKit

final class RainfallOverlayControlsView: UIView {

    // MARK: - State

    var isOverlayVisible: Bool = false {
        didSet { updateToggleAppearance() }
    }
    var selectedTimeframe: RainfallTimeframe = .threeDays {
        didSet { timeframePicker.selectedSegmentIndex = RainfallTimeframe.allCases.firstIndex(of: selectedTimeframe) ?? 2 }
    }
    var overlayOpacity: Double = 0.3 {
        didSet { opacitySlider.value = Float(overlayOpacity) }
    }
    var isLoading: Bool = false {
        didSet { updateToggleAppearance() }
    }

    // MARK: - Callbacks

    var onVisibilityChanged: ((Bool) -> Void)?
    var onTimeframeChanged: ((RainfallTimeframe) -> Void)?
    var onOpacityChanged: ((Double) -> Void)?

    // MARK: - Subviews

    private let toggleButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let toggleIcon = UIImageView()
    private let panelView = UIView()
    private let visibilitySwitch = UISwitch()
    private let timeframePicker = UISegmentedControl(items: RainfallTimeframe.allCases.map { $0.rawValue })
    private let opacitySlider = UISlider()

    private var isPanelExpanded = false

    // MARK: - Hit testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        if let result = super.hitTest(point, with: event) { return result }
        // The panel extends outside our bounds — forward hits to it manually.
        for subview in subviews.reversed() {
            let converted = subview.convert(point, from: self)
            if let result = subview.hitTest(converted, with: event) { return result }
        }
        return nil
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        setupToggleButton()
        setupPanel()
    }

    private func setupToggleButton() {
        toggleButton.accessibilityLabel = "Open rainfall overlay controls"
        toggleButton.addTarget(self, action: #selector(togglePanel), for: .touchUpInside)

        toggleIcon.contentMode = .scaleAspectFit
        toggleIcon.tintColor = .label
        toggleIcon.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        let buttonContent = UIView()
        buttonContent.isUserInteractionEnabled = false
        buttonContent.translatesAutoresizingMaskIntoConstraints = false
        buttonContent.addSubview(toggleIcon)
        buttonContent.addSubview(activityIndicator)

        toggleButton.addSubview(buttonContent)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleButton)

        let bg = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        bg.layer.cornerRadius = .cornerSmall
        bg.clipsToBounds = true
        bg.isUserInteractionEnabled = false
        bg.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.insertSubview(bg, at: 0)

        NSLayoutConstraint.activate([
            toggleButton.topAnchor.constraint(equalTo: topAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggleButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            toggleButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 44),
            toggleButton.heightAnchor.constraint(equalToConstant: 44),

            bg.topAnchor.constraint(equalTo: toggleButton.topAnchor),
            bg.bottomAnchor.constraint(equalTo: toggleButton.bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: toggleButton.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: toggleButton.trailingAnchor),

            buttonContent.centerXAnchor.constraint(equalTo: toggleButton.centerXAnchor),
            buttonContent.centerYAnchor.constraint(equalTo: toggleButton.centerYAnchor),
            buttonContent.widthAnchor.constraint(equalToConstant: 24),
            buttonContent.heightAnchor.constraint(equalToConstant: 24),

            toggleIcon.centerXAnchor.constraint(equalTo: buttonContent.centerXAnchor),
            toggleIcon.centerYAnchor.constraint(equalTo: buttonContent.centerYAnchor),
            toggleIcon.widthAnchor.constraint(equalToConstant: 20),
            toggleIcon.heightAnchor.constraint(equalToConstant: 20),

            activityIndicator.centerXAnchor.constraint(equalTo: buttonContent.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: buttonContent.centerYAnchor),
        ])

        updateToggleAppearance()
    }

    private func setupPanel() {
        panelView.backgroundColor = .clear
        panelView.alpha = 0
        panelView.isHidden = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panelView)

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        blur.layer.cornerRadius = .cornerMedium
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(blur)

        // Header
        let titleLabel = UILabel()
        titleLabel.text = "Rainfall overlay"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let spacer = UIView()
        let headerRow = UIStackView(arrangedSubviews: [titleLabel, spacer, closeButton])
        headerRow.axis = .horizontal
        headerRow.alignment = .center

        // Visibility toggle
        let switchLabel = UILabel()
        switchLabel.text = "Enabled"
        switchLabel.font = UIFont.preferredFont(forTextStyle: .body)
        visibilitySwitch.addTarget(self, action: #selector(visibilityChanged), for: .valueChanged)
        let switchRow = UIStackView(arrangedSubviews: [switchLabel, UIView(), visibilitySwitch])
        switchRow.axis = .horizontal
        switchRow.alignment = .center

        // Timeframe picker
        for (i, tf) in RainfallTimeframe.allCases.enumerated() {
            timeframePicker.setTitle(tf.rawValue, forSegmentAt: i)
        }
        timeframePicker.selectedSegmentIndex = RainfallTimeframe.allCases.firstIndex(of: selectedTimeframe) ?? 2
        timeframePicker.addTarget(self, action: #selector(timeframeChanged), for: .valueChanged)

        // Opacity slider
        let dotLight = UIImageView(image: UIImage(systemName: "circle.dotted"))
        dotLight.tintColor = .secondaryLabel
        dotLight.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        dotLight.setContentHuggingPriority(.required, for: .horizontal)

        let dotFull = UIImageView(image: UIImage(systemName: "circle.fill"))
        dotFull.tintColor = .secondaryLabel
        dotFull.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        dotFull.setContentHuggingPriority(.required, for: .horizontal)

        opacitySlider.minimumValue = 0.1
        opacitySlider.maximumValue = 0.9
        opacitySlider.value = Float(overlayOpacity)
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)

        let sliderRow = UIStackView(arrangedSubviews: [dotLight, opacitySlider, dotFull])
        sliderRow.axis = .horizontal
        sliderRow.spacing = 6
        sliderRow.alignment = .center

        // Legend
        let legend = RainfallLegendView()

        let contentStack = UIStackView(arrangedSubviews: [headerRow, switchRow, timeframePicker, sliderRow, legend])
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            panelView.topAnchor.constraint(equalTo: topAnchor),
            panelView.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -8),
            panelView.widthAnchor.constraint(equalToConstant: 260),

            blur.topAnchor.constraint(equalTo: panelView.topAnchor),
            blur.bottomAnchor.constraint(equalTo: panelView.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -12),

            panelView.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
    }

    // MARK: - Updates

    private func updateToggleAppearance() {
        if isLoading {
            activityIndicator.startAnimating()
            toggleIcon.alpha = 0
        } else {
            activityIndicator.stopAnimating()
            toggleIcon.alpha = 1
            let symbolName = isOverlayVisible ? "cloud.rain.fill" : "cloud.rain"
            toggleIcon.image = UIImage(systemName: symbolName)
        }
        toggleButton.tintColor = isPanelExpanded ? .systemBlue : .label
        visibilitySwitch.isOn = isOverlayVisible
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        isPanelExpanded.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if isPanelExpanded {
            panelView.isHidden = false
            panelView.transform = CGAffineTransform(translationX: 20, y: 0)
            UIView.animate(withDuration: 0.25) {
                self.panelView.alpha = 1
                self.panelView.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.25, animations: {
                self.panelView.alpha = 0
                self.panelView.transform = CGAffineTransform(translationX: 20, y: 0)
            }) { _ in
                self.panelView.isHidden = true
                self.panelView.transform = .identity
            }
        }
        updateToggleAppearance()
        toggleButton.accessibilityLabel = isPanelExpanded
            ? "Close rainfall overlay controls"
            : "Open rainfall overlay controls"
    }

    @objc private func closePanel() {
        guard isPanelExpanded else { return }
        togglePanel()
    }

    @objc private func visibilityChanged() {
        isOverlayVisible = visibilitySwitch.isOn
        onVisibilityChanged?(visibilitySwitch.isOn)
    }

    @objc private func timeframeChanged() {
        let tf = RainfallTimeframe.allCases[timeframePicker.selectedSegmentIndex]
        selectedTimeframe = tf
        onTimeframeChanged?(tf)
    }

    @objc private func opacityChanged() {
        overlayOpacity = Double(opacitySlider.value)
        onOpacityChanged?(overlayOpacity)
    }
}

// MARK: - Legend

private final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
}

final class RainfallLegendView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let mmLabel = UILabel()
        mmLabel.text = "mm"
        mmLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        mmLabel.textColor = .secondaryLabel

        let gradientView = GradientView()
        gradientView.layer.cornerRadius = 2
        gradientView.clipsToBounds = true

        let visible = Array(RainfallColorScale.stops.dropFirst())
        gradientView.gradientLayer.colors = visible.map { $0.color.cgColor }
        gradientView.gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientView.gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)

        let labelsRow = UIStackView()
        labelsRow.axis = .horizontal
        for stop in visible {
            let l = UILabel()
            l.text = stop.label
            l.font = UIFont.systemFont(ofSize: 8)
            l.textColor = .secondaryLabel
            labelsRow.addArrangedSubview(l)
            if stop.label != visible.last?.label {
                labelsRow.addArrangedSubview(makeFlexSpacer())
            }
        }

        let stack = UIStackView(arrangedSubviews: [mmLabel, gradientView, labelsRow])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func makeFlexSpacer() -> UIView {
        let v = UIView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
}
