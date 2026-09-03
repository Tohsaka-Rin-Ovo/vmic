import SwiftUI

@MainActor
final class AppChromeStore: ObservableObject {
    @Published var isDebugPageVisible = false
}
