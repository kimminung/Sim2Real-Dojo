import Foundation

// MARK: - 평가자(Evaluator)
//
// 정책이 환경의 티켓을 얼마나 잘 분류했는지 코드로 채점합니다.
// 모델이 스스로 매기는 점수가 아니라 "코드가 매기는 점수"라는 점이 중요합니다.
// RSI 루프에서 채택/기각 판정은 전적으로 이 점수에 따릅니다.

/// 티켓 한 건에 대한 실행 결과.
nonisolated struct TrialRow: Sendable, Hashable, Identifiable {
    let ticket: Ticket
    let predicted: Prediction
    let trace: ModelTrace

    var id: String { ticket.id }
    var categoryCorrect: Bool { predicted.category == ticket.expected.category }
    var priorityCorrect: Bool { predicted.priority == ticket.expected.priority }
    var isExact: Bool { categoryCorrect && priorityCorrect }

    /// category 0.5점 + priority 0.5점. 부분 점수를 주어야 "조금 나아짐"이 보입니다.
    var points: Double { (categoryCorrect ? 0.5 : 0) + (priorityCorrect ? 0.5 : 0) }
}

/// 정책 한 버전을 환경 하나에서 끝까지 실행한 결과.
nonisolated struct TrialResult: Sendable, Hashable {
    let policyVersion: Int
    let world: World
    let rows: [TrialRow]

    /// 0.0 ... 1.0
    var score: Double {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0) { $0 + $1.points } / Double(rows.count)
    }

    var exactCount: Int { rows.filter(\.isExact).count }
    var failures: [TrialRow] { rows.filter { !$0.isExact } }
    var percentText: String { String(format: "%.0f%%", score * 100) }
}

nonisolated enum Evaluator {
    static let sourcePath = #filePath

    /// 정책을 환경의 모든 티켓에 적용하고 채점합니다.
    /// 모델 호출은 네트워크일 수 있으므로 순차적으로 실행하고, 중간 취소를 존중합니다.
    static func evaluate(_ policy: Policy, in world: World, with model: any LanguageModel) async throws -> TrialResult {
        var rows: [TrialRow] = []
        for ticket in world.tickets {
            try Task.checkCancellation()
            let (predicted, trace) = try await model.classify(ticket, policy: policy)
            rows.append(TrialRow(ticket: ticket, predicted: predicted, trace: trace))
        }
        return TrialResult(policyVersion: policy.version, world: world, rows: rows)
    }
}
