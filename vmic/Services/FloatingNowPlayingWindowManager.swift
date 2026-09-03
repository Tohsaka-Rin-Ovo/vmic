import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UIKit

enum FloatingWindowStatus: Equatable {
    case idle
    case disabled
    case ready
    case starting
    case active
    case unavailable(String)
    case failed(String)

    var logName: String {
        switch self {
        case .idle:
            return "idle"
        case .disabled:
            return "disabled"
        case .ready:
            return "ready"
        case .starting:
            return "starting"
        case .active:
            return "active"
        case .unavailable(let reason):
            return "unavailable(\(reason))"
        case .failed(let message):
            return "failed(\(message))"
        }
    }
}

@MainActor
final class FloatingNowPlayingWindowManager: NSObject, ObservableObject {
    @Published private(set) var status: FloatingWindowStatus = .idle

    private weak var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var pictureInPictureController: AVPictureInPictureController?
    private var activeClipID: UUID?
    private var lastArtworkKey: String?
    private var lastRenderedTitle: String?
    private var didLogUnsupported = false
    private var preservedAudioSessionState: AudioSessionState?

    private static let canvasSize = CGSize(width: 720, height: 720)

    func attach(displayLayer: AVSampleBufferDisplayLayer) {
        guard sampleBufferDisplayLayer !== displayLayer else { return }

        sampleBufferDisplayLayer = displayLayer
        configureDisplayLayer(displayLayer)
        configurePictureInPictureController()
        DiagnosticLogStore.shared.log("悬浮窗渲染宿主已接入", source: .floatingWindow)
    }

    func sync(
        isForeground: Bool,
        isEnabled: Bool,
        clip: SoundClip?,
        artworkDirectory: URL,
        playbackState: SoundPlaybackState?
    ) {
        guard isEnabled else {
            stop(reason: "setting-disabled")
            setStatus(.disabled)
            return
        }

        guard let clip else {
            stop(reason: "no-current-clip")
            setStatus(.idle)
            return
        }

        let isPlaying = playbackState == .playing

        guard isPlaying else {
            stop(reason: "playback-not-playing")
            setStatus(.ready)
            return
        }

        renderIfNeeded(clip: clip, artworkDirectory: artworkDirectory)

        if isForeground {
            stop(reason: "app-foreground")
            setStatus(.ready)
        } else {
            startIfPossible(clip: clip)
        }
    }

    private func configureDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor

        if layer.controlTimebase == nil {
            var timebase: CMTimebase?
            let status = CMTimebaseCreateWithSourceClock(
                allocator: kCFAllocatorDefault,
                sourceClock: CMClockGetHostTimeClock(),
                timebaseOut: &timebase
            )

            if status == noErr, let timebase {
                layer.controlTimebase = timebase
                CMTimebaseSetRate(timebase, rate: 1)
            }
        }
    }

    private func configurePictureInPictureController() {
        guard pictureInPictureController == nil else { return }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            if !didLogUnsupported {
                didLogUnsupported = true
                DiagnosticLogStore.shared.log("当前设备不支持系统 PiP 悬浮窗", source: .floatingWindow)
            }
            setStatus(.unavailable("pip-unsupported"))
            return
        }

        guard let sampleBufferDisplayLayer else {
            setStatus(.unavailable("display-layer-missing"))
            return
        }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferDisplayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller
        DiagnosticLogStore.shared.log("系统 PiP 控制器已准备", source: .floatingWindow)
    }

    private func startIfPossible(clip: SoundClip) {
        configurePictureInPictureController()

        guard let pictureInPictureController else { return }

        if pictureInPictureController.isPictureInPictureActive {
            setStatus(.active)
            return
        }

        guard prepareBackgroundPlaybackSession() else { return }

        guard pictureInPictureController.isPictureInPicturePossible else {
            DiagnosticLogStore.shared.log(
                "悬浮窗暂不可启动",
                source: .floatingWindow,
                details: [
                    "title=\(clip.title)",
                    "possible=false",
                    "suspended=\(pictureInPictureController.isPictureInPictureSuspended)"
                ]
            )
            setStatus(.unavailable("pip-not-possible"))
            return
        }

        activeClipID = clip.id
        setStatus(.starting)
        DiagnosticLogStore.shared.log(
            "尝试开启后台悬浮窗",
            source: .floatingWindow,
            details: ["title=\(clip.title)", "clipID=\(shortID(clip.id))"]
        )
        pictureInPictureController.startPictureInPicture()
    }

    private func stop(reason: String) {
        guard let pictureInPictureController else { return }

        if pictureInPictureController.isPictureInPictureActive {
            DiagnosticLogStore.shared.log("关闭后台悬浮窗", source: .floatingWindow, details: ["reason=\(reason)"])
            pictureInPictureController.stopPictureInPicture()
        } else {
            restoreAudioSessionIfNeeded(reason: reason)
        }
    }

    private func prepareBackgroundPlaybackSession() -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            if preservedAudioSessionState == nil {
                preservedAudioSessionState = AudioSessionState(
                    category: session.category,
                    mode: session.mode,
                    options: session.categoryOptions
                )
            }

            DiagnosticLogStore.shared.log(
                "准备后台播放音频会话",
                source: .floatingWindow,
                details: [
                    "categoryBefore=\(session.category.rawValue)",
                    "modeBefore=\(session.mode.rawValue)"
                ]
            )
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            DiagnosticLogStore.shared.log(
                "后台播放音频会话已准备",
                source: .floatingWindow,
                details: [
                    "category=\(session.category.rawValue)",
                    "mode=\(session.mode.rawValue)"
                ]
            )
            return true
        } catch {
            setStatus(.failed(error.localizedDescription))
            DiagnosticLogStore.shared.log(
                "后台播放音频会话准备失败",
                source: .floatingWindow,
                details: ["error=\(error.localizedDescription)"]
            )
            return false
        }
    }

    private func restoreAudioSessionIfNeeded(reason: String) {
        guard let preservedAudioSessionState else { return }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                preservedAudioSessionState.category,
                mode: preservedAudioSessionState.mode,
                options: preservedAudioSessionState.options
            )
            self.preservedAudioSessionState = nil
            DiagnosticLogStore.shared.log(
                "恢复悬浮窗前音频会话",
                source: .floatingWindow,
                details: [
                    "reason=\(reason)",
                    "category=\(session.category.rawValue)",
                    "mode=\(session.mode.rawValue)"
                ]
            )
        } catch {
            DiagnosticLogStore.shared.log(
                "恢复悬浮窗前音频会话失败",
                source: .floatingWindow,
                details: ["reason=\(reason)", "error=\(error.localizedDescription)"]
            )
        }
    }

    private func renderIfNeeded(clip: SoundClip, artworkDirectory: URL) {
        let artworkKey = clip.artworkFileName ?? "placeholder"
        guard activeClipID != clip.id || lastArtworkKey != artworkKey || lastRenderedTitle != clip.title else { return }

        guard let sampleBufferDisplayLayer else { return }
        guard let image = composedArtworkImage(for: clip, artworkDirectory: artworkDirectory) else {
            DiagnosticLogStore.shared.log("悬浮窗封面渲染失败", source: .floatingWindow, details: ["title=\(clip.title)"])
            return
        }

        guard let sampleBuffer = sampleBuffer(from: image) else {
            DiagnosticLogStore.shared.log("悬浮窗视频帧创建失败", source: .floatingWindow, details: ["title=\(clip.title)"])
            return
        }

        if sampleBufferDisplayLayer.status == .failed {
            sampleBufferDisplayLayer.flushAndRemoveImage()
        } else {
            sampleBufferDisplayLayer.flush()
        }

        sampleBufferDisplayLayer.enqueue(sampleBuffer)
        activeClipID = clip.id
        lastArtworkKey = artworkKey
        lastRenderedTitle = clip.title
        DiagnosticLogStore.shared.log(
            "悬浮窗封面已更新",
            source: .floatingWindow,
            details: ["title=\(clip.title)", "clipID=\(shortID(clip.id))", "artwork=\(artworkKey)"]
        )
    }

    private func composedArtworkImage(for clip: SoundClip, artworkDirectory: URL) -> UIImage? {
        let artwork = loadArtwork(for: clip, artworkDirectory: artworkDirectory)
        let size = Self.canvasSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            let cgContext = context.cgContext
            let backgroundColors = [
                UIColor(red: 0.04, green: 0.16, blue: 0.30, alpha: 1).cgColor,
                UIColor(red: 0.07, green: 0.45, blue: 0.80, alpha: 1).cgColor
            ]
            let gradientLocations: [CGFloat] = [0, 1]

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: backgroundColors as CFArray,
                locations: gradientLocations
            ) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            artwork.draw(in: aspectFillRect(for: artwork.size, in: rect), blendMode: .normal, alpha: 0.20)
            UIColor(red: 0.02, green: 0.09, blue: 0.18, alpha: 0.38).setFill()
            UIBezierPath(rect: rect).fill()

            let artworkRect = CGRect(x: 110, y: 72, width: 500, height: 500)
            let artworkPath = UIBezierPath(roundedRect: artworkRect, cornerRadius: 56)
            cgContext.saveGState()
            artworkPath.addClip()
            artwork.draw(in: aspectFillRect(for: artwork.size, in: artworkRect))
            cgContext.restoreGState()

            UIColor.white.withAlphaComponent(0.22).setStroke()
            artworkPath.lineWidth = 2
            artworkPath.stroke()

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
                .paragraphStyle: paragraphStyle
            ]

            (clip.title as NSString).draw(
                with: CGRect(x: 64, y: 600, width: 592, height: 44),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: titleAttributes,
                context: nil
            )
            ("vmic" as NSString).draw(
                with: CGRect(x: 64, y: 652, width: 592, height: 32),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: subtitleAttributes,
                context: nil
            )
        }
    }

    private func sampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let pixelBuffer = pixelBuffer(from: image) else { return nil }

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        return sampleStatus == noErr ? sampleBuffer : nil
    }

    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let width = Int(Self.canvasSize.width)
        let height = Int(Self.canvasSize.height)
        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return nil
        }

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        UIGraphicsPopContext()

        return pixelBuffer
    }

    private func loadArtwork(for clip: SoundClip, artworkDirectory: URL) -> UIImage {
        if let artworkURL = clip.artworkURL(in: artworkDirectory),
           let data = try? Data(contentsOf: artworkURL),
           let image = UIImage(data: data) {
            return image
        }

        return UIImage(named: "PlaceholderCover") ?? fallbackArtworkImage()
    }

    private func fallbackArtworkImage() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(red: 0.05, green: 0.27, blue: 0.50, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            let symbol = UIImage(systemName: "waveform.circle.fill")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 156, y: 156, width: 200, height: 200))
        }
    }

    private func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale

        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func setStatus(_ newStatus: FloatingWindowStatus) {
        guard status != newStatus else { return }

        status = newStatus
        DiagnosticLogStore.shared.log("悬浮窗状态更新", source: .floatingWindow, details: ["status=\(newStatus.logName)"])
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

private struct AudioSessionState {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
}

extension FloatingNowPlayingWindowManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            DiagnosticLogStore.shared.log("系统即将开启悬浮窗", source: .floatingWindow)
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.setStatus(.active)
            DiagnosticLogStore.shared.log("系统已开启悬浮窗", source: .floatingWindow)
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.setStatus(.failed(error.localizedDescription))
            self?.restoreAudioSessionIfNeeded(reason: "pip-failed")
            DiagnosticLogStore.shared.log("系统拒绝开启悬浮窗", source: .floatingWindow, details: ["error=\(error.localizedDescription)"])
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.setStatus(.ready)
            self?.restoreAudioSessionIfNeeded(reason: "pip-stopped")
            DiagnosticLogStore.shared.log("系统已关闭悬浮窗", source: .floatingWindow)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

extension FloatingNowPlayingWindowManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            DiagnosticLogStore.shared.log("悬浮窗播放状态请求", source: .floatingWindow, details: ["playing=\(playing)"])
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(value: CMTimeValue(24 * 60 * 60), timescale: 1))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        Task { @MainActor in
            DiagnosticLogStore.shared.log(
                "悬浮窗尺寸变化",
                source: .floatingWindow,
                details: ["width=\(newRenderSize.width)", "height=\(newRenderSize.height)"]
            )
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }
}

struct FloatingNowPlayingHostView: UIViewRepresentable {
    @ObservedObject var manager: FloatingNowPlayingWindowManager

    func makeUIView(context: Context) -> FloatingNowPlayingHostUIView {
        let view = FloatingNowPlayingHostUIView()
        manager.attach(displayLayer: view.displayLayer)
        return view
    }

    func updateUIView(_ uiView: FloatingNowPlayingHostUIView, context: Context) {
        manager.attach(displayLayer: uiView.displayLayer)
    }
}

final class FloatingNowPlayingHostUIView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
    }
}
