import SwiftUI

enum VmicTheme {
    static let ink = Color(red: 0.06, green: 0.10, blue: 0.18)
    static let mutedInk = Color(red: 0.34, green: 0.41, blue: 0.52)
    static let blue = Color(red: 0.08, green: 0.34, blue: 0.78)
    static let brightBlue = Color(red: 0.12, green: 0.48, blue: 0.92)
    static let paleBlue = Color(red: 0.91, green: 0.96, blue: 1.00)
    static let cyan = Color(red: 0.21, green: 0.73, blue: 0.92)
    static let mint = Color(red: 0.16, green: 0.72, blue: 0.62)
    static let surface = Color.white.opacity(0.86)

    static var appBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.95, blue: 1.00),
                Color(red: 0.98, green: 0.99, blue: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct BlueProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [VmicTheme.blue, VmicTheme.brightBlue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(VmicTheme.blue)
            .frame(width: 44, height: 44)
            .background(VmicTheme.blue.opacity(configuration.isPressed ? 0.18 : 0.10), in: Circle())
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
