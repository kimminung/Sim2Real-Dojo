import SwiftUI

// MARK: - 루트 화면
//
// 세 칸 구성: 제어판(왼쪽) · RSI 타임라인(가운데) · 정책/코드/모델 호출(오른쪽).
// iPhone처럼 좁은 화면에서는 세 칸을 탭으로 바꿉니다.

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            #if os(iOS)
            TabView {
                Tab("제어판", systemImage: "slider.horizontal.3") { ControlPanelView(model: model) }
                Tab("타임라인", systemImage: "clock.arrow.circlepath") { TimelineView(model: model) }
                Tab("정책·코드", systemImage: "doc.text.magnifyingglass") { PolicyCodeView(model: model) }
            }
            #else
            HStack(spacing: 0) {
                ControlPanelView(model: model)
                    .frame(width: 340)
                Divider()
                TimelineView(model: model)
                    .frame(minWidth: 460)
                Divider()
                PolicyCodeView(model: model)
                    .frame(minWidth: 420)
            }
            #endif
        }
        .sheet(isPresented: $model.showGuide) {
            LearningGuideView()
        }
        .alert("실행할 수 없습니다", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
}
