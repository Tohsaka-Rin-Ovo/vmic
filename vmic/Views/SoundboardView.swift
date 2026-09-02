import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SoundboardView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var editMode: EditMode = .inactive
    @State private var isImporterPresented = false
    @State private var clipBeingRenamed: SoundClip?
    @State private var renameText = ""
    @State private var showsSortingNotice = false

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
                    PlayerHeader(activeClips: activeClips)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    InjectionControlPanel()
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

                if libraryStore.clips.isEmpty {
                    Section {
                        EmptySoundboardView(importAction: {
                            isImporterPresented = true
                        })
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
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
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.bottom, currentClip == nil ? 0 : 84)

            if let currentClip {
                VStack {
                    Spacer()
                    BottomNowPlayingBar(
                        clip: currentClip,
                        artworkDirectory: libraryStore.artworkDirectory,
                        playbackState: playbackManager.playbackState(for: currentClip.id),
                        volume: $settingsStore.inputVolume,
                        togglePlayback: {
                            togglePlayback(currentClip)
                        },
                        stopAction: {
                            playbackManager.stop(currentClip)
                        },
                        importAction: {
                            isImporterPresented = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }

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
        .task {
            playbackManager.setOutputVolume(settingsStore.inputVolume)
        }
        .onChange(of: settingsStore.inputVolume) { _, newValue in
            playbackManager.setOutputVolume(newValue)
        }
        .navigationTitle("vmic")
        .navigationBarTitleDisplayMode(.inline)
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

        playbackManager.toggle(clip, from: libraryStore.soundsDirectory, volume: settingsStore.inputVolume)
    }
}

private struct PlayerHeader: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let activeClips: [SoundClip]

    private var title: String {
        activeClips.first?.title ?? settingsStore.text(.readyToBridgeAudio)
    }

    private var subtitle: String {
        if activeClips.count > 1 {
            return settingsStore.text(.soundsPlaying(activeClips.count))
        }

        if injectionManager.isInjectionEnabled {
            return settingsStore.text(.injectionEnabled)
        }

        return settingsStore.text(.selectSoundToPlay)
    }

    private var isTitlePlaying: Bool {
        guard let clip = activeClips.first else { return false }
        return playbackManager.playbackState(for: clip.id) == .playing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                CoverArtworkView(
                    artworkURL: activeClips.first?.artworkURL(in: libraryStore.artworkDirectory),
                    size: 104
                )

                VStack(alignment: .leading, spacing: 8) {
                    MarqueeText(
                        title,
                        font: .title2.weight(.bold),
                        color: VmicTheme.ink,
                        isActive: isTitlePlaying
                    )
                    .frame(height: 34, alignment: .center)

                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(VmicTheme.mutedInk)
                        .lineLimit(1)
                }

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
            }
        }
        .padding(18)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
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
            if let artworkURL, let image = UIImage(contentsOfFile: artworkURL.path) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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

private struct BottomNowPlayingBar: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip
    let artworkDirectory: URL
    let playbackState: SoundPlaybackState?
    @Binding var volume: Double
    let togglePlayback: () -> Void
    let stopAction: () -> Void
    let importAction: () -> Void

    private var isPlaying: Bool {
        playbackState == .playing
    }

    var body: some View {
        VStack(spacing: 8) {
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

                Spacer(minLength: 6)

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(TransportIconButtonStyle(isActive: true))

                Button(action: importAction) {
                    Image(systemName: "plus")
                }
                .buttonStyle(CompactTransportButtonStyle())
                .accessibilityLabel(settingsStore.text(.importAudio))

                Button(action: stopAction) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(CompactTransportButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)

                Slider(value: $volume, in: 0...1)
                    .tint(VmicTheme.blue)

                Text(settingsStore.text(.volumePercent(Int((volume * 100).rounded()))))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        }
    }
}

private struct CompactTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(VmicTheme.blue)
            .frame(width: 34, height: 34)
            .background(VmicTheme.blue.opacity(configuration.isPressed ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct TransportIconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isActive ? Color.white : VmicTheme.mutedInk)
            .frame(width: 48, height: 48)
            .background(
                isActive ? VmicTheme.ink.opacity(configuration.isPressed ? 0.84 : 1) : Color.white.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
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
