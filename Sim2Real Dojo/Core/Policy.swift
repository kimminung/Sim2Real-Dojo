import Foundation

// MARK: - 정책(Policy) = 모델에게 주는 지시문
//
// RSI 루프가 "개선"하는 대상은 모델의 가중치가 아니라 이 텍스트입니다.
// 같은 텍스트가 (1) 스크립트 모델에게는 파싱 가능한 규칙표로,
// (2) 실제 Claude에게는 system 프롬프트로 전달됩니다.
// 그래서 Sim에서 배운 정책을 그대로 Real(실제 모델)로 옮길 수 있습니다.

nonisolated struct Policy: Sendable, Hashable, Codable, Identifiable {
    var version: Int
    var text: String

    var id: Int { version }

    static let sourcePath = #filePath

    /// 텍스트에서 규칙 줄만 파싱한 결과. 순서가 곧 우선순위입니다(위에서부터 먼저 일치하는 규칙 적용).
    var rules: [Rule] { Rule.parse(text) }

    /// 어떤 규칙에도 걸리지 않을 때 적용되는 기본값.
    var fallback: Prediction { Rule.parseFallback(text) ?? Prediction(category: .general, priority: .low) }

    /// 루프가 시작하는 출발점. 일부러 규칙을 두 개만 넣어 두었습니다.
    static let seed = Policy(version: 1, text: """
    당신은 고객지원 티켓 분류 담당자입니다. 티켓을 읽고 category와 priority를 정합니다.
    허용 category: 환불, 배송, 결제, 계정, 일반문의
    허용 priority: 낮음, 보통, 높음, 긴급
    규칙(위에서부터 먼저 일치하는 규칙을 적용):
    - "환불" → 환불 / 보통
    - "배송" → 배송 / 보통
    기본값 → 일반문의 / 낮음
    출력은 JSON 한 줄: {"category": "...", "priority": "..."}
    """)

    /// 규칙 목록을 새 규칙 배열로 교체한 새 정책 텍스트를 만듭니다. (스크립트 수정자가 사용)
    func replacingRules(with newRules: [Rule]) -> Policy {
        var lines = text.components(separatedBy: "\n").filter { Rule.parseLine($0) == nil }
        // "규칙(" 로 시작하는 헤더 줄 바로 뒤에 규칙을 삽입합니다.
        let headerIndex = lines.firstIndex { $0.hasPrefix("규칙(") } ?? max(lines.count - 2, 0)
        lines.insert(contentsOf: newRules.map(\.line), at: headerIndex + 1)
        return Policy(version: version, text: lines.joined(separator: "\n"))
    }

    // MARK: 정책 간 차이(diff)

    nonisolated enum DiffKind: Sendable { case same, added, removed }

    nonisolated struct DiffLine: Sendable, Hashable, Identifiable {
        let id: Int
        let kind: DiffKind
        let text: String
    }

    /// 줄 단위의 단순 diff. 교육용이므로 LCS 대신 "집합 차이"로 충분히 설명됩니다.
    static func diff(old: Policy, new: Policy) -> [DiffLine] {
        let oldLines = old.text.components(separatedBy: "\n")
        let newLines = new.text.components(separatedBy: "\n")
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)
        var result: [DiffLine] = []
        for line in newLines {
            result.append(DiffLine(id: result.count, kind: oldSet.contains(line) ? .same : .added, text: line))
        }
        for line in oldLines where !newSet.contains(line) {
            result.append(DiffLine(id: result.count, kind: .removed, text: line))
        }
        return result
    }
}

// MARK: - 규칙 한 줄

/// `- "키워드" → 분류 / 우선순위` 형식의 한 줄.
nonisolated struct Rule: Sendable, Hashable {
    var keyword: String
    var prediction: Prediction

    var line: String { "- \"\(keyword)\" → \(prediction.category.rawValue) / \(prediction.priority.rawValue)" }

    /// 정책 텍스트 전체에서 규칙 줄을 순서대로 뽑습니다.
    static func parse(_ text: String) -> [Rule] {
        text.components(separatedBy: "\n").compactMap(parseLine)
    }

    /// 한 줄을 규칙으로 해석합니다. 형식이 맞지 않으면 nil.
    static func parseLine(_ line: String) -> Rule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- \""),
              let closeQuote = trimmed.dropFirst(3).firstIndex(of: "\"") else { return nil }
        let keyword = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<closeQuote])
        let rest = trimmed[trimmed.index(after: closeQuote)...]
        guard let prediction = parsePrediction(String(rest)) else { return nil }
        return Rule(keyword: keyword, prediction: prediction)
    }

    /// `기본값 → 일반문의 / 낮음` 줄을 해석합니다.
    static func parseFallback(_ text: String) -> Prediction? {
        for line in text.components(separatedBy: "\n") where line.hasPrefix("기본값") {
            return parsePrediction(line)
        }
        return nil
    }

    /// "→ 분류 / 우선순위" 꼬리를 해석합니다.
    private static func parsePrediction(_ tail: String) -> Prediction? {
        guard let arrow = tail.range(of: "→") else { return nil }
        let parts = tail[arrow.upperBound...].split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let category = TicketCategory(rawValue: parts[0]),
              let priority = TicketPriority(rawValue: parts[1]) else { return nil }
        return Prediction(category: category, priority: priority)
    }
}
