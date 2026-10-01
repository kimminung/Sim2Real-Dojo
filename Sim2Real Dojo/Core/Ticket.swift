import Foundation

// MARK: - 과제 정의: 고객지원 티켓 분류
//
// 이 앱이 다루는 "과제"는 고객지원 티켓 한 건을 읽고
// category(무슨 일인가)와 priority(얼마나 급한가)를 정하는 일입니다.
// 정책(Policy)이 이 과제를 얼마나 잘 푸는지가 RSI 루프의 점수가 됩니다.

/// 티켓 분류 라벨 공간 - 허용되는 category 값.
nonisolated enum TicketCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case refund = "환불"
    case shipping = "배송"
    case payment = "결제"
    case account = "계정"
    case general = "일반문의"

    var id: String { rawValue }
}

/// 티켓 분류 라벨 공간 - 허용되는 priority 값.
nonisolated enum TicketPriority: String, CaseIterable, Codable, Sendable, Identifiable {
    case low = "낮음"
    case normal = "보통"
    case high = "높음"
    case urgent = "긴급"

    var id: String { rawValue }
}

/// 모델이 내놓는 답(또는 정답 라벨).
nonisolated struct Prediction: Sendable, Hashable, Codable {
    var category: TicketCategory
    var priority: TicketPriority

    var label: String { "\(category.rawValue) / \(priority.rawValue)" }
}

/// 티켓 한 건. `expected`는 채점에 쓰이는 정답이며 모델에게는 절대 보여주지 않습니다.
nonisolated struct Ticket: Sendable, Hashable, Identifiable {
    let id: String
    let text: String
    let expected: Prediction
}

// MARK: - 환경(World): Sim과 Real

/// 정책이 실행되는 환경입니다.
///
/// - `sim`  : 깨끗하고 정형화된 티켓. 값싸고 결정적이라 RSI 루프를 빠르게 돌릴 수 있습니다.
/// - `real` : 오타·은어·복합 요청이 섞인 현장 티켓. Sim에서 배운 정책이 여기서 얼마나 버티는지가
///            "현실 격차(reality gap)"입니다.
nonisolated enum World: String, CaseIterable, Sendable, Identifiable, Codable {
    case sim = "Sim"
    case real = "Real"

    var id: String { rawValue }

    /// 투명성용: 이 파일의 절대 경로. 앱의 "코드" 탭이 실제 소스를 읽어 보여줄 때 사용합니다.
    static let sourcePath = #filePath

    var title: String {
        switch self {
        case .sim: "Sim 환경 · 정제된 연습 티켓"
        case .real: "Real 환경 · 현장 티켓(오타·은어 포함)"
        }
    }

    var summary: String {
        switch self {
        case .sim:
            "맞춤법이 맞고 한 가지 요청만 담긴 티켓 12건. 정책을 빠르게 반복 개선하기 위한 훈련장입니다."
        case .real:
            "오타, 줄임말, 감정 표현, 두 가지 요청이 섞인 티켓 12건. Sim에서 배운 규칙이 통하지 않는 지점을 드러냅니다."
        }
    }

    var tickets: [Ticket] {
        switch self {
        case .sim: Self.simTickets
        case .real: Self.realTickets
        }
    }

    // 정제된 연습 데이터. 의도적으로 키워드가 또렷합니다.
    static let simTickets: [Ticket] = [
        Ticket(id: "S01", text: "주문한 신발 사이즈가 안 맞아서 환불 요청합니다.",
               expected: Prediction(category: .refund, priority: .normal)),
        Ticket(id: "S02", text: "배송이 아직 안 왔어요. 송장번호 확인 부탁드립니다.",
               expected: Prediction(category: .shipping, priority: .normal)),
        Ticket(id: "S03", text: "결제가 두 번 됐어요. 중복 결제 확인해 주세요.",
               expected: Prediction(category: .payment, priority: .high)),
        Ticket(id: "S04", text: "비밀번호를 잊어버려서 로그인이 안 됩니다.",
               expected: Prediction(category: .account, priority: .normal)),
        Ticket(id: "S05", text: "영업시간이 어떻게 되나요?",
               expected: Prediction(category: .general, priority: .low)),
        Ticket(id: "S06", text: "파손된 상태로 도착했습니다. 환불 처리 부탁드립니다.",
               expected: Prediction(category: .refund, priority: .high)),
        Ticket(id: "S07", text: "오늘 결혼식 선물인데 배송이 아직 안 왔어요. 당장 확인 부탁드립니다.",
               expected: Prediction(category: .shipping, priority: .urgent)),
        Ticket(id: "S08", text: "카드 결제 승인이 계속 실패합니다.",
               expected: Prediction(category: .payment, priority: .normal)),
        Ticket(id: "S09", text: "계정이 해킹된 것 같아요. 모르는 주문이 있습니다.",
               expected: Prediction(category: .account, priority: .urgent)),
        Ticket(id: "S10", text: "회원 등급 혜택이 궁금합니다.",
               expected: Prediction(category: .general, priority: .low)),
        Ticket(id: "S11", text: "배송지 주소를 변경하고 싶어요.",
               expected: Prediction(category: .shipping, priority: .low)),
        Ticket(id: "S12", text: "쿠폰이 적용되지 않아요.",
               expected: Prediction(category: .payment, priority: .low)),
    ]

    // 현장 데이터. 같은 의미를 다른 단어로 말하고(택배↔배송), 오타(결재↔결제)가 섞여 있습니다.
    static let realTickets: [Ticket] = [
        Ticket(id: "R01", text: "환불좀요 ㅠㅠ 사이즈 안맞음",
               expected: Prediction(category: .refund, priority: .normal)),
        Ticket(id: "R02", text: "택배 언제와요?? 일주일째 안옴",
               expected: Prediction(category: .shipping, priority: .normal)),
        Ticket(id: "R03", text: "결재가 2번 빠져나갔어요 빨리 환불해주세요",
               expected: Prediction(category: .payment, priority: .high)),
        Ticket(id: "R04", text: "로그인 안됨. 비번 초기화 해주세요",
               expected: Prediction(category: .account, priority: .normal)),
        Ticket(id: "R05", text: "매장 위치 알려주세요",
               expected: Prediction(category: .general, priority: .low)),
        Ticket(id: "R06", text: "박스 찌그러져서 왔는데 그냥 쓸게요. 다음엔 포장 좀 신경써주세요",
               expected: Prediction(category: .general, priority: .low)),
        Ticket(id: "R07", text: "오늘 생일인데 선물 아직도 안와요 진짜 급해요",
               expected: Prediction(category: .shipping, priority: .urgent)),
        Ticket(id: "R08", text: "카드 승인 거절 계속 뜸",
               expected: Prediction(category: .payment, priority: .normal)),
        Ticket(id: "R09", text: "내 계정으로 누가 로그인했다는 알림 왔어요 무서워요",
               expected: Prediction(category: .account, priority: .urgent)),
        Ticket(id: "R10", text: "포인트 적립은 어떻게 하나요",
               expected: Prediction(category: .general, priority: .low)),
        Ticket(id: "R11", text: "주소 잘못 적었어요 바꿔주세요 아직 발송 전이면",
               expected: Prediction(category: .shipping, priority: .low)),
        Ticket(id: "R12", text: "할인코드 입력했는데 안먹혀요",
               expected: Prediction(category: .payment, priority: .low)),
    ]
}
