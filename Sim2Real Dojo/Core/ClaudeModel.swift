import Foundation

// MARK: - 실제 Claude 모델 어댑터 (Real 모델)
//
// Anthropic Messages API(`POST /v1/messages`)를 URLSession으로 직접 호출합니다.
// Swift용 공식 SDK가 없으므로 HTTP 요청 본문을 그대로 만듭니다 - 교육용으로는 오히려 투명합니다.
// 요청/응답 JSON은 ModelTrace로 전부 기록되어 화면의 "모델 호출" 탭에 표시됩니다.
//
// 참고 사항
// - 기본 모델은 claude-opus-5. 분류처럼 짧은 과제는 output_config.effort = "low"로 비용을 줄입니다.
// - thinking 파라미터는 생략합니다(Opus 5는 기본이 adaptive thinking).
// - 안전 분류기가 요청을 거절(stop_reason: "refusal")할 수 있으므로 서버 측 fallbacks를 켭니다.
// - API 키는 메모리에만 보관합니다. 디스크나 로그에 남기지 않습니다.

nonisolated enum ClaudeModelID: String, CaseIterable, Sendable, Identifiable {
    case opus5 = "claude-opus-5"
    case sonnet5 = "claude-sonnet-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }
}

nonisolated struct ClaudeAPIError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated final class ClaudeModel: LanguageModel, Sendable {
    static let sourcePath = #filePath
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String
    let modelID: ClaudeModelID
    let session: URLSession

    init(apiKey: String, modelID: ClaudeModelID = .opus5, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    var displayName: String { "Claude · \(modelID.rawValue)" }

    // MARK: 배우(Actor)

    func classify(_ ticket: Ticket, policy: Policy) async throws -> (Prediction, ModelTrace) {
        let body: [String: Any] = [
            "model": modelID.rawValue,
            "max_tokens": 512,
            "system": policy.text,
            "messages": [[
                "role": "user",
                "content": "티켓:\n\(ticket.text)\n\n정책에 따라 분류하고 JSON 한 줄만 출력하세요.",
            ]],
            "output_config": ["effort": "low"],
            "fallbacks": "default",
        ]
        let (text, requestJSON, responseJSON) = try await send(body)
        let prediction = try Self.parsePrediction(from: text)
        let trace = ModelTrace(model: displayName,
                               title: "분류 호출 → \(prediction.label)",
                               request: requestJSON,
                               response: responseJSON)
        return (prediction, trace)
    }

    // MARK: 수정자(Reviser)

    func revise(_ policy: Policy, failures: [TrialRow], attempt: Int) async throws -> (Policy, ModelTrace) {
        let failureTable = failures.map {
            "- [\($0.ticket.id)] \"\($0.ticket.text)\" → 모델 답: \($0.predicted.label) / 정답: \($0.ticket.expected.label)"
        }.joined(separator: "\n")

        let instructions = """
        아래는 티켓 분류 정책(system 프롬프트)과, 이 정책으로 분류했을 때 틀린 사례입니다.
        정책을 개선해 틀린 사례를 맞히되 다른 사례를 망가뜨리지 않도록 하세요.
        \(attempt > 0 ? "직전 제안 \(attempt)회가 점수를 올리지 못해 기각되었습니다. 다른 접근을 시도하세요.\n" : "")
        형식 제약:
        - 규칙 줄은 반드시 `- "키워드" → 분류 / 우선순위` 형식을 지키세요. (예: - "택배" → 배송 / 보통)
        - `기본값 → 분류 / 우선순위` 줄과 마지막 출력 형식 줄은 유지하세요.
        - 개선된 정책 전문만 출력하세요. 설명이나 코드 펜스는 쓰지 마세요.

        [현재 정책]
        \(policy.text)

        [틀린 사례]
        \(failureTable)
        """

        let body: [String: Any] = [
            "model": modelID.rawValue,
            "max_tokens": 8000,
            "messages": [["role": "user", "content": instructions]],
            "fallbacks": "default",
        ]
        let (text, requestJSON, responseJSON) = try await send(body)
        let cleaned = Self.stripCodeFence(text)
        guard !Rule.parse(cleaned).isEmpty else {
            throw ClaudeAPIError(message: "모델이 돌려준 정책에서 규칙 줄을 찾지 못했습니다.")
        }
        let proposal = Policy(version: policy.version, text: cleaned)
        let trace = ModelTrace(model: displayName,
                               title: "정책 수정 호출 (시도 \(attempt + 1))",
                               request: requestJSON,
                               response: responseJSON)
        return (proposal, trace)
    }

    // MARK: HTTP

    /// 요청을 보내고 (텍스트 응답, 요청 JSON, 응답 JSON)을 돌려줍니다.
    private func send(_ body: [String: Any]) async throws -> (String, String, String) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.timeoutInterval = 600

        let requestJSON = Self.pretty(try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .prettyPrinted]))
        let (data, response) = try await session.data(for: request)
        let responseJSON = Self.pretty(data)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError(message: "HTTP 응답이 아닙니다.")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard http.statusCode == 200 else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String ?? responseJSON
            throw ClaudeAPIError(message: "HTTP \(http.statusCode): \(detail)")
        }
        if json["stop_reason"] as? String == "refusal" {
            let category = (json["stop_details"] as? [String: Any])?["category"] as? String ?? "unknown"
            throw ClaudeAPIError(message: "모델이 요청을 거절했습니다 (category: \(category)).")
        }
        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return (text, requestJSON, responseJSON)
    }

    // MARK: 파싱 도우미

    /// 응답 텍스트 안의 첫 JSON 객체에서 category/priority를 읽습니다.
    static func parsePrediction(from text: String) throws -> Prediction {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let data = String(text[open...close]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let category = TicketCategory(rawValue: (object["category"] as? String ?? "").trimmingCharacters(in: .whitespaces)),
              let priority = TicketPriority(rawValue: (object["priority"] as? String ?? "").trimmingCharacters(in: .whitespaces))
        else {
            throw ClaudeAPIError(message: "분류 결과 JSON을 해석하지 못했습니다: \(text.prefix(200))")
        }
        return Prediction(category: category, priority: priority)
    }

    static func stripCodeFence(_ text: String) -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.hasPrefix("```") == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    static func pretty(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
    }
}
