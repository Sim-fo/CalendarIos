import SwiftUI
import UIKit

// MARK: - Weekly Gesture Coordinator (Android parity + UIKit multitouch protection)

enum WeeklyGestureMode: Equatable {
    case idle
    case singleTouchPending
    case zoomExclusive
    case eventDrag
    case slotSelection
}

enum WeeklyGestureOwner: Equatable {
    case none
    case root
    case emptySlot
    case eventCard
    case header
}

@MainActor
final class WeeklyGestureCoordinator {
    private(set) var mode: WeeklyGestureMode = .idle
    private(set) var owner: WeeklyGestureOwner = .none
    private(set) var activeTouchCount: Int = 0
    private var zoomCooldownUntil: CFTimeInterval = 0

    /// Grace window after all fingers lift from a multitouch/pinch session so trailing
    /// taps or staggered finger lifts never trigger slot creation or header/event taps.
    let postZoomCooldownSeconds: CFTimeInterval

    private let singleTouchRecognizers = NSHashTable<UIGestureRecognizer>.weakObjects()
    private weak var horizontalScrollView: UIScrollView?
    private weak var verticalScrollView: UIScrollView?

    var onEnterZoomExclusive: (() -> Void)?
    var onSessionReset: (() -> Void)?

    private let nowProvider: () -> CFTimeInterval

    init(
        postZoomCooldownSeconds: CFTimeInterval = 0.22,
        nowProvider: @escaping () -> CFTimeInterval = { CACurrentMediaTime() }
    ) {
        self.postZoomCooldownSeconds = postZoomCooldownSeconds
        self.nowProvider = nowProvider
    }

    var isZoomExclusive: Bool {
        mode == .zoomExclusive
    }

    var isInPostZoomCooldown: Bool {
        nowProvider() < zoomCooldownUntil
    }

    /// Mirrors Android `WeeklyGestureCoordinator.canHandleSingleTouch()` plus
    /// touch-count and post-pinch cooldown guards.
    var canHandleSingleTouch: Bool {
        !isZoomExclusive && activeTouchCount <= 1 && !isInPostZoomCooldown
    }

    var isBlockingScroll: Bool {
        isZoomExclusive || mode == .slotSelection || mode == .eventDrag
    }

    func registerSingleTouchRecognizer(_ recognizer: UIGestureRecognizer) {
        singleTouchRecognizers.add(recognizer)
    }

    func bindScrollViews(horizontal: UIScrollView?, vertical: UIScrollView?) {
        if let horizontal {
            horizontalScrollView = horizontal
        }
        if let vertical {
            verticalScrollView = vertical
        }
        syncScrollEnabled()
    }

    func updateActiveTouchCount(_ count: Int) {
        let clamped = max(0, count)
        activeTouchCount = clamped

        if clamped >= 2 {
            enterZoomExclusive()
            return
        }

        if clamped == 1 {
            if mode == .idle {
                mode = .singleTouchPending
                owner = .root
            }
            // Note: if already in `.zoomExclusive`, STAY in `.zoomExclusive`
            // until ALL fingers lift (clamped == 0), matching Android!
            return
        }

        // clamped == 0: all fingers lifted off the screen
        endAllTouches()
    }

    func enterZoomExclusive() {
        let wasZoomExclusive = isZoomExclusive
        mode = .zoomExclusive
        owner = .root
        cancelAllSingleTouchRecognizers()
        syncScrollEnabled()
        if !wasZoomExclusive {
            onEnterZoomExclusive?()
        }
    }

    func tryStartSlotSelection() -> Bool {
        guard canHandleSingleTouch, mode == .idle || mode == .singleTouchPending else {
            return false
        }
        mode = .slotSelection
        owner = .emptySlot
        syncScrollEnabled()
        return true
    }

    func tryStartEventDrag() -> Bool {
        guard canHandleSingleTouch, mode == .idle || mode == .singleTouchPending else {
            return false
        }
        mode = .eventDrag
        owner = .eventCard
        syncScrollEnabled()
        return true
    }

    func finishInteraction(owner: WeeklyGestureOwner) {
        if self.owner == owner && !isZoomExclusive {
            mode = activeTouchCount > 0 ? .singleTouchPending : .idle
            self.owner = activeTouchCount > 0 ? .root : .none
            syncScrollEnabled()
        }
    }

    func endAllTouches() {
        let wasZoomExclusive = isZoomExclusive
        activeTouchCount = 0

        if wasZoomExclusive {
            zoomCooldownUntil = nowProvider() + postZoomCooldownSeconds
            mode = .idle
            owner = .none
            syncScrollEnabled()
            onSessionReset?()
            return
        }

        // If an active single-touch interaction (.slotSelection or .eventDrag) is in progress,
        // do NOT reset `mode` synchronously here: MultiTouchObserver sits on UIWindow and receives
        // `touchesEnded` BEFORE the child UILongPress/UIPanGestureRecognizer receives `.ended`.
        // Let the child recognizer commit and call `finishInteraction(owner:)`, with an async
        // safety cleanup in case the gesture ended without invoking its target.
        if mode == .slotSelection || mode == .eventDrag {
            let expectedOwner = owner
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeTouchCount == 0, self.owner == expectedOwner else { return }
                self.mode = .idle
                self.owner = .none
                self.syncScrollEnabled()
            }
            return
        }

        mode = .idle
        owner = .none
        syncScrollEnabled()
    }

    func forceReset() {
        activeTouchCount = 0
        zoomCooldownUntil = 0
        mode = .idle
        owner = .none
        cancelAllSingleTouchRecognizers()
        syncScrollEnabled()
        onSessionReset?()
    }

    private func cancelAllSingleTouchRecognizers() {
        for recognizer in singleTouchRecognizers.allObjects {
            if recognizer.isEnabled {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
        }
    }

    private func syncScrollEnabled() {
        let shouldAllowScroll = !isBlockingScroll
        if let horizontalScrollView, horizontalScrollView.isScrollEnabled != shouldAllowScroll {
            horizontalScrollView.isScrollEnabled = shouldAllowScroll
        }
        if let verticalScrollView, verticalScrollView.isScrollEnabled != shouldAllowScroll {
            verticalScrollView.isScrollEnabled = shouldAllowScroll
        }
    }
}

// MARK: - Single-Touch Long Press Capture (Empty Timeline Slot)

struct LongPressCaptureView: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let gestureCoordinator: WeeklyGestureCoordinator
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            gestureCoordinator: gestureCoordinator,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = minimumDuration
        recognizer.numberOfTouchesRequired = 1
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        gestureCoordinator.registerSingleTouchRecognizer(recognizer)
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.gestureCoordinator = gestureCoordinator
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled

        guard let recognizer = uiView.gestureRecognizers?.first as? UILongPressGestureRecognizer else {
            return
        }
        if recognizer.minimumPressDuration != minimumDuration {
            recognizer.minimumPressDuration = minimumDuration
        }
        gestureCoordinator.registerSingleTouchRecognizer(recognizer)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gestureCoordinator: WeeklyGestureCoordinator
        var onBegan: (CGPoint) -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: (CGPoint) -> Void
        var onCancelled: () -> Void
        private var didOwnSlotSelection = false

        init(
            gestureCoordinator: WeeklyGestureCoordinator,
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping (CGPoint) -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.gestureCoordinator = gestureCoordinator
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer.numberOfTouches == 1 else { return false }
            return gestureCoordinator.canHandleSingleTouch
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            gestureCoordinator.canHandleSingleTouch
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)

            switch recognizer.state {
            case .began:
                guard recognizer.numberOfTouches == 1,
                      gestureCoordinator.tryStartSlotSelection() else {
                    didOwnSlotSelection = false
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                didOwnSlotSelection = true
                onBegan(point)

            case .changed:
                guard didOwnSlotSelection else { return }
                if recognizer.numberOfTouches != 1 || gestureCoordinator.isZoomExclusive {
                    cancelSelection()
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                onChanged(point)

            case .ended:
                guard didOwnSlotSelection else { return }
                didOwnSlotSelection = false
                if gestureCoordinator.isZoomExclusive || gestureCoordinator.mode != .slotSelection {
                    onCancelled()
                } else {
                    onEnded(point)
                }
                gestureCoordinator.finishInteraction(owner: .emptySlot)

            case .cancelled, .failed:
                cancelSelection()

            default:
                break
            }
        }

        private func cancelSelection() {
            guard didOwnSlotSelection else { return }
            didOwnSlotSelection = false
            onCancelled()
            gestureCoordinator.finishInteraction(owner: .emptySlot)
        }
    }
}

// MARK: - Single-Touch Event Card Capture (Tap + Long-Press Move)

struct EventTouchCaptureView: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let gestureCoordinator: WeeklyGestureCoordinator
    let onTap: () -> Void
    let onMoveBegan: () -> Void
    let onMoveChanged: (CGPoint) -> Void
    let onMoveEnded: () -> Void
    let onMoveCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            gestureCoordinator: gestureCoordinator,
            onTap: onTap,
            onMoveBegan: onMoveBegan,
            onMoveChanged: onMoveChanged,
            onMoveEnded: onMoveEnded,
            onMoveCancelled: onMoveCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.delegate = context.coordinator

        let longPressRecognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = minimumDuration
        longPressRecognizer.numberOfTouchesRequired = 1
        longPressRecognizer.allowableMovement = 12
        longPressRecognizer.cancelsTouchesInView = true
        longPressRecognizer.delegate = context.coordinator

        tapRecognizer.require(toFail: longPressRecognizer)

        gestureCoordinator.registerSingleTouchRecognizer(tapRecognizer)
        gestureCoordinator.registerSingleTouchRecognizer(longPressRecognizer)

        view.addGestureRecognizer(tapRecognizer)
        view.addGestureRecognizer(longPressRecognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.gestureCoordinator = gestureCoordinator
        context.coordinator.onTap = onTap
        context.coordinator.onMoveBegan = onMoveBegan
        context.coordinator.onMoveChanged = onMoveChanged
        context.coordinator.onMoveEnded = onMoveEnded
        context.coordinator.onMoveCancelled = onMoveCancelled

        if let recognizers = uiView.gestureRecognizers {
            for recognizer in recognizers {
                gestureCoordinator.registerSingleTouchRecognizer(recognizer)
                if let longPress = recognizer as? UILongPressGestureRecognizer,
                   longPress.minimumPressDuration != minimumDuration {
                    longPress.minimumPressDuration = minimumDuration
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gestureCoordinator: WeeklyGestureCoordinator
        var onTap: () -> Void
        var onMoveBegan: () -> Void
        var onMoveChanged: (CGPoint) -> Void
        var onMoveEnded: () -> Void
        var onMoveCancelled: () -> Void
        private var initialWindowPoint: CGPoint?
        private var didOwnEventDrag = false

        init(
            gestureCoordinator: WeeklyGestureCoordinator,
            onTap: @escaping () -> Void,
            onMoveBegan: @escaping () -> Void,
            onMoveChanged: @escaping (CGPoint) -> Void,
            onMoveEnded: @escaping () -> Void,
            onMoveCancelled: @escaping () -> Void
        ) {
            self.gestureCoordinator = gestureCoordinator
            self.onTap = onTap
            self.onMoveBegan = onMoveBegan
            self.onMoveChanged = onMoveChanged
            self.onMoveEnded = onMoveEnded
            self.onMoveCancelled = onMoveCancelled
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer.numberOfTouches <= 1 else { return false }
            return gestureCoordinator.canHandleSingleTouch
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            gestureCoordinator.canHandleSingleTouch
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  gestureCoordinator.canHandleSingleTouch else {
                return
            }
            onTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                guard recognizer.numberOfTouches == 1,
                      gestureCoordinator.tryStartEventDrag() else {
                    didOwnEventDrag = false
                    initialWindowPoint = nil
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                didOwnEventDrag = true
                initialWindowPoint = point
                onMoveBegan()

            case .changed:
                guard didOwnEventDrag else { return }
                if recognizer.numberOfTouches != 1 || gestureCoordinator.isZoomExclusive {
                    cancelMove()
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                let translation = CGPoint(
                    x: point.x - (initialWindowPoint?.x ?? point.x),
                    y: point.y - (initialWindowPoint?.y ?? point.y)
                )
                onMoveChanged(translation)

            case .ended:
                guard didOwnEventDrag else { return }
                didOwnEventDrag = false
                initialWindowPoint = nil
                if gestureCoordinator.isZoomExclusive || gestureCoordinator.mode != .eventDrag {
                    onMoveCancelled()
                } else {
                    onMoveEnded()
                }
                gestureCoordinator.finishInteraction(owner: .eventCard)

            case .cancelled, .failed:
                cancelMove()

            default:
                break
            }
        }

        private func cancelMove() {
            guard didOwnEventDrag else { return }
            didOwnEventDrag = false
            initialWindowPoint = nil
            onMoveCancelled()
            gestureCoordinator.finishInteraction(owner: .eventCard)
        }
    }
}

// MARK: - Single-Touch Resize Handle Capture

struct PanCaptureView: UIViewRepresentable {
    let gestureCoordinator: WeeklyGestureCoordinator
    let onBegan: () -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            gestureCoordinator: gestureCoordinator,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        gestureCoordinator.registerSingleTouchRecognizer(recognizer)
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.gestureCoordinator = gestureCoordinator
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled

        if let recognizer = uiView.gestureRecognizers?.first {
            gestureCoordinator.registerSingleTouchRecognizer(recognizer)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gestureCoordinator: WeeklyGestureCoordinator
        var onBegan: () -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: () -> Void
        var onCancelled: () -> Void
        private var initialWindowPoint: CGPoint?
        private var didOwnResize = false

        init(
            gestureCoordinator: WeeklyGestureCoordinator,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping () -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.gestureCoordinator = gestureCoordinator
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer.numberOfTouches == 1 else { return false }
            return gestureCoordinator.canHandleSingleTouch
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            gestureCoordinator.canHandleSingleTouch
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                guard recognizer.numberOfTouches == 1,
                      gestureCoordinator.tryStartEventDrag() else {
                    didOwnResize = false
                    initialWindowPoint = nil
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                didOwnResize = true
                initialWindowPoint = point
                onBegan()

            case .changed:
                guard didOwnResize else { return }
                if recognizer.numberOfTouches != 1 || gestureCoordinator.isZoomExclusive {
                    cancelResize()
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                let translation = CGPoint(
                    x: point.x - (initialWindowPoint?.x ?? point.x),
                    y: point.y - (initialWindowPoint?.y ?? point.y)
                )
                onChanged(translation)

            case .ended:
                guard didOwnResize else { return }
                didOwnResize = false
                initialWindowPoint = nil
                if gestureCoordinator.isZoomExclusive || gestureCoordinator.mode != .eventDrag {
                    onCancelled()
                } else {
                    onEnded()
                }
                gestureCoordinator.finishInteraction(owner: .eventCard)

            case .cancelled, .failed:
                cancelResize()

            default:
                break
            }
        }

        private func cancelResize() {
            guard didOwnResize else { return }
            didOwnResize = false
            initialWindowPoint = nil
            onCancelled()
            gestureCoordinator.finishInteraction(owner: .eventCard)
        }
    }
}

// MARK: - Observable ScrollView & ScrollView Bridge

struct ObservableScrollView<Content: View>: View {
    let bridge: ScrollViewBridge
    let onScrollViewResolved: (UIScrollView) -> Void
    let content: () -> Content
    let onOffsetChange: (CGFloat) -> Void
    let onViewportHeightChange: (CGFloat) -> Void

    init(
        bridge: ScrollViewBridge,
        onScrollViewResolved: @escaping (UIScrollView) -> Void,
        @ViewBuilder content: @escaping () -> Content,
        onOffsetChange: @escaping (CGFloat) -> Void,
        onViewportHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.bridge = bridge
        self.onScrollViewResolved = onScrollViewResolved
        self.content = content
        self.onOffsetChange = onOffsetChange
        self.onViewportHeightChange = onViewportHeightChange
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .background(
                    ScrollViewResolverView(axis: .vertical) { scrollView in
                        bridge.bind(to: scrollView) { offset in
                            onOffsetChange(offset.y)
                        }
                        onScrollViewResolved(scrollView)
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        onViewportHeightChange(proxy.size.height)
                    }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        onViewportHeightChange(newHeight)
                    }
            }
        )
    }
}

@MainActor
final class ScrollViewBridge {
    weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var lastOffset: CGPoint = .zero
    private var onOffsetChange: ((CGPoint) -> Void)?

    func bind(to scrollView: UIScrollView, onOffsetChange: @escaping (CGPoint) -> Void) {
        self.onOffsetChange = onOffsetChange

        if self.scrollView !== scrollView {
            offsetObservation?.invalidate()
            self.scrollView = scrollView
            lastOffset = scrollView.contentOffset
            offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
                guard let newOffset = change.newValue else { return }
                Task { @MainActor [weak self] in
                    guard let self, newOffset != self.lastOffset else { return }
                    self.lastOffset = newOffset
                    self.onOffsetChange?(newOffset)
                }
            }
        }

        if scrollView.contentOffset != lastOffset {
            lastOffset = scrollView.contentOffset
            onOffsetChange(scrollView.contentOffset)
        }
    }
}

enum ScrollViewAxis {
    case horizontal
    case vertical
}

struct ScrollViewResolverView: UIViewRepresentable {
    let axis: ScrollViewAxis
    let onResolve: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        ResolverUIView(axis: axis, onResolve: onResolve)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let resolverView = uiView as? ResolverUIView {
            resolverView.axis = axis
            resolverView.onResolve = onResolve
            resolverView.resolveIfNeeded()
        }
    }
}

private final class ResolverUIView: UIView {
    var axis: ScrollViewAxis
    var onResolve: (UIScrollView) -> Void
    private weak var resolvedScrollView: UIScrollView?

    init(axis: ScrollViewAxis, onResolve: @escaping (UIScrollView) -> Void) {
        self.axis = axis
        self.onResolve = onResolve
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolveIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveIfNeeded()
    }

    func resolveIfNeeded() {
        guard window != nil else { return }
        guard let scrollView = resolvedWeeklyScrollView(axis: axis) else { return }
        guard resolvedScrollView !== scrollView else { return }
        resolvedScrollView = scrollView
        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            self.onResolve(scrollView)
        }
    }
}

private extension UIView {
    func resolvedWeeklyScrollView(axis: ScrollViewAxis) -> UIScrollView? {
        // First walk UP the superview chain to find the exact enclosing UIScrollView.
        // Because ScrollViewResolverView is placed directly inside each ScrollView's content,
        // the nearest enclosing UIScrollView is guaranteed to be the exact target ScrollView.
        var ancestor: UIView? = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            ancestor = current.superview
        }

        // Fallback: search descendants strictly matching the requested axis (never guess wrong axis).
        var root: UIView = self
        while let parent = root.superview {
            root = parent
        }

        let allScrollViews = root.allDescendantScrollViews()
        let candidates = allScrollViews.filter { scrollView in
            switch axis {
            case .horizontal:
                return scrollView.contentSize.width > scrollView.bounds.width + 1
            case .vertical:
                return scrollView.contentSize.height > scrollView.bounds.height + 1
            }
        }

        return candidates.max(by: { lhs, rhs in
            switch axis {
            case .horizontal:
                return (lhs.contentSize.width - lhs.bounds.width) < (rhs.contentSize.width - rhs.bounds.width)
            case .vertical:
                return (lhs.contentSize.height - lhs.bounds.height) < (rhs.contentSize.height - rhs.bounds.height)
            }
        })
    }

    func allDescendantScrollViews() -> [UIScrollView] {
        var result: [UIScrollView] = []

        func collect(from view: UIView) {
            if let scrollView = view as? UIScrollView {
                result.append(scrollView)
            }
            for subview in view.subviews {
                collect(from: subview)
            }
        }

        collect(from: self)
        return result
    }
}

// MARK: - Window-Level Multitouch Observer + Two-Axis Pinch Capture

struct TwoAxisPinchValue {
    let center: CGPoint
    let span: CGSize
}

/// Passive observer attached at window level that tracks every touch inside the weekly timeline
/// bounds. The instant 2+ fingers touch down anywhere in the timeline (even across different day
/// columns and before a pinch begins moving), it notifies `WeeklyGestureCoordinator` to enter
/// `zoomExclusive` and cancel all single-touch recognizers.
private final class MultiTouchObserverGestureRecognizer: UIGestureRecognizer {
    weak var targetView: UIView?
    var onActiveTouchCountChange: ((Int) -> Void)?

    private var trackedTouches = Set<UITouch>()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let targetView,
              let hostView = view,
              targetView.window != nil,
              !targetView.isHidden,
              !targetView.hasPresentedViewControllerAbove else {
            return
        }

        let hitBounds = targetView.bounds.insetBy(dx: -24, dy: -24)
        for touch in touches {
            let pointInHost = touch.location(in: hostView)
            let pointInTarget = targetView.convert(pointInHost, from: hostView)
            if hitBounds.contains(pointInTarget) {
                trackedTouches.insert(touch)
            }
        }
        pruneAndReport(event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        pruneAndReport(event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        trackedTouches.subtract(touches)
        pruneAndReport(event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        trackedTouches.subtract(touches)
        pruneAndReport(event: event)
    }

    override func reset() {
        super.reset()
        if !trackedTouches.isEmpty {
            trackedTouches.removeAll()
            onActiveTouchCountChange?(0)
        }
    }

    private func pruneAndReport(event: UIEvent) {
        // Prune any stale touch pointers UIKit already ended/cancelled
        trackedTouches = trackedTouches.filter { touch in
            touch.phase != .ended && touch.phase != .cancelled && touch.window != nil
        }

        // Cross-check event.allTouches for any active touches inside the timeline bounds
        if let allTouches = event.allTouches,
           let targetView,
           let hostView = view,
           targetView.window != nil,
           !targetView.isHidden,
           !targetView.hasPresentedViewControllerAbove {
            let hitBounds = targetView.bounds.insetBy(dx: -24, dy: -24)
            for touch in allTouches where touch.phase != .ended && touch.phase != .cancelled {
                let pointInTarget = targetView.convert(touch.location(in: hostView), from: hostView)
                if hitBounds.contains(pointInTarget) {
                    trackedTouches.insert(touch)
                }
            }
        }

        onActiveTouchCountChange?(trackedTouches.count)
    }
}

struct TwoAxisPinchCaptureView: UIViewRepresentable {
    let gestureCoordinator: WeeklyGestureCoordinator
    let onBegan: (TwoAxisPinchValue) -> Void
    let onChanged: (TwoAxisPinchValue) -> Void
    let onEnded: () -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            gestureCoordinator: gestureCoordinator,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = PinchGestureAttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.gestureCoordinator = gestureCoordinator
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled

        if let view = uiView as? PinchGestureAttachmentView {
            view.coordinator = context.coordinator
            view.attachIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gestureCoordinator: WeeklyGestureCoordinator
        var onBegan: (TwoAxisPinchValue) -> Void
        var onChanged: (TwoAxisPinchValue) -> Void
        var onEnded: () -> Void
        var onCancelled: () -> Void

        private lazy var pinchRecognizer: UIPinchGestureRecognizer = {
            let recognizer = UIPinchGestureRecognizer(
                target: self,
                action: #selector(handlePinch(_:))
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        private lazy var multiTouchObserver: MultiTouchObserverGestureRecognizer = {
            let observer = MultiTouchObserverGestureRecognizer(target: nil, action: nil)
            observer.delegate = self
            observer.onActiveTouchCountChange = { [weak self] count in
                guard let self else { return }
                self.gestureCoordinator.updateActiveTouchCount(count)
            }
            return observer
        }()

        private weak var attachedView: UIView?
        private weak var targetView: UIView?
        private var isPinchActive = false
        private var resignObserver: NSObjectProtocol?

        init(
            gestureCoordinator: WeeklyGestureCoordinator,
            onBegan: @escaping (TwoAxisPinchValue) -> Void,
            onChanged: @escaping (TwoAxisPinchValue) -> Void,
            onEnded: @escaping () -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.gestureCoordinator = gestureCoordinator
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
            super.init()

            resignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isPinchActive = false
                    self.gestureCoordinator.forceReset()
                }
            }
        }

        func attach(to view: UIView, targetView: UIView) {
            if attachedView === view {
                self.targetView = targetView
                multiTouchObserver.targetView = targetView
                return
            }
            detach()
            view.addGestureRecognizer(multiTouchObserver)
            view.addGestureRecognizer(pinchRecognizer)
            attachedView = view
            self.targetView = targetView
            multiTouchObserver.targetView = targetView
        }

        func detach() {
            attachedView?.removeGestureRecognizer(multiTouchObserver)
            attachedView?.removeGestureRecognizer(pinchRecognizer)
            attachedView = nil
            targetView = nil
            multiTouchObserver.targetView = nil
            isPinchActive = false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            if gestureRecognizer === multiTouchObserver {
                return true
            }
            guard let targetView,
                  let hostView = attachedView,
                  targetView.window != nil,
                  !targetView.isHidden,
                  !targetView.hasPresentedViewControllerAbove else {
                return false
            }
            let pointInTarget = targetView.convert(touch.location(in: hostView), from: hostView)
            return targetView.bounds.insetBy(dx: -24, dy: -24).contains(pointInTarget)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Must return true so UIPinchGestureRecognizer on the window is never blocked by
            // UIScrollView's internal pan/delayed-touch recognizers or SwiftUI hosting recognizers.
            // Single-touch long-press/tap/pan recognizers are explicitly cancelled and blocked by
            // WeeklyGestureCoordinator the instant 2+ touches hit the timeline.
            true
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            // Always handle terminal states FIRST, even if numberOfTouches dropped below 2!
            switch recognizer.state {
            case .ended:
                if isPinchActive {
                    isPinchActive = false
                    onEnded()
                }
                return
            case .cancelled, .failed:
                if isPinchActive {
                    isPinchActive = false
                    onCancelled()
                }
                return
            default:
                break
            }

            guard recognizer.numberOfTouches >= 2,
                  let view = recognizer.view,
                  let targetView else {
                if isPinchActive {
                    isPinchActive = false
                    onEnded()
                }
                return
            }

            let firstPointInHost = recognizer.location(ofTouch: 0, in: view)
            let secondPointInHost = recognizer.location(ofTouch: 1, in: view)
            let firstPoint = targetView.convert(firstPointInHost, from: view)
            let secondPoint = targetView.convert(secondPointInHost, from: view)
            let currentSpan = CGSize(
                width: abs(secondPoint.x - firstPoint.x),
                height: abs(secondPoint.y - firstPoint.y)
            )
            let center = CGPoint(
                x: (firstPoint.x + secondPoint.x) / 2,
                y: (firstPoint.y + secondPoint.y) / 2
            )

            guard targetView.bounds.insetBy(dx: -24, dy: -24).contains(center) else {
                if isPinchActive {
                    isPinchActive = false
                    onEnded()
                }
                return
            }

            switch recognizer.state {
            case .began:
                gestureCoordinator.enterZoomExclusive()
                isPinchActive = true
                onBegan(TwoAxisPinchValue(center: center, span: currentSpan))
            case .changed:
                if !isPinchActive {
                    gestureCoordinator.enterZoomExclusive()
                    isPinchActive = true
                    onBegan(TwoAxisPinchValue(center: center, span: currentSpan))
                } else {
                    onChanged(TwoAxisPinchValue(center: center, span: currentSpan))
                }
            default:
                break
            }
        }
    }
}

private final class PinchGestureAttachmentView: UIView {
    weak var coordinator: TwoAxisPinchCaptureView.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            coordinator?.detach()
        } else {
            attachIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        if let window {
            coordinator?.attach(to: window, targetView: self)
        }
    }
}

private extension UIView {
    var hasPresentedViewControllerAbove: Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController,
               viewController.presentedViewController != nil {
                return true
            }
            responder = current.next
        }
        return false
    }
}
