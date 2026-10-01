import SwiftUI

/// 심투리얼 도장 (Sim2Real Dojo)
/// Sim에서 정책을 재귀적으로 개선(RSI)하고 Real로 전이해 현실 격차를 재는 교육용 앱.
@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS) || os(visionOS)
        .defaultSize(width: 1360, height: 840)
        #endif
    }
}
