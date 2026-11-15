import Photos
import SwiftUI
import UIKit

/// Adds an edge-only dismiss gesture to the gallery root, leaving the native
/// navigation controller's interactive back gesture in charge of detail pages.
struct GalleryEdgeDismiss: UIViewControllerRepresentable {
    let enabled: Bool
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> GalleryEdgeController { GalleryEdgeController() }
    func updateUIViewController(_ controller: GalleryEdgeController, context: Context) {
        controller.enabled = enabled
        controller.onDismiss = onDismiss
    }
    static func dismantleUIViewController(_ controller: GalleryEdgeController, coordinator: ()) {
        controller.detach()
    }
}

final class GalleryEdgeController: UIViewController, UIGestureRecognizerDelegate {
    var enabled = true
    var onDismiss: (() -> Void)?
    private weak var host: UIView?
    private lazy var edge: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        gesture.edges = .left
        gesture.delegate = self
        return gesture
    }()

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attach()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attach()
    }
    private func attach() {
        guard let target = navigationController?.view ?? parent?.view, target !== view else { return }
        guard host !== target else { return }
        detach()
        host = target
        target.addGestureRecognizer(edge)
    }
    func detach() {
        host?.removeGestureRecognizer(edge)
        host = nil
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard enabled, (navigationController?.viewControllers.count ?? 1) <= 1 else { return false }
        let velocity = edge.velocity(in: host)
        return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer
    }
    @objc private func swiped(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard enabled, gesture.state == .ended, let host else { return }
        let distance = gesture.translation(in: host).x
        let speed = gesture.velocity(in: host).x
        if distance >= min(100, host.bounds.width * 0.25) || (distance > 24 && speed > 600) {
            onDismiss?()
        }
    }
}

struct GalleryPager: UIViewControllerRepresentable {
    let records: [GalleryRecord]
    let assets: [String: PHAsset]
    @Binding var selection: String
    @Binding var transitioning: Bool
    let locked: Bool

    func makeUIViewController(context: Context) -> GalleryPagerController { GalleryPagerController() }
    func updateUIViewController(_ controller: GalleryPagerController, context: Context) {
        controller.onSelection = { selection = $0 }
        controller.onTransition = { transitioning = $0 }
        controller.update(records: records, assets: assets, selection: selection, locked: locked)
    }
}

final class GalleryPageController: UIHostingController<GalleryImage> {
    let photoID: String
    init(asset: PHAsset, onZoom: @escaping (Bool) -> Void) {
        photoID = asset.localIdentifier
        super.init(rootView: GalleryImage(asset: asset, fullSize: true, onZoomChanged: onZoom))
        view.backgroundColor = .black
    }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class GalleryPagerController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var onSelection: ((String) -> Void)?
    var onTransition: ((Bool) -> Void)?
    private var records: [GalleryRecord] = []
    private var assets: [String: PHAsset] = [:]
    private var locked = false
    private var zoomed: Set<String> = []
    private var transitioning = false
    private var needsPageRefresh = false
    private var desiredSelection: String?
    private var current: GalleryPageController? { viewControllers?.first as? GalleryPageController }
    private var pagingScroll: UIScrollView? { view.subviews.compactMap { $0 as? UIScrollView }.first }

    init() {
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal)
        dataSource = self
        delegate = self
        view.backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prioritizeBackGesture()
    }

    func update(records: [GalleryRecord], assets: [String: PHAsset], selection: String, locked: Bool) {
        if self.records.map(\.id) != records.map(\.id) { needsPageRefresh = true }
        self.records = records
        self.assets = assets
        self.locked = locked
        desiredSelection = selection
        zoomed.formIntersection(Set(records.map(\.id)))
        synchronizeSelection()
        updatePaging()
        prioritizeBackGesture()
    }

    private func synchronizeSelection() {
        guard !transitioning, let id = desiredSelection,
              current?.photoID != id || needsPageRefresh else { return }
        guard let page = current?.photoID == id ? current : makePage(id) else { return }
        needsPageRefresh = false
        dataSource = nil
        setViewControllers([page], direction: .forward, animated: false)
        dataSource = self
    }

    private func makePage(_ id: String) -> GalleryPageController? {
        guard let asset = assets[id] else { return nil }
        zoomed.remove(id)
        return GalleryPageController(asset: asset) { [weak self] isZoomed in
            guard let self else { return }
            if isZoomed { self.zoomed.insert(id) } else { self.zoomed.remove(id) }
            self.updatePaging()
        }
    }

    private func updatePaging() {
        let enlarged = current.map { zoomed.contains($0.photoID) } ?? false
        pagingScroll?.isScrollEnabled = !locked && !enlarged
        current?.view.isUserInteractionEnabled = !locked
    }

    private func prioritizeBackGesture() {
        if let back = navigationController?.interactivePopGestureRecognizer {
            pagingScroll?.panGestureRecognizer.require(toFail: back)
        }
    }

    private func adjacent(to controller: UIViewController, offset: Int) -> UIViewController? {
        guard !locked, let page = controller as? GalleryPageController,
              let index = records.firstIndex(where: { $0.id == page.photoID }) else { return nil }
        let next = index + offset
        guard records.indices.contains(next) else { return nil }
        return makePage(records[next].id)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        adjacent(to: viewController, offset: -1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        adjacent(to: viewController, offset: 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        transitioning = true
        onTransition?(true)
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        transitioning = false
        if completed, let id = current?.photoID, records.contains(where: { $0.id == id }) {
            desiredSelection = id
            onSelection?(id)
        }
        synchronizeSelection()
        updatePaging()
        onTransition?(false)
    }
}
