import Foundation

// MARK: - RSI 루프 (Recursive Self-Improvement, 재귀적 자기개선)
//
// 한 세대(generation)는 네 단계입니다.
//   실행(Act)   : 현재 정책으로 환경의 모든 티켓을 분류한다.
//   채점(Score) : 평가자가 코드로 점수를 매기고 실패 사례를 모은다.
//   수정(Revise): 모델이 실패 사례를 보고 새 정책을 제안한다.
//   판정(Judge) : 새 정책을 다시 채점해 점수가 "오를 때만" 채택한다(언덕 오르기).
// 판정을 모델이 아니라 평가자 점수가 내린다는 점이 이 루프의 안전장치입니다.

nonisolated enum LoopEvent: Sendable {
    case started(world: World, model: String, policy: Policy, generations: Int)
    case trial(TrialResult, generation: Int)
    case critique(failures: [TrialRow], generation: Int)
    case proposal(old: Policy, new: Policy, trace: ModelTrace, generation: Int)
    case decision(accepted: Bool, oldScore: Double, newScore: Double, generation: Int)
    case note(String, generation: Int)
    case finished(policy: Policy, trial: TrialResult)
    case cancelled
    case failed(String)
}

nonisolated struct RSIEngine {
    static let sourcePath = #filePath

    /// 루프를 돌리며 일어나는 모든 일을 순서대로 흘려보냅니다.
    /// 화면(AppModel)은 이 스트림을 그대로 타임라인에 옮겨 적기만 합니다.
    static func run(world: World, model: any LanguageModel, start: Policy, generations: Int) -> AsyncStream<LoopEvent> {
        AsyncStream { continuation in
            let task = Task {
                var current = start
                var nextVersion = start.version + 1
                var attempt = 0
                continuation.yield(.started(world: world, model: model.displayName, policy: start, generations: generations))
                do {
                    // 0세대: 출발점 측정
                    var currentTrial = try await Evaluator.evaluate(current, in: world, with: model)
                    continuation.yield(.trial(currentTrial, generation: 0))

                    for generation in 1...max(generations, 1) {
                        try Task.checkCancellation()
                        if currentTrial.failures.isEmpty {
                            continuation.yield(.note("실패 사례가 없어 조기 종료합니다.", generation: generation))
                            break
                        }
                        // 채점 결과 공유
                        continuation.yield(.critique(failures: currentTrial.failures, generation: generation))

                        // 수정 제안
                        var (proposal, trace) = try await model.revise(current, failures: currentTrial.failures, attempt: attempt)
                        proposal.version = nextVersion
                        nextVersion += 1
                        continuation.yield(.proposal(old: current, new: proposal, trace: trace, generation: generation))

                        // 제안을 같은 환경에서 재채점
                        let trial = try await Evaluator.evaluate(proposal, in: world, with: model)
                        continuation.yield(.trial(trial, generation: generation))

                        // 판정: 점수가 올랐을 때만 채택
                        let accepted = trial.score > currentTrial.score
                        continuation.yield(.decision(accepted: accepted, oldScore: currentTrial.score,
                                                     newScore: trial.score, generation: generation))
                        if accepted {
                            current = proposal
                            currentTrial = trial
                            attempt = 0
                        } else {
                            attempt += 1
                        }
                    }
                    continuation.yield(.finished(policy: current, trial: currentTrial))
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Sim → Real 전이 보고서

/// Sim에서 다듬은 정책을 Real 환경(또는 실제 모델)에서 실행했을 때의 차이.
nonisolated struct TransferReport: Sendable, Hashable {
    let policyVersion: Int
    let simScore: Double
    let realScore: Double
    let realTrial: TrialResult

    /// 현실 격차. 양수면 Sim에서 과대평가된 만큼입니다.
    var gap: Double { simScore - realScore }

    var verdict: String {
        switch gap {
        case ..<0.05: "격차 작음 - 정책이 잘 전이되었습니다."
        case ..<0.25: "격차 보통 - Real에서 몇 세대 더 적응이 필요합니다."
        default: "격차 큼 - Sim 데이터가 현장을 충분히 대표하지 못합니다."
        }
    }
}
