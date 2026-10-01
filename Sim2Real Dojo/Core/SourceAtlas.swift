import Foundation

// MARK: - 코드 투명성: 개념 ↔ 소스 파일 지도
//
// 교육용 앱의 핵심 약속은 "화면에서 본 것은 전부 코드에서 찾을 수 있다"입니다.
// 각 Core 파일은 `#filePath`로 자기 경로를 노출하고, 이 지도가 개념별로 그 경로와 심벌을 묶습니다.
// 앱이 빌드된 Mac에서는 실제 소스를 읽어 화면에 보여 주고, 다른 기기에서는 저장소 경로를 안내합니다.

nonisolated struct SourceAtlas {
    nonisolated enum Stage: String, CaseIterable, Identifiable, Sendable {
        case world = "환경"
        case policy = "정책"
        case actor = "배우"
        case evaluator = "평가자"
        case reviser = "수정자"
        case loop = "RSI 루프"
        case claude = "Claude 어댑터"
        case transfer = "전이 보고서"

        var id: String { rawValue }
    }

    nonisolated struct Entry: Sendable, Identifiable {
        let stage: Stage
        let path: String
        let symbol: String
        let summary: String

        var id: Stage { stage }
        var fileName: String { (path as NSString).lastPathComponent }
        var repoPath: String { "MyApp/Core/\(fileName)" }
    }

    static let entries: [Entry] = [
        Entry(stage: .world, path: World.sourcePath, symbol: "World, Ticket",
              summary: "Sim/Real 두 환경과 각 12건의 티켓, 정답 라벨. 정답은 모델에게 절대 전달되지 않습니다."),
        Entry(stage: .policy, path: Policy.sourcePath, symbol: "Policy, Rule",
              summary: "개선 대상인 지시문 텍스트. 규칙 줄 파서와 diff. 같은 텍스트가 스크립트 모델의 규칙표이자 Claude의 system 프롬프트입니다."),
        Entry(stage: .actor, path: ScriptedModel.sourcePath, symbol: "ScriptedModel.classify(_:policy:)",
              summary: "배우 역할. 정책의 규칙을 위에서부터 훑어 처음 일치하는 규칙을 적용하고, 없으면 기본값."),
        Entry(stage: .evaluator, path: Evaluator.sourcePath, symbol: "Evaluator.evaluate(_:in:with:)",
              summary: "코드로 채점. category 0.5점 + priority 0.5점. 채택/기각은 오직 이 점수로 결정됩니다."),
        Entry(stage: .reviser, path: ScriptedModel.sourcePath, symbol: "ScriptedModel.revise(_:failures:attempt:)",
              summary: "수정자 역할. 실패 티켓에서 키워드를 뽑아 새 규칙을 맨 위에 추가. 기각이 반복되면 다음 후보 키워드를 시도."),
        Entry(stage: .loop, path: RSIEngine.sourcePath, symbol: "RSIEngine.run(world:model:start:generations:)",
              summary: "실행→채점→수정→판정을 세대 수만큼 반복. 점수가 오를 때만 채택하는 언덕 오르기."),
        Entry(stage: .claude, path: ClaudeModel.sourcePath, symbol: "ClaudeModel",
              summary: "Anthropic Messages API를 URLSession으로 직접 호출. 요청/응답 JSON을 전부 ModelTrace로 기록."),
        Entry(stage: .transfer, path: RSIEngine.sourcePath, symbol: "TransferReport",
              summary: "Sim 점수와 Real 점수의 차이(현실 격차)와 해석."),
    ]

    static func entry(for stage: Stage) -> Entry {
        entries.first { $0.stage == stage }!
    }

    /// 빌드한 Mac에서 실행 중이면 실제 소스를 읽어 옵니다. 아니면 nil.
    static func source(of entry: Entry) -> String? {
        try? String(contentsOfFile: entry.path, encoding: .utf8)
    }
}
