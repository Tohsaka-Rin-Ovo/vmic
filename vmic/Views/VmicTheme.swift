import SwiftUI
import UIKit

enum VmicTheme {
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1)
            : UIColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1)
    })
    static let mutedInk = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.70, blue: 0.82, alpha: 1)
            : UIColor(red: 0.34, green: 0.41, blue: 0.52, alpha: 1)
    })
    static let blue = Color(red: 0.08, green: 0.34, blue: 0.78)
    static let brightBlue = Color(red: 0.12, green: 0.48, blue: 0.92)
    static let paleBlue = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.16, blue: 0.28, alpha: 1)
            : UIColor(red: 0.91, green: 0.96, blue: 1.00, alpha: 1)
    })
    static let cyan = Color(red: 0.21, green: 0.73, blue: 0.92)
    static let mint = Color(red: 0.16, green: 0.72, blue: 0.62)
    static let surface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.11, blue: 0.18, alpha: 0.88)
            : UIColor(white: 1, alpha: 0.86)
    })
    static let drawerBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 0.96)
            : UIColor(red: 0.96, green: 0.99, blue: 1.00, alpha: 0.98)
    })
    static let separator = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.28, blue: 0.40, alpha: 0.50)
            : UIColor(red: 0.75, green: 0.84, blue: 0.94, alpha: 0.55)
    })

    static var appBackground: some View {
        LinearGradient(
            colors: [
                Color(UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.03, green: 0.07, blue: 0.13, alpha: 1)
                        : UIColor(red: 0.88, green: 0.95, blue: 1.00, alpha: 1)
                }),
                Color(UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 1)
                        : UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 1)
                })
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
