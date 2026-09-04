import SwiftUI

struct SettingsDrawer: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    SettingsNavigationRow {
                        ThemeSettingsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.theme),
                            detail: themeTitle(settingsStore.themeMode),
                            systemImage: "paintpalette"
                        )
                    }

                    SettingsNavigationRow {
                        LanguageSettingsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.language),
                            detail: settingsStore.language.displayName,
                            systemImage: "globe"
                        )
                    }

                    SettingsNavigationRow {
                        PlaybackSettingsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.playback),
                            detail: settingsStore.text(.singlePlayback),
                            systemImage: "play.circle"
                        )
                    }

                    SettingsNavigationRow {
                        ListSettingsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.list),
                            detail: settingsStore.text(.showDuration),
                            systemImage: "list.bullet"
                        )
                    }

                    SettingsNavigationRow {
                        FloatingWindowSettingsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.floatingWindow),
                            detail: settingsStore.floatingWindowEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled),
                            systemImage: "pip"
                        )
                    }

                    SettingsNavigationRow {
                        AboutSettingsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.about),
                            detail: "vmic",
                            systemImage: "info.circle"
                        )
                    }

                    SettingsNavigationRow(showSeparator: false) {
                        DebugDiagnosticsView()
                    } label: {
                        SettingsLinkRow(
                            title: settingsStore.text(.debug),
                            detail: settingsStore.text(.injectionChannel),
                            systemImage: "stethoscope"
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(VmicTheme.drawerBackground)
            .navigationTitle(settingsStore.text(.settings))
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
        .background(VmicTheme.drawerBackground)
    }

    private func themeTitle(_ theme: AppThemeMode) -> String {
        switch theme {
        case .system:
            return settingsStore.text(.themeSystem)
        case .light:
            return settingsStore.text(.themeLight)
        case .dark:
            return settingsStore.text(.themeDark)
        }
    }
}

private struct SettingsNavigationRow<Destination: View, Label: View>: View {
    let showSeparator: Bool
    let destination: () -> Destination
    let label: () -> Label

    init(
        showSeparator: Bool = true,
        @ViewBuilder _ destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.showSeparator = showSeparator
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 0) {
                label()
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showSeparator {
                    Rectangle()
                        .fill(VmicTheme.separator)
                        .frame(height: 1)
                        .padding(.leading, 46)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                ForEach(AppThemeMode.allCases) { theme in
                    Button {
                        settingsStore.themeMode = theme
                    } label: {
                        HStack {
                            Text(title(theme))
                                .foregroundStyle(VmicTheme.ink)

                            Spacer()

                            if settingsStore.themeMode == theme {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(VmicTheme.blue)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.drawerBackground)
        .navigationTitle(settingsStore.text(.theme))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }

    private func title(_ theme: AppThemeMode) -> String {
        switch theme {
        case .system:
            return settingsStore.text(.themeSystem)
        case .light:
            return settingsStore.text(.themeLight)
        case .dark:
            return settingsStore.text(.themeDark)
        }
    }
}

private struct LanguageSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        settingsStore.language = language
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .foregroundStyle(VmicTheme.ink)

                            Spacer()

                            if settingsStore.language == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(VmicTheme.blue)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.drawerBackground)
        .navigationTitle(settingsStore.text(.language))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }
}

private struct PlaybackSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                SettingsVolumeRow()

                SettingsToggleRow(
                    title: settingsStore.text(.singlePlayback),
                    detail: settingsStore.text(.singlePlaybackDetail),
                    isOn: $settingsStore.singlePlayback
                )
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.drawerBackground)
        .navigationTitle(settingsStore.text(.playback))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }
}

private struct ListSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                SettingsToggleRow(
                    title: settingsStore.text(.showDuration),
                    detail: settingsStore.text(.showDurationDetail),
                    isOn: $settingsStore.showDuration
                )
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.drawerBackground)
        .navigationTitle(settingsStore.text(.list))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }
}

private struct FloatingWindowSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                SettingsToggleRow(
                    title: settingsStore.text(.backgroundFloatingWindow),
                    detail: settingsStore.text(.backgroundFloatingWindowDetail),
                    isOn: $settingsStore.floatingWindowEnabled
                )

                SettingsToggleRow(
                    title: settingsStore.text(.showFloatingDockInDebug),
                    detail: settingsStore.text(.showFloatingDockInDebugDetail),
                    isOn: $settingsStore.showFloatingDockInDebug
                )
            }
            .listRowBackground(Color.clear)

            Section {
                Text(settingsStore.text(.floatingWindowSystemNote))
                    .font(.footnote)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.drawerBackground)
        .navigationTitle(settingsStore.text(.floatingWindow))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }
}

private struct AboutSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("vmic")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(VmicTheme.ink)

                    Text(settingsStore.text(.aboutDetail))
                        .font(.subheadline)
                        .foregroundStyle(VmicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                HStack {
                    Text(settingsStore.text(.version))
                        .foregroundStyle(VmicTheme.ink)

                    Spacer()

                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        .foregroundStyle(VmicTheme.mutedInk)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                if let url = URL(string: "https://github.com/hatsune-miku/cakedesign-skill") {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Text("Proudly Crafted With CakeDesign.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(VmicTheme.mutedInk)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VmicTheme.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.drawerBackground)
        .navigationTitle(settingsStore.text(.about))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VmicTheme.blue)
                .frame(width: 34, height: 34)
                .background(VmicTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(VmicTheme.mutedInk.opacity(0.62))
        }
    }
}

private struct SettingsVolumeRow: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(settingsStore.text(.inputVolume))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Spacer()

                Text(settingsStore.text(.volumePercent(Int((settingsStore.inputVolume * 100).rounded()))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()
            }

            Slider(value: $settingsStore.inputVolume, in: 0...1)
                .tint(VmicTheme.blue)

            Text(settingsStore.text(.inputVolumeDetail))
                .font(.caption)
                .foregroundStyle(VmicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String

    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(VmicTheme.blue)
    }
}

struct CompactCloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.semibold))
            .foregroundStyle(VmicTheme.blue)
            .frame(width: 26, height: 26)
            .background(VmicTheme.blue.opacity(configuration.isPressed ? 0.18 : 0.10), in: Circle())
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
