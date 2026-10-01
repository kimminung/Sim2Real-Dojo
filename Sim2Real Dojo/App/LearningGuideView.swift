import SwiftUI

// MARK: - 학습 가이드
//
// 직원 교육용 커리큘럼. 각 장은 "개념 → 화면에서 확인 → 코드 위치 → 실습" 순서입니다.

struct GuideChapter: Identifiable {
    let id: Int
    let title: String
    let concept: String
    let watch: String
    let code: [SourceAtlas.Stage]
    let exercise: String

    static let all: [GuideChapter] = [
        GuideChapter(
            id: 1, title: "Sim-to-Real이란",
            concept: """
            로봇공학에서 Sim-to-Real은 "시뮬레이터에서 싸게 배운 것을 현실로 옮기는 일"입니다. \
            LLM 운영에서도 같습니다. 정제된 샘플(Sim)로 프롬프트를 다듬은 뒤 현장 데이터(Real)와 실제 모델에 올리면 \
            점수가 떨어지는데, 그 차이가 '현실 격차(reality gap)'입니다. 이 앱은 두 축을 분리해 보여 줍니다. \
            환경 축(Sim 티켓 ↔ Real 티켓)과 모델 축(스크립트 모델 ↔ 실제 Claude).
            """,
            watch: "왼쪽 '1. 환경'에서 Sim/Real을 바꾸며 설명 문구를 읽으세요. '4. 전이' 카드의 현실 격차 숫자가 핵심 지표입니다.",
            code: [.world, .transfer],
            exercise: "리셋 후 정책 v1을 그대로 'Real로 전이'하세요. Sim 점수와 Real 점수를 적어 두고, 왜 다른지 티켓별 채점표에서 두 건을 골라 설명해 보세요."
        ),
        GuideChapter(
            id: 2, title: "RSI 루프: 실행→채점→수정→판정",
            concept: """
            재귀적 자기개선(Recursive Self-Improvement)은 모델이 자기 결과를 보고 자기 지시문을 고치는 반복입니다. \
            위험한 말처럼 들리지만, 이 앱의 루프에는 안전장치가 있습니다. (1) 고치는 대상은 가중치가 아니라 텍스트 정책, \
            (2) 점수는 모델이 아니라 코드(평가자)가 매김, (3) 점수가 오를 때만 채택(언덕 오르기). \
            그래서 나빠지는 변경은 절대 살아남지 못합니다.
            """,
            watch: "타임라인에서 G1의 네 항목(채점 결과 공유 → 정책 수정 제안 → 제안 채점 → 채택/기각)을 순서대로 펼쳐 보세요.",
            code: [.loop, .evaluator],
            exercise: "세대 수를 8로 올리고 Sim에서 RSI를 실행하세요. 몇 세대에서 100%에 도달하는지, 조기 종료 메모가 뜨는지 확인하세요."
        ),
        GuideChapter(
            id: 3, title: "정책 = 프롬프트, 그리고 규칙표",
            concept: """
            개선되는 것은 Policy.text 한 덩어리입니다. 같은 텍스트가 스크립트 모델에게는 파싱 가능한 규칙표(`- "키워드" → 분류 / 우선순위`)이고, \
            Claude에게는 system 프롬프트입니다. 형식을 하나로 맞춰 두었기 때문에 Sim에서 배운 정책을 손대지 않고 Real 모델로 옮길 수 있습니다. \
            이것이 전이의 전제 조건입니다: 정책의 표현 형식이 두 세계에서 같아야 합니다.
            """,
            watch: "오른쪽 '정책' 탭에서 규칙 줄이 위에 쌓이는 모습을 보세요. 위에 있을수록 먼저 적용됩니다.",
            code: [.policy, .actor],
            exercise: "정책 탭에서 규칙 하나를 직접 추가하고(예: - \"택배\" → 배송 / 보통) 'Real에서 채점'을 누르세요. 점수가 어떻게 바뀌나요?"
        ),
        GuideChapter(
            id: 4, title: "평가자: 코드가 점수를 매긴다",
            concept: """
            Evaluator는 category 0.5점 + priority 0.5점으로 채점합니다. 부분 점수를 주는 이유는 '조금 나아짐'이 보여야 언덕 오르기가 \
            작동하기 때문입니다. 정답(expected)은 Ticket 안에 있지만 모델에게는 절대 전달되지 않습니다. \
            평가자가 모델 바깥에 있다는 사실이 RSI를 안전하게 만듭니다.
            """,
            watch: "타임라인의 '제안 채점' 항목을 펼쳐 티켓별 ✓/−/✗ 아이콘과 '어떤 규칙이 일치했는지'를 확인하세요.",
            code: [.evaluator, .world],
            exercise: "만약 평가자가 priority를 무시하고 category만 채점한다면 어떤 정책이 채택될지 예상해 보고, 코드에서 어느 줄을 고치면 되는지 찾아보세요."
        ),
        GuideChapter(
            id: 5, title: "수정자와 과적합",
            concept: """
            스크립트 수정자는 실패한 티켓에서 키워드를 뽑아 규칙을 추가합니다. 단순해서 좋은 점은, 키워드 학습의 함정이 그대로 보인다는 것입니다. \
            Sim에서 '오늘'이라는 단어로 긴급을 배우면 Real에서 '오늘 생일인데'는 맞히지만 다른 문맥에서는 틀립니다. \
            제안이 기각되면 attempt가 올라가 다음 후보 키워드를 시도합니다. 이것이 가장 단순한 탐색 다양성입니다.
            """,
            watch: "'정책 수정 제안' 항목의 diff에서 어떤 키워드가 선택됐는지, '기각' 뒤 다음 세대에서 키워드가 바뀌는지 보세요.",
            code: [.reviser],
            exercise: "Real 환경에서 RSI를 2세대 실행한 뒤 추가된 규칙을 읽어 보세요. 사람이라면 절대 쓰지 않을 키워드가 있나요? 그 규칙이 다른 티켓을 어떻게 망칠 수 있을지 토론하세요."
        ),
        GuideChapter(
            id: 6, title: "현실 격차 줄이기: 실제 Claude로 전환",
            concept: """
            모델 축을 바꿔 봅시다. '2. 모델'에서 Claude API를 고르고 키를 넣으면 같은 정책이 실제 모델의 system 프롬프트가 됩니다. \
            ClaudeModel은 Anthropic Messages API를 URLSession으로 직접 호출하고 요청/응답 JSON을 전부 기록합니다. \
            실제 모델은 키워드가 아니라 의미를 읽기 때문에 '택배'를 배송으로 이해합니다. \
            격차가 줄어드는지, 오히려 다른 종류의 오류가 생기는지 관찰하세요.
            """,
            watch: "'모델 호출' 탭에서 실제 HTTP 요청 본문(model, system, output_config, fallbacks)과 응답(content, stop_reason, usage)을 읽으세요.",
            code: [.claude],
            exercise: "스크립트 모델로 Sim에서 다듬은 정책을 그대로 두고, 모델만 Claude로 바꿔 'Real로 전이'하세요. 두 전이 결과를 표로 비교하세요."
        ),
    ]
}

struct LearningGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int? = 1

    var body: some View {
        NavigationSplitView {
            List(GuideChapter.all, selection: $selection) { chapter in
                Label("\(chapter.id). \(chapter.title)", systemImage: "\(chapter.id).circle")
                    .tag(chapter.id)
            }
            .navigationTitle("학습 가이드")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let chapter = GuideChapter.all.first(where: { $0.id == selection }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(chapter.title).font(.title2.bold())
                        guideSection("개념", systemImage: "lightbulb", text: chapter.concept)
                        guideSection("화면에서 확인", systemImage: "eye", text: chapter.watch)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("코드 위치", systemImage: "chevron.left.forwardslash.chevron.right").font(.headline)
                            ForEach(chapter.code) { stage in
                                let entry = SourceAtlas.entry(for: stage)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(stage.rawValue).font(.caption.bold()).frame(width: 80, alignment: .leading)
                                    VStack(alignment: .leading) {
                                        Text("\(entry.repoPath) · \(entry.symbol)").font(.caption.monospaced())
                                        Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        guideSection("실습", systemImage: "figure.walk", text: chapter.exercise)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("장을 선택하세요", systemImage: "book")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("닫기") { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 820, minHeight: 560)
        #endif
    }

    private func guideSection(_ title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.headline)
            Text(text).font(.body).textSelection(.enabled)
        }
    }
}
