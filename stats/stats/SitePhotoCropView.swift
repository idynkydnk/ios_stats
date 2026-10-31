import SwiftUI
import UIKit
import Combine

struct SiteFacePhoto: Identifiable {
    let id = UUID()
    let playerName: String
    let image: CGImage
}

struct SitePhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var crop: SitePhotoCropModel
    @State private var uploading = false
    @State private var error: String?
    let onUsePhoto: (Data) async throws -> Void

    init(image: CGImage, onUsePhoto: @escaping (Data) async throws -> Void) {
        _crop = StateObject(wrappedValue: SitePhotoCropModel(image: image))
        self.onUsePhoto = onUsePhoto
    }

    var body: some View {
        NavigationStack {
            GeometryReader { available in
                let isWide = available.size.width > available.size.height * 1.25
                let layout = isWide
                    ? AnyLayout(HStackLayout(spacing: 24))
                    : AnyLayout(VStackLayout(spacing: 20))
                layout {
                    GeometryReader { area in
                        let side = max(1, min(area.size.width, area.size.height))
                        SitePhotoCropViewport(model: crop)
                            .frame(width: side, height: side)
                            .overlay {
                                // The square is saved; the circle previews player avatars.
                                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                    .shadow(color: .black.opacity(0.6), radius: 2)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            .clipped()
                            .position(x: area.size.width / 2, y: area.size.height / 2)
                    }
                    ScrollView {
                        VStack(spacing: 14) {
                            Text("Pinch to zoom. Drag to put the face inside the circle.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 12) {
                                Image(systemName: "minus.magnifyingglass")
                                    .accessibilityHidden(true)
                                Slider(value: Binding(
                                    get: { crop.zoom },
                                    set: { crop.viewport?.setRelativeZoom($0) }
                                ), in: 1...SitePhotoCropModel.maximumZoom)
                                .accessibilityLabel("Photo zoom")
                                .accessibilityValue(String(format: "%.1f times", crop.zoom))
                                Image(systemName: "plus.magnifyingglass")
                                    .accessibilityHidden(true)
                            }
                            Button("Reset") {
                                crop.viewport?.resetCrop(animated: !reduceMotion)
                            }
                            .frame(minHeight: 44)
                            .accessibilityHint("Centers the photo and zooms all the way out")
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxWidth: isWide ? 360 : .infinity,
                           maxHeight: isWide ? .infinity : min(180, available.size.height * 0.4))
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Adjust face photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(uploading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await usePhoto() }
                } label: {
                    HStack {
                        if uploading { ProgressView().tint(.white) }
                        Text(uploading ? "Uploading…" : "Use photo")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(uploading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .disabled(uploading)
            .interactiveDismissDisabled(uploading)
            .alert("Photo not saved", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "Please try again.")
            }
        }
    }

    @MainActor
    private func usePhoto() async {
        guard !uploading, let viewport = crop.viewport else { return }
        uploading = true
        defer { uploading = false }
        let rect = viewport.cropRect
        let image = crop.image
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try SitePhotoUpload.croppedJPEG(from: image, rect: rect)
            }.value
            try await onUsePhoto(data)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
private final class SitePhotoCropModel: ObservableObject {
    static let maximumZoom = 6.0
    let image: CGImage
    @Published var zoom = 1.0
    weak var viewport: SitePhotoCropScrollView?

    init(image: CGImage) { self.image = image }
}

private struct SitePhotoCropViewport: UIViewRepresentable {
    let model: SitePhotoCropModel

    func makeUIView(context: Context) -> SitePhotoCropScrollView {
        let view = SitePhotoCropScrollView(image: model.image)
        model.viewport = view
        view.onZoom = { [weak model, weak view] in
            // Layout and native gestures can notify while SwiftUI is updating.
            // Read the latest scale on the next turn, without driving the view
            // back from a stale binding on every pinch frame.
            Task { @MainActor in
                guard let model, let view else { return }
                model.zoom = view.relativeZoom
            }
        }
        return view
    }

    func updateUIView(_ uiView: SitePhotoCropScrollView, context: Context) {}
}

// Keep gesture tracking in UIKit: no image decoding, rendering, or SwiftUI
// layout work is needed while a finger is moving.
private final class SitePhotoCropScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var viewportSize = CGSize.zero
    var onZoom: (() -> Void)?

    init(image: CGImage) {
        imageView = UIImageView(image: UIImage(cgImage: image))
        super.init(frame: .zero)
        addSubview(imageView)
        contentSize = imageView.bounds.size
        delegate = self
        backgroundColor = .white
        clipsToBounds = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bounces = false
        bouncesZoom = false
        decelerationRate = .fast
        isAccessibilityElement = true
        accessibilityLabel = "Face photo preview"
        accessibilityHint = "Use the zoom slider to enlarge the face. Use actions to move the photo."
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move photo left") { [weak self] _ in self?.movePhoto(x: -0.1, y: 0) ?? false },
            UIAccessibilityCustomAction(name: "Move photo right") { [weak self] _ in self?.movePhoto(x: 0.1, y: 0) ?? false },
            UIAccessibilityCustomAction(name: "Move photo up") { [weak self] _ in self?.movePhoto(x: 0, y: -0.1) ?? false },
            UIAccessibilityCustomAction(name: "Move photo down") { [weak self] _ in self?.movePhoto(x: 0, y: 0.1) ?? false },
        ]
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var relativeZoom: Double {
        min(SitePhotoCropModel.maximumZoom, max(1, Double(zoomScale / minimumZoomScale)))
    }

    var cropRect: CGRect { imageView.convert(bounds, from: self) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != viewportSize else { return }
        let firstLayout = viewportSize == .zero
        let zoom = firstLayout ? 1 : relativeZoom
        let center = firstLayout
            ? CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
            : CGPoint(x: (contentOffset.x + viewportSize.width / 2) / zoomScale,
                      y: (contentOffset.y + viewportSize.height / 2) / zoomScale)
        viewportSize = bounds.size
        minimumZoomScale = max(bounds.width / imageView.bounds.width, bounds.height / imageView.bounds.height)
        maximumZoomScale = minimumZoomScale * SitePhotoCropModel.maximumZoom
        setZoomScale(minimumZoomScale * zoom, animated: false)
        centerOn(center)
        onZoom?()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { onZoom?() }

    func setRelativeZoom(_ value: Double) {
        let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
        setZoomScale(minimumZoomScale * min(max(value, 1), SitePhotoCropModel.maximumZoom), animated: false)
        centerOn(center)
    }

    func resetCrop(animated: Bool) {
        let changes = {
            self.setZoomScale(self.minimumZoomScale, animated: false)
            self.centerOn(CGPoint(x: self.imageView.bounds.midX, y: self.imageView.bounds.midY))
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: changes)
        } else {
            changes()
        }
    }

    private func centerOn(_ point: CGPoint) {
        let x = point.x * zoomScale - bounds.width / 2
        let y = point.y * zoomScale - bounds.height / 2
        contentOffset = CGPoint(
            x: min(max(0, x), max(0, imageView.bounds.width * zoomScale - bounds.width)),
            y: min(max(0, y), max(0, imageView.bounds.height * zoomScale - bounds.height))
        )
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if relativeZoom > 1.05 {
            resetCrop(animated: !UIAccessibility.isReduceMotionEnabled)
        } else {
            let point = gesture.location(in: imageView)
            let scale = minimumZoomScale * 2.5
            let rect = CGRect(x: point.x - bounds.width / scale / 2,
                              y: point.y - bounds.height / scale / 2,
                              width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: rect, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    private func movePhoto(x: CGFloat, y: CGFloat) -> Bool {
        let rect = cropRect
        centerOn(CGPoint(x: rect.midX - x * rect.width, y: rect.midY - y * rect.height))
        return true
    }
}
