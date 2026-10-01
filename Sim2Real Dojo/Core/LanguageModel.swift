import Foundation

// MARK: - 모델 추상화
//
// RSI 루프는 "어떤 모델이든" 두 가지 역할만 해 주면 돌아갑니다.
//   1. 배우(Actor)   : 정책을 따라 티켓 하나를 분류한다.
//   2. 수정자(Reviser): 실패 사례를 보고 정책을 고쳐 쓴다.
// 스크립트 모델(오프라인)과 실제 Claude(API)가 같은 프로토콜을 구현하므로
// 모델만 바꿔 끼우면 Sim→Real 전이를 실험할 수 있습니다.

/// 모델 호출 한 번의 투명한 기록. 화면의 "모델 호출" 탭에 그대로 표시됩니다.
nonisolated struct ModelTrace: Sendable, Hashable {
    var model: String
    var title: String
    var request: String
    var response: String
}

nonisolated protocol LanguageModel: Sendable {
    var displayName: String { get }

    /// 배우 역할. 정책을 지시문 삼아 티켓 한 건을 분류합니다.
    func classify(_ ticket: Ticket, policy: Policy) async throws -> (Prediction, ModelTrace)

    /// 수정자 역할. 실패 사례를 보고 개선된 정책을 제안합니다.
    /// - attempt: 직전 제안이 기각된 횟수. 같은 제안을 반복하지 않도록 다양성에 씁니다.
    func revise(_ policy: Policy, failures: [TrialRow], attempt: Int) async throws -> (Policy, ModelTrace)
}

// MARK: - 스크립트 모델 (오프라인 · 결정적)
//
// LLM 없이도 전 과정을 체험할 수 있게 만든 "모의 모델"입니다.
// 배우는 정책의 규칙표를 그대로 실행하고, 수정자는 실패한 티켓에서 키워드를 뽑아 규칙을 추가합니다.
// 똑똑하지 않다는 점이 오히려 교육적입니다: 키워드 학습의 과적합과 현실 격차가 그대로 드러납니다.

nonisolated struct ScriptedModel: LanguageModel {
    static let sourcePath = #filePath

    var displayName: String { "스크립트 모델 (오프라인)" }

    /// 한 세대에 추가하는 규칙 수 상한. 작게 두어야 "한 걸음씩 나아지는" 과정이 보입니다.
    var maxNewRulesPerRevision = 3

    func classify(_ ticket: Ticket, policy: Policy) async throws -> (Prediction, ModelTrace) {
        let haystack = ticket.text.lowercased()
        if let rule = policy.rules.first(where: { haystack.contains($0.keyword.lowercased()) }) {
            let trace = ModelTrace(model: displayName,
                                   title: "규칙 일치: \"\(rule.keyword)\"",
                                   request: "티켓 \(ticket.id): \(ticket.text)",
                                   response: "일치한 규칙 → \(rule.line)\n결과: \(rule.prediction.label)")
            return (rule.prediction, trace)
        }
        let trace = ModelTrace(model: displayName,
                               title: "일치 규칙 없음 → 기본값",
                               request: "티켓 \(ticket.id): \(ticket.text)",
                               response: "기본값 적용 → \(policy.fallback.label)")
        return (policy.fallback, trace)
    }

    func revise(_ policy: Policy, failures: [TrialRow], attempt: Int) async throws -> (Policy, ModelTrace) {
        var rules = policy.rules
        var added: [Rule] = []
        var notes: [String] = []
        let existing = Set(rules.map { $0.keyword.lowercased() })

        for failure in failures.sorted(by: { $0.ticket.id < $1.ticket.id }) {
            guard added.count < maxNewRulesPerRevision else { break }
            let addedKeywords = Set(added.map(\.keyword))
            let candidates = Self.keywordCandidates(in: failure.ticket.text)
                .filter { !existing.contains($0.lowercased()) && !addedKeywords.contains($0) }
            guard !candidates.isEmpty else {
                notes.append("\(failure.ticket.id): 쓸 만한 키워드 없음, 건너뜀")
                continue
            }
            // 기각이 반복되면 다음 후보 키워드를 시도합니다. (단순한 탐색 다양성)
            let keyword = candidates[attempt % candidates.count]
            let rule = Rule(keyword: keyword, prediction: failure.ticket.expected)
            added.append(rule)
            notes.append("\(failure.ticket.id): 예측 \(failure.predicted.label) ≠ 정답 \(failure.ticket.expected.label) → 규칙 추가 \(rule.line)")
        }

        // 새 규칙을 맨 위에 넣어 기존 규칙보다 먼저 적용되게 합니다.
        rules.insert(contentsOf: added, at: 0)
        let proposal = policy.replacingRules(with: rules)
        let trace = ModelTrace(model: displayName,
                               title: "규칙 \(added.count)개 추가 제안 (시도 \(attempt + 1))",
                               request: "실패 \(failures.count)건:\n" + failures.map { "· \($0.ticket.id) \($0.ticket.text)" }.joined(separator: "\n"),
                               response: notes.joined(separator: "\n"))
        return (proposal, trace)
    }

    // MARK: 키워드 추출 - 의도적으로 단순합니다.

    /// 뽑지 않을 토큰. 어느 티켓에나 등장할 수 있어 규칙으로 쓰면 오분류를 만듭니다.
    static let stopwords: Set<String> = [
        "확인", "확인해", "부탁드립니다", "부탁드려요", "주세요", "해주세요", "안", "아직", "아직도", "계속", "그냥",
        "진짜", "좀", "때문에", "어떻게", "있습니다", "됩니다", "같아요", "왔어요", "안와요", "싶어요", "ㅠㅠ",
        "하나요", "되나요", "번", "것", "상태로", "도착했습니다", "처리", "요청합니다", "않아요", "안됨", "뜸",
    ]

    /// 끝에 붙은 조사를 떼어 어근만 남깁니다. (예: "비밀번호를" → "비밀번호")
    static let particles = ["에서", "으로", "이", "가", "을", "를", "은", "는", "에", "의", "도", "만", "로"]

    static func keywordCandidates(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "," }) {
            var token = raw.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            for particle in particles where token.count > particle.count + 1 && token.hasSuffix(particle) {
                token.removeLast(particle.count)
                break
            }
            guard token.count >= 2, !stopwords.contains(token), !seen.contains(token),
                  token.rangeOfCharacter(from: .letters) != nil else { continue }
            seen.insert(token)
            result.append(token)
        }
        return result
    }
}
