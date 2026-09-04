import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SoundboardView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var isAudioLibraryPresented = false
    @State private var debugDestination: DebugFocusTarget?

    private var activeClips: [SoundClip] {
        libraryStore.clips.filter {
            playbackManager.activeClipIDs.contains($0.id)
        }
    }

    private var currentClip: SoundClip? {
        if let currentClipID = playbackManager.currentClipID,
           let clip = libraryStore.clips.first(where: { $0.id == currentClipID }) {
            return clip
        }

        return activeClips.first
    }

    var body: some View {
        ZStack {
            VmicTheme.appBackground

            List {
                Section {
                    PlayerHeader(
                        currentClip: currentClip,
                        openAudioLibrary: {
                            isAudioLibraryPresented = true
                        }
                    )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    InjectionControlPanel { target in
                        debugDestination = target
                    }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if let error = injectionManager.lastError ?? libraryStore.lastError ?? playbackManager.lastError {
                        ErrorBanner(message: error)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .task {
            playbackManager.setOutputVolume(settingsStore.inputVolume)
        }
        .onChange(of: settingsStore.inputVolume) { _, newValue in
            playbackManager.setOutputVolume(newValue)
        }
        .navigationTitle("vmic")
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
        .navigationDestination(isPresented: $isAudioLibraryPresented) {
            AudioLibraryView()
        }
        .navigationDestination(item: $debugDestination) { target in
            DebugDiagnosticsView(initialFocus: target.initialFocus)
        }
    }

    private func togglePlayback(_ clip: SoundClip) {
        if settingsStore.singlePlayback && playbackManager.playbackState(for: clip.id) == nil {
            playbackManager.stopAll()
        }

        playbackManager.toggle(
            clip,
            from: libraryStore.soundsDirectory,
            volume: settingsStore.inputVolume,
            reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
        )
    }
}

private struct PlayerHeader: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let currentClip: SoundClip?
    let openAudioLibrary: () -> Void

    private var title: String {
        currentClip == nil ? settingsStore.text(.readyToBridgeAudio) : settingsStore.text(.bridgeAudioReady)
    }

    private var subtitle: String {
        guard let currentClip else {
            return settingsStore.text(.selectSoundToPlay)
        }

        if playbackManager.playbackState(for: currentClip.id) == .paused {
            return settingsStore.text(.clipPaused(currentClip.title))
        }

        return settingsStore.text(.clipPlaying(currentClip.title))
    }

    private var isTitlePlaying: Bool {
        guard let clip = currentClip else { return false }
        return playbackManager.playbackState(for: clip.id) == .playing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                CoverArtworkView(
                    artworkURL: currentClip?.artworkURL(in: libraryStore.artworkDirectory),
                    size: 104
                )

                Button(action: openAudioLibrary) {
                    VStack(alignment: .leading, spacing: 8) {
                        MarqueeText(
                            title,
                            font: .title2.weight(.bold),
                            color: VmicTheme.ink,
                            isActive: isTitlePlaying
                        )
                        .frame(height: 34, alignment: .center)

                        MarqueeText(
                            subtitle,
                            font: .subheadline.weight(.medium),
                            color: VmicTheme.mutedInk,
                            isActive: isTitlePlaying
                        )
                        .frame(height: 21, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .accessibilityLabel(settingsStore.text(.audioList))

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                MiniStatus(
                    title: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.call) : settingsStore.text(.standby),
                    systemImage: injectionManager.isInjectionAvailableInCurrentCall ? "phone.fill" : "phone",
                    tint: injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : VmicTheme.mutedInk
                )

                MiniStatus(
                    title: injectionManager.isInjectionEnabled ? settingsStore.text(.live) : settingsStore.text(.local),
                    systemImage: injectionManager.isInjectionEnabled ? "dot.radiowaves.left.and.right" : "speaker.wave.2",
                    tint: injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
                )

                Button(action: openAudioLibrary) {
                    MiniStatus(
                        title: settingsStore.text(.audio),
                        systemImage: "list.bullet",
                        tint: VmicTheme.blue
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .accessibilityLabel(settingsStore.text(.audioList))
            }
            .frame(maxWidth: 330, alignment: .leading)
        }
        .padding(18)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct AudioLibraryView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var editMode: EditMode = .inactive
    @State private var isImporterPresented = false
    @State private var clipBeingRenamed: SoundClip?
    @State private var renameText = ""
    @State private var showsSortingNotice = false

    var body: some View {
        ZStack {
            VmicTheme.appBackground

            List {
                if libraryStore.clips.isEmpty {
                    Section {
                        EmptySoundboardView(importAction: {
                            isImporterPresented = true
                        })
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)
                } else {
                    Section {
                        ForEach(libraryStore.clips) { clip in
                            AudioListRow(
                                clip: clip,
                                artworkDirectory: libraryStore.artworkDirectory,
                                playbackState: playbackManager.playbackState(for: clip.id),
                                play: {
                                    togglePlayback(clip)
                                },
                                rename: {
                                    clipBeingRenamed = clip
                                    renameText = clip.title
                                },
                                remove: {
                                    libraryStore.delete(clip)
                                }
                            )
                            .onLongPressGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editMode = .active
                                    showsSortingNotice = true
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: libraryStore.move)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if showsSortingNotice {
                VStack {
                    Text(settingsStore.text(.sortingEnabled))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(VmicTheme.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 8)

                    Spacer()
                }
                .transition(.opacity)
                .task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    showsSortingNotice = false
                }
            }
        }
        .navigationTitle(settingsStore.text(.audioList))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button(settingsStore.text(.done)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editMode = .inactive
                        }
                    }
                }

                Button {
                    isImporterPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(QuietIconButtonStyle())
                .accessibilityLabel(settingsStore.text(.importAudio))
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await libraryStore.importFiles(from: urls)
                }
            case .failure(let error):
                libraryStore.lastError = error.localizedDescription
            }
        }
        .alert(settingsStore.text(.renameAudio), isPresented: Binding(
            get: {
                clipBeingRenamed != nil
            },
            set: { isPresented in
                if !isPresented {
                    clipBeingRenamed = nil
                    renameText = ""
                }
            }
        )) {
            TextField(settingsStore.text(.audioName), text: $renameText)

            Button(settingsStore.text(.cancel), role: .cancel) {
                clipBeingRenamed = nil
                renameText = ""
            }

            Button(settingsStore.text(.save)) {
                if let clip = clipBeingRenamed {
                    libraryStore.rename(clip, to: renameText)
                }
                clipBeingRenamed = nil
                renameText = ""
            }
        }
    }

    private func togglePlayback(_ clip: SoundClip) {
        if settingsStore.singlePlayback && playbackManager.playbackState(for: clip.id) == nil {
            playbackManager.stopAll()
        }

        playbackManager.toggle(
            clip,
            from: libraryStore.soundsDirectory,
            volume: settingsStore.inputVolume,
            reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
        )
    }
}

private struct AudioListRow: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip
    let artworkDirectory: URL
    let playbackState: SoundPlaybackState?
    let play: () -> Void
    let rename: () -> Void
    let remove: () -> Void

    private var isActive: Bool {
        playbackState != nil
    }

    private var isPlaying: Bool {
        playbackState == .playing
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                CoverArtworkView(artworkURL: clip.artworkURL(in: artworkDirectory), size: 58)

                if isActive {
                    Circle()
                        .fill(VmicTheme.ink.opacity(0.72))
                        .frame(width: 30, height: 30)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if isPlaying {
                    MarqueeText(
                        clip.title,
                        font: .system(size: 17, weight: .semibold),
                        color: VmicTheme.blue,
                        isActive: true
                    )
                    .frame(height: 22)
                } else {
                    Text(clip.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isActive ? VmicTheme.blue : VmicTheme.ink)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(settingsStore.text(.localAudio))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.88, green: 0.53, blue: 0.10))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color(red: 0.88, green: 0.53, blue: 0.10), lineWidth: 1)
                        }

                    Text(clip.artist?.isEmpty == false ? clip.artist! : settingsStore.text(.unknownArtist))
                        .font(.subheadline)
                        .foregroundStyle(isActive ? VmicTheme.blue : VmicTheme.mutedInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if settingsStore.showDuration {
                Text(formatDuration(clip.durationSeconds))
                    .font(.subheadline)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }

            Menu {
                Button(action: rename) {
                    Label(settingsStore.text(.rename), systemImage: "pencil")
                }

                Button(role: .destructive, action: remove) {
                    Label(settingsStore.text(.removeFromLibrary), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(settingsStore.text(.playSound(clip.title)))
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return "--:--"
        }

        let totalSeconds = Int(seconds.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct CoverArtworkView: View {
    let artworkURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = CoverArtworkCache.image(for: artworkURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("PlaceholderCover")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum CoverArtworkCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for artworkURL: URL?) -> UIImage? {
        guard let artworkURL else { return nil }

        let key = artworkURL as NSURL
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let image = UIImage(contentsOfFile: artworkURL.path) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let isActive: Bool

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating = false

    private let spacing: CGFloat = 28

    init(_ text: String, font: Font, color: Color, isActive: Bool) {
        self.text = text
        self.font = font
        self.color = color
        self.isActive = isActive
    }

    private var shouldScroll: Bool {
        isActive && textWidth > containerWidth + 6
    }

    private var animationDuration: Double {
        max(5.5, Double(textWidth + spacing) / 26)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if shouldScroll {
                    HStack(spacing: spacing) {
                        marqueeLabel
                        marqueeLabel
                    }
                    .offset(x: isAnimating ? -(textWidth + spacing) : 0)
                    .animation(
                        .linear(duration: animationDuration).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .clipped()
            .background(measurementLabel)
            .onAppear {
                containerWidth = proxy.size.width
                restartIfNeeded()
            }
            .onChange(of: proxy.size.width) { _, width in
                containerWidth = width
                restartIfNeeded()
            }
            .onChange(of: text) { _, _ in
                restartIfNeeded()
            }
            .onChange(of: isActive) { _, _ in
                restartIfNeeded()
            }
            .onPreferenceChange(MarqueeTextWidthPreferenceKey.self) { width in
                textWidth = width
                restartIfNeeded()
            }
        }
        .clipped()
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var measurementLabel: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MarqueeTextWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .hidden()
    }

    private func restartIfNeeded() {
        isAnimating = false

        guard shouldScroll else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard shouldScroll else { return }
            isAnimating = true
        }
    }
}

private struct MarqueeTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MiniStatus: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptySoundboardView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            CoverArtworkView(artworkURL: nil, size: 112)

            VStack(spacing: 6) {
                Text(settingsStore.text(.noSounds))
                    .font(.headline)
                    .foregroundStyle(VmicTheme.ink)

                Text(settingsStore.text(.importHint))
                    .font(.subheadline)
                    .foregroundStyle(VmicTheme.mutedInk)
            }

            Button(action: importAction) {
                Label(settingsStore.text(.importAudio), systemImage: "plus")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(BlueProminentButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

struct BottomNowPlayingBar: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var appChromeStore: AppChromeStore

    let clip: SoundClip
    let artworkDirectory: URL
    let playbackState: SoundPlaybackState?
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
    let togglePlayback: () -> Void
    let stopAction: () -> Void
    let seekAction: (Double) -> Void

    @State private var compactDragStartPosition: CGPoint?
    @State private var compactDragLivePosition: CGPoint?
    @State private var compactDragDidMove = false
    @State private var isDraggingDock = false
    @State private var shouldSpinCover = false
    @State private var dockContainerSize = CGSize(width: UIScreen.main.bounds.width - 32, height: 128)

    private var isPlaying: Bool {
        playbackState == .playing
    }

    private var isCompact: Bool {
        appChromeStore.floatingDockPresentation == .compact
    }

    var body: some View {
        GeometryReader { proxy in
            let size = dockSize(in: proxy.size)

            ZStack {
                if isCompact {
                    compactBody
                } else {
                    expandedBody
                }
            }
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .position(resolvedDockPosition(in: proxy.size))
            .onAppear {
                dockContainerSize = proxy.size
            }
            .onChange(of: proxy.size) { _, size in
                dockContainerSize = size
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appChromeStore.floatingDockPresentation)
        .onAppear {
            refreshCoverSpin()
        }
        .onChange(of: isPlaying) { _, _ in
            refreshCoverSpin()
        }
        .onChange(of: isCompact) { _, _ in
            isDraggingDock = false
            compactDragStartPosition = nil
            compactDragLivePosition = nil
            refreshCoverSpin()
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                movableHeader

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(DockIconButtonStyle())
                    .accessibilityLabel(isPlaying ? settingsStore.text(.pause) : settingsStore.text(.play))

                    Button {
                        appChromeStore.isPlaybackSettingsPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(DockIconButtonStyle())
                    .accessibilityLabel(settingsStore.text(.playbackSettings))

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appChromeStore.floatingDockPresentation = .compact
                        }
                    } label: {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                    .buttonStyle(DockIconButtonStyle())
                    .accessibilityLabel(settingsStore.text(.compactPlayer))

                    Button(action: stopAction) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(DockIconButtonStyle())
                    .accessibilityLabel(settingsStore.text(.stopPlayback))
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            PlaybackProgressBar(
                progress: progress,
                elapsedTime: elapsedTime,
                duration: duration,
                seekAction: seekAction
            )
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        }
    }

    private var movableHeader: some View {
        HStack(spacing: 10) {
            CoverArtworkView(artworkURL: clip.artworkURL(in: artworkDirectory), size: 48)

            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(
                    clip.title,
                    font: .subheadline.weight(.semibold),
                    color: VmicTheme.ink,
                    isActive: isPlaying
                )
                .frame(height: 20)

                Text(clip.artist?.isEmpty == false ? clip.artist! : settingsStore.text(.unknownArtist))
                    .font(.caption)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private var compactBody: some View {
        ZStack(alignment: .topTrailing) {
            compactPlaybackBubble

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appChromeStore.floatingDockPresentation = .expanded
                }
            } label: {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(VmicTheme.blue)
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settingsStore.text(.expandPlayer))
        }
        .frame(width: 82, height: 82)
        .scaleEffect(isDraggingDock ? 0.96 : 1)
    }

    private var compactPlaybackBubble: some View {
        ZStack {
            CoverArtworkView(artworkURL: clip.artworkURL(in: artworkDirectory), size: 76)
                .clipShape(Circle())
                .rotationEffect(.degrees(shouldSpinCover ? 360 : 0))
                .animation(
                    .linear(duration: 18).repeatForever(autoreverses: false),
                    value: shouldSpinCover
                )

            Circle()
                .fill(Color.black.opacity(0.16))

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(11)
                .background(Color.black.opacity(0.22), in: Circle())
                .allowsHitTesting(false)
        }
        .frame(width: 76, height: 76)
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .contentShape(Circle())
        .gesture(compactInteractionGesture)
    }

    private var compactInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if compactDragStartPosition == nil {
                    compactDragStartPosition = clampedPosition(
                        appChromeStore.floatingDockPosition ?? defaultDockPosition(in: dockContainerSize),
                        in: dockContainerSize
                    )
                }

                guard dragDistance(value.translation) > 5 else { return }

                if !compactDragDidMove {
                    compactDragDidMove = true
                    isDraggingDock = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                let anchor = compactDragStartPosition ?? defaultDockPosition(in: dockContainerSize)
                let proposed = CGPoint(
                    x: anchor.x + value.translation.width,
                    y: anchor.y + value.translation.height
                )
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    compactDragLivePosition = clampedPosition(proposed, in: dockContainerSize)
                }
            }
            .onEnded { value in
                let didMove = compactDragDidMove || dragDistance(value.translation) > 8
                defer {
                    isDraggingDock = false
                    compactDragStartPosition = nil
                    compactDragDidMove = false
                }

                guard didMove else {
                    compactDragLivePosition = nil
                    togglePlayback()
                    return
                }

                let anchor = compactDragStartPosition ?? defaultDockPosition(in: dockContainerSize)
                let proposed = CGPoint(
                    x: anchor.x + value.translation.width,
                    y: anchor.y + value.translation.height
                )
                let snapped = snappedCompactPosition(proposed, in: dockContainerSize)

                withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                    appChromeStore.floatingDockPosition = snapped
                    compactDragLivePosition = nil
                }
            }
    }

    private func resolvedDockPosition(in containerSize: CGSize) -> CGPoint {
        let position: CGPoint

        if isCompact {
            position = compactDragLivePosition ?? appChromeStore.floatingDockPosition ?? defaultDockPosition(in: containerSize)
        } else {
            position = defaultDockPosition(in: containerSize)
        }

        return clampedPosition(position, in: containerSize)
    }

    private func defaultDockPosition(in containerSize: CGSize) -> CGPoint {
        if isCompact {
            return defaultCompactDockPosition(in: containerSize)
        }

        let size = dockSize(in: containerSize)
        return CGPoint(
            x: containerSize.width / 2,
            y: containerSize.height - size.height / 2 - 10
        )
    }

    private func defaultCompactDockPosition(in containerSize: CGSize) -> CGPoint {
        let size = dockSize(in: containerSize)
        let bottomClearance = min(max(containerSize.height * 0.14, 96), 132)
        return CGPoint(
            x: containerSize.width - size.width / 2 - 18,
            y: containerSize.height - size.height / 2 - bottomClearance
        )
    }

    private func snappedCompactPosition(_ position: CGPoint, in containerSize: CGSize) -> CGPoint {
        let clamped = clampedPosition(position, in: containerSize)
        let size = dockSize(in: containerSize)
        let horizontalInset = size.width / 2 + 14
        let targetX: CGFloat

        if clamped.x < containerSize.width / 2 {
            targetX = horizontalInset
        } else {
            targetX = max(horizontalInset, containerSize.width - horizontalInset)
        }

        return clampedPosition(CGPoint(x: targetX, y: clamped.y), in: containerSize)
    }

    private func clampedPosition(_ position: CGPoint, in containerSize: CGSize) -> CGPoint {
        let size = dockSize(in: containerSize)
        let horizontalInset = size.width / 2 + 12
        let verticalInset = size.height / 2 + 12
        return CGPoint(
            x: min(max(position.x, horizontalInset), max(horizontalInset, containerSize.width - horizontalInset)),
            y: min(max(position.y, verticalInset), max(verticalInset, containerSize.height - verticalInset))
        )
    }

    private func dragDistance(_ translation: CGSize) -> CGFloat {
        sqrt(translation.width * translation.width + translation.height * translation.height)
    }

    private func dockSize(in containerSize: CGSize) -> CGSize {
        if isCompact {
            return CGSize(width: 82, height: 82)
        }

        let availableWidth = max(containerSize.width - 32, 76)
        return CGSize(width: min(availableWidth, 390), height: 108)
    }

    private func refreshCoverSpin() {
        shouldSpinCover = false

        guard isCompact, isPlaying else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard isCompact, isPlaying else { return }
            shouldSpinCover = true
        }
    }
}

struct PlaybackSessionSettingsView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let close: () -> Void

    private var queueClips: [SoundClip] {
        guard
            let currentClipID = playbackManager.currentClipID,
            let currentIndex = libraryStore.clips.firstIndex(where: { $0.id == currentClipID })
        else {
            return libraryStore.clips
        }

        var clips = libraryStore.clips
        let currentClip = clips.remove(at: currentIndex)
        return [currentClip] + clips
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PlaybackSettingsPanel(title: settingsStore.text(.currentPlaybackList)) {
                        if queueClips.isEmpty {
                            Text(settingsStore.text(.noCurrentPlaybackList))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(VmicTheme.mutedInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(queueClips) { clip in
                                    PlaybackQueueRow(
                                        clip: clip,
                                        artworkDirectory: libraryStore.artworkDirectory,
                                        isCurrent: playbackManager.currentClipID == clip.id,
                                        playbackState: playbackManager.playbackState(for: clip.id),
                                        progress: playbackManager.playbackProgress(for: clip.id),
                                        elapsedTime: playbackManager.elapsedTime(for: clip.id),
                                        duration: playbackManager.duration(for: clip.id) ?? clip.durationSeconds,
                                        playAction: {
                                            playFromQueue(clip)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    PlaybackSettingsPanel(title: settingsStore.text(.playbackMode)) {
                        Picker(settingsStore.text(.playbackMode), selection: $settingsStore.playbackMode) {
                            ForEach(PlaybackMode.allCases) { mode in
                                Text(playbackModeTitle(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(settingsStore.text(.playbackSettingsDetail))
                            .font(.footnote)
                            .foregroundStyle(VmicTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PlaybackSettingsPanel(title: settingsStore.text(.playbackLimit)) {
                        Picker(settingsStore.text(.playbackLimit), selection: $settingsStore.playbackLimitMode) {
                            Text(settingsStore.text(.playbackLimitUnlimited)).tag(PlaybackLimitMode.unlimited)
                            Text(settingsStore.text(.playbackLimitPlayCount)).tag(PlaybackLimitMode.playCount)
                            Text(settingsStore.text(.playbackLimitMinutes)).tag(PlaybackLimitMode.minutes)
                        }
                        .pickerStyle(.segmented)

                        if settingsStore.playbackLimitMode == .playCount {
                            Stepper(value: $settingsStore.playbackLimitCount, in: 1...99) {
                                Text(settingsStore.text(.playbackLimitCountValue(settingsStore.playbackLimitCount)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(VmicTheme.ink)
                            }
                        } else if settingsStore.playbackLimitMode == .minutes {
                            Stepper(value: $settingsStore.playbackLimitMinutes, in: 1...180, step: 1) {
                                Text(settingsStore.text(.playbackLimitMinutesValue(settingsStore.playbackLimitMinutes)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(VmicTheme.ink)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(VmicTheme.drawerBackground)
            .navigationTitle(settingsStore.text(.playbackSettings))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(CompactCloseButtonStyle())
                }
            }
            .vmicOpaqueNavigationBar()
        }
        .background(VmicTheme.drawerBackground.ignoresSafeArea())
    }

    private func playbackModeTitle(_ mode: PlaybackMode) -> String {
        switch mode {
        case .ordered:
            return settingsStore.text(.playbackModeOrdered)
        case .repeatOne:
            return settingsStore.text(.playbackModeRepeatOne)
        case .shuffle:
            return settingsStore.text(.playbackModeShuffle)
        }
    }

    private func playFromQueue(_ clip: SoundClip) {
        if settingsStore.singlePlayback && playbackManager.playbackState(for: clip.id) == nil {
            playbackManager.stopAll()
        }

        playbackManager.toggle(
            clip,
            from: libraryStore.soundsDirectory,
            volume: settingsStore.inputVolume,
            reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
        )
    }
}

private struct PlaybackSettingsPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
    }
}

private struct PlaybackQueueRow: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip
    let artworkDirectory: URL
    let isCurrent: Bool
    let playbackState: SoundPlaybackState?
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
    let playAction: () -> Void

    private var isPlaying: Bool {
        playbackState == .playing
    }

    private var isActive: Bool {
        playbackState != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverArtworkView(artworkURL: clip.artworkURL(in: artworkDirectory), size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)
                    .lineLimit(1)

                Text(clip.artist?.isEmpty == false ? clip.artist! : settingsStore.text(.unknownArtist))
                    .font(.caption)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(isPlaying ? settingsStore.text(.currentPlayback) : settingsStore.text(.audio))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isActive ? VmicTheme.blue : VmicTheme.mutedInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((isActive ? VmicTheme.blue : VmicTheme.mutedInk).opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("\(formatTime(elapsedTime)) / \(formatTime(duration))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(VmicTheme.mutedInk)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 6)

            if isActive {
                ProgressView(value: progress)
                    .tint(VmicTheme.blue)
                    .frame(width: 54)
            }

            Button(action: playAction) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(DockIconButtonStyle())
            .accessibilityLabel(isPlaying ? settingsStore.text(.pause) : settingsStore.text(.play))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(isCurrent ? VmicTheme.blue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func formatTime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }

        let totalSeconds = Int(seconds.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct PlaybackProgressBar: View {
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
    let seekAction: (Double) -> Void

    @State private var dragProgress: Double?

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var displayedProgress: Double {
        dragProgress ?? clampedProgress
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(VmicTheme.blue.opacity(0.14))
                        .frame(height: 4)

                    Capsule()
                        .fill(VmicTheme.blue)
                        .frame(width: max(4, proxy.size.width * displayedProgress), height: 4)

                    Circle()
                        .fill(VmicTheme.blue)
                        .frame(width: 10, height: 10)
                        .offset(x: knobOffset(width: proxy.size.width))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = dragProgress(for: value.location.x, width: proxy.size.width)
                            dragProgress = progress
                            seekAction(progress)
                        }
                        .onEnded { value in
                            let progress = dragProgress(for: value.location.x, width: proxy.size.width)
                            seekAction(progress)
                            dragProgress = nil
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(elapsedTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(VmicTheme.mutedInk)
            .monospacedDigit()
        }
    }

    private func dragProgress(for locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(locationX / width), 0), 1)
    }

    private func knobOffset(width: CGFloat) -> CGFloat {
        let rawOffset = width * displayedProgress - 5
        return min(max(rawOffset, 0), max(width - 10, 0))
    }

    private func formatTime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }

        let totalSeconds = Int(seconds.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct DockIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(VmicTheme.blue)
            .frame(width: 32, height: 32)
            .background(VmicTheme.blue.opacity(configuration.isPressed ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.82, green: 0.20, blue: 0.18))

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
