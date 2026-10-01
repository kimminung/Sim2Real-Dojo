import SwiftUI
import Observation

// MARK: - 화면 상태
//
// AppModel은 Core(엔진)와 SwiftUI 화면 사이의 번역기입니다.
// 엔진이 흘려보내는 LoopEvent를 타임라인 항목과 차트 점으로 옮겨 적을 뿐,
// 분류·채점·수정 로직은 전부 Core에 있습니다.

@Observable @MainActor
final class AppModel {

    enum Backend: String, CaseIterable, Identifiable {
        case scripted = "스크립트 모델"
        case claude = "Claude API"
        var id: String { rawValue }
    }

    struct TimelineItem: Identifiable {
        enum Kind { case start, trial, critique, proposal, accepted, rejected, note, transfer, finished, error }

        let id = UUID()
        let generation: Int
        let kind: Kind
        let title: String
        let detail: String
        var trial: TrialResult? = nil
        var trace: ModelTrace? = nil
        var diff: [Policy.DiffLine]? = nil
        var failures: [TrialRow]? = nil

        var symbol: String {
            switch kind {
            case .start: "flag.fill"
            case .trial: "checklist"
            case .critique: "magnifyingglass"
            case .proposal: "pencil.and.outline"
            case .accepted: "arrow.up.circle.fill"
            case .rejected: "xmark.circle"
            case .note: "info.circle"
            case .transfer: "arrow.left.arrow.right.circle.fill"
            case .finished: "flag.checkered"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch kind {
            case .accepted, .finished: .green
            case .rejected: .orange
            case .error: .red
            case .transfer: .purple
            case .proposal: .blue
            default: .secondary
            }
        }
    }

    struct ScorePoint: Identifiable {
        let id = UUID()
        let generation: Int
        let world: World
        let score: Double
        let accepted: Bool
    }

    // MARK: 설정

    var world: World = .sim
    var backend: Backend = .scripted
    var claudeModelID: ClaudeModelID = .opus5
    /// 메모리에만 보관합니다. 환경 변수 ANTHROPIC_API_KEY가 있으면 그것을 초기값으로 씁니다.
    var apiKey: String = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    var generations = 4

    // MARK: 상태

    var policy: Policy = .seed
    var items: [TimelineItem] = []
    var scores: [ScorePoint] = []
    var bestSimScore: Double?
    var transfer: TransferReport?
    var lastTrace: ModelTrace?
    var isRunning = false
    var statusText = "준비됨. 환경과 모델을 고르고 RSI를 실행하세요."
    var showGuide = false
    var errorMessage: String?

    private var runTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("-showGuide") { showGuide = true }
        if CommandLine.arguments.contains("-autoDemo") { Task { await autoDemo() } }
        #endif
    }

    var canUseClaude: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 현재 설정에 맞는 모델을 만듭니다. Sim→Real 전이의 "Real 모델" 축이 여기서 갈립니다.
    func makeModel() throws -> any LanguageModel {
        switch backend {
        case .scripted:
            return ScriptedModel()
        case .claude:
            guard canUseClaude else { throw ClaudeAPIError(message: "Claude API 키를 입력하세요.") }
            return ClaudeModel(apiKey: apiKey, modelID: claudeModelID)
        }
    }

    // MARK: 동작

    /// 현재 환경에서 RSI 루프를 돌립니다.
    func runRSI() {
        guard !isRunning else { return }
        let model: any LanguageModel
        do { model = try makeModel() } catch { errorMessage = error.localizedDescription; return }

        isRunning = true
        statusText = "\(world.rawValue) 환경에서 RSI \(generations)세대 실행 중…"
        let stream = RSIEngine.run(world: world, model: model, start: policy, generations: generations)
        runTask = Task {
            for await event in stream { handle(event) }
            isRunning = false
            runTask = nil
        }
    }

    /// 루프 없이 현재 정책을 한 환경에서 채점만 합니다. (정책을 손으로 고쳐 본 뒤 확인할 때)
    func evaluateOnly(in target: World) {
        guard !isRunning else { return }
        let model: any LanguageModel
        do { model = try makeModel() } catch { errorMessage = error.localizedDescription; return }

        isRunning = true
        statusText = "\(target.rawValue) 환경에서 정책 v\(policy.version) 평가 중…"
        let policy = policy
        runTask = Task {
            do {
                let trial = try await Evaluator.evaluate(policy, in: target, with: model)
                append(trialItem(trial, generation: 0, title: "\(target.rawValue) 단독 평가 · 정책 v\(trial.policyVersion)"))
                lastTrace = trial.rows.last?.trace
                if target == .sim { bestSimScore = trial.score }
                statusText = "\(target.rawValue) 평가 완료: \(trial.percentText)"
            } catch {
                append(TimelineItem(generation: 0, kind: .error, title: "평가 실패", detail: error.localizedDescription))
                statusText = "평가 실패"
            }
            isRunning = false
            runTask = nil
        }
    }

    /// Sim에서 다듬은 현재 정책을 Real 환경에서 실행하고 현실 격차를 계산합니다.
    func transferToReal() {
        guard !isRunning else { return }
        let model: any LanguageModel
        do { model = try makeModel() } catch { errorMessage = error.localizedDescription; return }

        isRunning = true
        statusText = "정책 v\(policy.version)을 Real 환경으로 전이 중…"
        let policy = policy
        runTask = Task {
            do {
                // Sim 점수가 없으면(정책을 손으로 고친 경우 등) 먼저 측정합니다.
                let simScore: Double
                if let bestSimScore { simScore = bestSimScore } else {
                    let simTrial = try await Evaluator.evaluate(policy, in: .sim, with: model)
                    simScore = simTrial.score
                    bestSimScore = simScore
                    append(trialItem(simTrial, generation: 0, title: "전이 전 Sim 기준점 · 정책 v\(policy.version)"))
                }
                let realTrial = try await Evaluator.evaluate(policy, in: .real, with: model)
                let report = TransferReport(policyVersion: policy.version, simScore: simScore,
                                            realScore: realTrial.score, realTrial: realTrial)
                transfer = report
                lastTrace = realTrial.rows.last?.trace
                scores.append(ScorePoint(generation: 0, world: .real, score: realTrial.score, accepted: true))
                var item = trialItem(realTrial, generation: 0, title: "Sim → Real 전이 · 정책 v\(policy.version)")
                item = TimelineItem(generation: 0, kind: .transfer, title: item.title,
                                    detail: String(format: "Sim %.0f%% → Real %.0f%% · 현실 격차 %+.0f%%p. %@",
                                                   simScore * 100, realTrial.score * 100, report.gap * 100, report.verdict),
                                    trial: realTrial)
                append(item)
                statusText = "전이 완료. 현실 격차 \(String(format: "%.0f", report.gap * 100))%p"
            } catch {
                append(TimelineItem(generation: 0, kind: .error, title: "전이 실패", detail: error.localizedDescription))
                statusText = "전이 실패"
            }
            isRunning = false
            runTask = nil
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    func reset() {
        cancel()
        policy = .seed
        items = []
        scores = []
        bestSimScore = nil
        transfer = nil
        lastTrace = nil
        statusText = "초기화했습니다. 정책 v1(출발점)로 돌아갑니다."
    }

    /// 스크린샷·데모용: Sim RSI → Real 전이 → Real RSI 2세대를 자동 실행합니다.
    func autoDemo() async {
        runRSI()
        await runTask?.value
        transferToReal()
        await runTask?.value
        world = .real
        generations = 2
        runRSI()
        await runTask?.value
    }

    // MARK: 이벤트 → 타임라인

    private func handle(_ event: LoopEvent) {
        switch event {
        case let .started(world, model, policy, generations):
            append(TimelineItem(generation: 0, kind: .start,
                                title: "RSI 시작 · \(world.rawValue) 환경 · \(model)",
                                detail: "출발 정책 v\(policy.version), 규칙 \(policy.rules.count)개, 최대 \(generations)세대"))

        case let .trial(trial, generation):
            append(trialItem(trial, generation: generation,
                             title: generation == 0 ? "0세대 측정 · 정책 v\(trial.policyVersion)" : "제안 v\(trial.policyVersion) 채점"))
            lastTrace = trial.rows.last?.trace
            if generation == 0 {
                scores.append(ScorePoint(generation: 0, world: trial.world, score: trial.score, accepted: true))
            }

        case let .critique(failures, generation):
            append(TimelineItem(generation: generation, kind: .critique,
                                title: "채점 결과 공유 · 실패 \(failures.count)건",
                                detail: failures.map { "\($0.ticket.id) \($0.predicted.label) ≠ \($0.ticket.expected.label)" }.joined(separator: " · "),
                                failures: failures))

        case let .proposal(old, new, trace, generation):
            let diff = Policy.diff(old: old, new: new)
            let added = diff.filter { $0.kind == .added }.count
            let removed = diff.filter { $0.kind == .removed }.count
            append(TimelineItem(generation: generation, kind: .proposal,
                                title: "정책 수정 제안 v\(old.version) → v\(new.version)",
                                detail: "\(trace.title) · +\(added)줄 −\(removed)줄",
                                trace: trace, diff: diff))
            lastTrace = trace

        case let .decision(accepted, oldScore, newScore, generation):
            scores.append(ScorePoint(generation: generation, world: world, score: newScore, accepted: accepted))
            append(TimelineItem(generation: generation, kind: accepted ? .accepted : .rejected,
                                title: accepted ? "채택" : "기각",
                                detail: String(format: "%.0f%% → %.0f%% (%@)", oldScore * 100, newScore * 100,
                                               accepted ? "점수 상승" : "상승 없음, 이전 정책 유지")))

        case let .note(text, generation):
            append(TimelineItem(generation: generation, kind: .note, title: "메모", detail: text))

        case let .finished(policy, trial):
            self.policy = policy
            if trial.world == .sim { bestSimScore = trial.score }
            append(TimelineItem(generation: 0, kind: .finished,
                                title: "RSI 종료 · 최종 정책 v\(policy.version) · \(trial.percentText)",
                                detail: "규칙 \(policy.rules.count)개. 오른쪽 '정책' 탭에서 최종 텍스트를 확인하세요."))
            statusText = "\(trial.world.rawValue) RSI 완료: 정책 v\(policy.version), \(trial.percentText)"

        case .cancelled:
            append(TimelineItem(generation: 0, kind: .note, title: "취소됨", detail: "사용자가 루프를 중단했습니다."))
            statusText = "취소됨"

        case let .failed(message):
            append(TimelineItem(generation: 0, kind: .error, title: "오류", detail: message))
            statusText = "오류: \(message)"
        }
    }

    private func trialItem(_ trial: TrialResult, generation: Int, title: String) -> TimelineItem {
        TimelineItem(generation: generation, kind: .trial, title: title,
                     detail: "\(trial.world.rawValue) · 점수 \(trial.percentText) · 완전 정답 \(trial.exactCount)/\(trial.rows.count)",
                     trial: trial)
    }

    private func append(_ item: TimelineItem) {
        items.append(item)
    }
}
