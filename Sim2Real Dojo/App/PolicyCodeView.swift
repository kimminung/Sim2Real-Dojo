import SwiftUI

// MARK: - 오른쪽 패널: 정책 · 코드 · 모델 호출
//
// "정책" 탭에서는 RSI가 고친 지시문을 직접 읽고 손으로 고쳐 볼 수 있습니다.
// "코드" 탭은 화면의 각 개념이 어느 소스 파일의 어느 심벌인지 보여 주고, 빌드한 Mac에서는 실제 소스를 읽어 옵니다.
// "모델 호출" 탭은 마지막 모델 호출의 요청/응답 전문입니다.

struct PolicyCodeView: View {
    @Bindable var model: AppModel

    enum Tab: String, CaseIterable, Identifiable {
        case policy = "정책", code = "코드", trace = "모델 호출"
        var id: String { rawValue }
    }

    @State private var tab: Tab = {
        #if DEBUG
        // 스크린샷·데모용: `-showCode` 인자로 실행하면 코드 탭을 먼저 보여 줍니다.
        if CommandLine.arguments.contains("-showCode") { return .code }
        #endif
        return .policy
    }()
    @State private var stage: SourceAtlas.Stage = .loop

    var body: some View {
        VStack(spacing: 0) {
            Picker("탭", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch tab {
            case .policy: policyTab
            case .code: codeTab
            case .trace: traceTab
            }
        }
    }

    // MARK: 정책

    private var policyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("정책 v\(model.policy.version)")
                    .font(.headline)
                Text("규칙 \(model.policy.rules.count)개 · 기본값 \(model.policy.fallback.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("출발점으로") { model.policy = .seed; model.bestSimScore = nil }
                    .font(.caption)
                    .disabled(model.isRunning)
            }
            Text("이 텍스트가 스크립트 모델에게는 규칙표, Claude에게는 system 프롬프트입니다. 직접 고친 뒤 아래 버튼으로 채점해 보세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $model.policy.text)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .disabled(model.isRunning)

            HStack {
                Button("Sim에서 채점") { model.evaluateOnly(in: .sim) }
                Button("Real에서 채점") { model.evaluateOnly(in: .real) }
                Spacer()
            }
            .disabled(model.isRunning)
        }
        .padding([.horizontal, .bottom])
    }

    // MARK: 코드

    private var codeTab: some View {
        let entry = SourceAtlas.entry(for: stage)
        return VStack(alignment: .leading, spacing: 8) {
            Picker("개념", selection: $stage) {
                ForEach(SourceAtlas.Stage.allCases) { Text($0.rawValue).tag($0) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Label(entry.repoPath, systemImage: "doc.text")
                    .font(.caption.monospaced())
                Label(entry.symbol, systemImage: "function")
                    .font(.caption.monospaced())
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)

            if let source = SourceAtlas.source(of: entry) {
                ScrollView([.vertical, .horizontal]) {
                    Text(source)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("소스를 이 기기에서 읽을 수 없습니다", systemImage: "externaldrive.badge.questionmark",
                                       description: Text("빌드한 Mac에서만 실제 파일을 읽습니다. 저장소의 \(entry.repoPath) 를 여세요."))
            }
        }
        .padding([.horizontal, .bottom])
    }

    // MARK: 모델 호출

    private var traceTab: some View {
        Group {
            if let trace = model.lastTrace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(trace.title).font(.headline)
                        Text(trace.model).font(.caption).foregroundStyle(.secondary)
                        Text("요청").font(.caption.bold())
                        Text(trace.request)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        Text("응답").font(.caption.bold())
                        Text(trace.response)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding([.horizontal, .bottom])
                }
            } else {
                ContentUnavailableView("아직 모델 호출이 없습니다", systemImage: "waveform.path.ecg",
                                       description: Text("RSI를 실행하면 마지막 호출의 요청/응답 전문이 여기 표시됩니다. Claude API를 쓰면 실제 HTTP JSON이 보입니다."))
            }
        }
    }
}
