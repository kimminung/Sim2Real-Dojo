# 기술 PRD — 심투리얼 도장 (Sim2Real Dojo)

| 항목 | 내용 |
|---|---|
| 문서 버전 | 1.0 (2026-10-01) |
| 상태 | 구현 완료, 교육 운영 준비 |
| 대상 플랫폼 | macOS 27 (주), iOS 27, visionOS 27 |
| 라이선스 | Apache-2.0 |

## 1. 배경과 문제

LLM을 업무에 적용하는 팀은 "정제된 샘플에서 잘 되던 프롬프트가 현장에서 무너지는" 경험을 반복합니다. 원인을 설명하는 개념(현실 격차, 분포 이동, 과적합)은 있지만, 직원 교육에서 이를 **직접 만져 보며** 배울 도구가 없습니다. 또한 "모델이 자기 프롬프트를 고친다"는 RSI 개념은 막연한 불안을 주며, 어떤 안전장치가 있어야 안전한지 체감하기 어렵습니다.

## 2. 목표

1. Sim-to-Real 전이와 현실 격차를 **숫자와 티켓 단위**로 체감하게 한다.
2. RSI 루프의 네 단계(실행·채점·수정·판정)와 **세 가지 안전장치**(텍스트 정책, 코드 채점, 언덕 오르기)를 화면에서 확인하게 한다.
3. **코드 투명성**: 화면의 모든 숫자·결정이 어느 파일의 어느 함수에서 나왔는지 앱 안에서 찾을 수 있게 한다.
4. API 키 없이도 전 과정이 돌아가고, 키가 있으면 실제 Claude로 같은 실험을 재현할 수 있게 한다.

### 비목표

- 실제 운영용 티켓 분류기 품질. 데이터는 교육용 24건으로 고정한다.
- 모델 가중치 학습·파인튜닝. 개선 대상은 정책 텍스트뿐이다.
- API 키의 영구 저장(Keychain 등). 교육 세션 동안 메모리에만 둔다.
- 멀티 유저, 서버, 결과 저장소.

## 3. 사용자와 시나리오

| 사용자 | 시나리오 |
|---|---|
| 신입 AI 운영자 | 학습 가이드 1~3장을 따라 Sim RSI → Real 전이를 수행하고 격차 원인을 티켓 단위로 설명 |
| 프롬프트 담당자 | 정책 탭에서 규칙을 직접 수정하고 Sim/Real에서 채점해 변화를 비교 |
| 엔지니어 | 코드 탭에서 평가자·수정자 구현을 읽고, Claude 어댑터의 요청 JSON을 확인 |
| 교육 진행자 | `-autoDemo`로 결정적 데모를 재현하고 토론 포인트(과적합 키워드 등)를 제시 |

## 4. 핵심 개념 정의

| 용어 | 정의 (코드) |
|---|---|
| 환경 World | `World.sim` / `World.real`. 각 12건의 `Ticket(id, text, expected)` |
| 정책 Policy | `Policy(version, text)`. 규칙 줄 `- "키워드" → 분류 / 우선순위`와 `기본값 → …` 줄을 포함한 지시문 |
| 배우 Actor | `LanguageModel.classify(ticket, policy)` |
| 평가자 Evaluator | `Evaluator.evaluate(policy, in:, with:)` → `TrialResult(score 0…1, rows, failures)` |
| 수정자 Reviser | `LanguageModel.revise(policy, failures, attempt)` → 새 `Policy` |
| 판정 Judge | `RSIEngine.run` 내부, `trial.score > currentTrial.score`일 때만 채택 |
| 전이 보고서 | `TransferReport(simScore, realScore)` → `gap`, `verdict` |

채점 규칙: category 일치 0.5점 + priority 일치 0.5점. 점수는 12건 평균.

## 5. 기능 요구사항

### F1. RSI 루프 실행
- 입력: 환경, 모델, 세대 수(1~8), 현재 정책.
- 0세대에서 현재 정책을 측정한 뒤 세대마다 채점 공유 → 제안 → 재채점 → 판정을 수행한다.
- 실패 사례가 0건이면 조기 종료 메모를 남기고 멈춘다.
- 기각 시 `attempt`를 증가시켜 수정자가 다른 후보를 시도하게 한다.
- 모든 단계는 `LoopEvent`로 순서대로 방출되어 타임라인에 1:1로 기록된다.
- 사용자는 언제든 취소할 수 있다(`Task.checkCancellation`).

### F2. Sim → Real 전이
- 현재 정책을 Real 환경에서 채점하고, 마지막 Sim 점수(없으면 즉석 측정)와 비교해 `TransferReport`를 만든다.
- 격차 해석: < 5%p 작음, < 25%p 보통, 그 이상 큼.

### F3. 모델 교체
- 스크립트 모델: 결정적, 네트워크 없음, 규칙표 실행과 키워드 규칙 추가(세대당 최대 3개).
- Claude 모델: Anthropic Messages API 직접 호출. 모델 ID 선택(`claude-opus-5` 기본, `claude-sonnet-5`, `claude-haiku-4-5`).
- 두 모델은 같은 프로토콜을 구현하며 UI 코드는 차이를 모른다.

### F4. 정책 편집과 단독 채점
- 정책 텍스트를 직접 수정하고 Sim 또는 Real에서 채점만 실행할 수 있다.
- "출발점으로" 버튼으로 v1 정책으로 되돌린다.

### F5. 코드 투명성
- `SourceAtlas`가 개념 8종을 파일 경로(`#filePath`)와 심벌에 매핑한다.
- 빌드한 Mac에서는 실제 소스 파일을 읽어 표시하고, 아니면 저장소 경로를 안내한다.
- 모든 모델 호출은 `ModelTrace(model, title, request, response)`로 기록되어 타임라인과 "모델 호출" 탭에 전문이 보인다.

### F6. 학습 가이드
- 6장. 각 장은 개념, 화면에서 확인, 코드 위치(`SourceAtlas` 연동), 실습으로 구성된다.

### F7. 데모 자동화 (DEBUG)
- `-autoDemo`, `-showGuide`, `-showCode` 실행 인자.

## 6. 비기능 요구사항

| 항목 | 요구 |
|---|---|
| 결정성 | 스크립트 모델 경로는 같은 입력에 항상 같은 결과(스크린샷·교육 재현성) |
| 오프라인 | API 키 없이 모든 기능 동작(Claude 모델 선택 시에만 네트워크) |
| 보안 | API 키 메모리 보관, 로그 미기록, `.gitignore`에 `.env`/`*.key` |
| 샌드박스 | macOS App Sandbox 비활성(`ENABLE_APP_SANDBOX = NO`). 소스 열람(`#filePath`)과 네트워크 호출을 위해 필요. 배포 시 샌드박스 + `network.client` 권한으로 전환 가능 |
| 동시성 | Swift 기본 MainActor 격리. Core 타입은 `nonisolated`·`Sendable`, 엔진은 `AsyncStream` + `Task` |
| 접근성 | 시스템 폰트·다이내믹 타입, 색상 외에 아이콘(✓/−/×)으로 상태 구분 |
| 플랫폼 | 하나의 타깃으로 macOS/iOS/visionOS 빌드. iOS는 TabView 레이아웃 |

## 7. 아키텍처

```
MyApp/
├── Core/                      순수 Swift, UI 의존 없음
│   ├── Ticket.swift           World, Ticket, Prediction, 데이터 24건
│   ├── Policy.swift           Policy, Rule 파서, diff
│   ├── LanguageModel.swift    protocol LanguageModel, ModelTrace, ScriptedModel
│   ├── ClaudeModel.swift      Messages API 어댑터 (URLSession)
│   ├── Evaluator.swift        TrialRow, TrialResult, Evaluator
│   ├── RSIEngine.swift        LoopEvent, RSIEngine.run, TransferReport
│   └── SourceAtlas.swift      개념 ↔ 소스 지도
├── App/
│   ├── AppModel.swift         @Observable 상태, LoopEvent → 타임라인/차트
│   ├── ControlPanelView.swift 제어판, 전이 카드
│   ├── TimelineView.swift     점수 차트(Swift Charts) + 이벤트 목록
│   ├── PolicyCodeView.swift   정책 편집 · 코드 열람 · 모델 호출
│   └── LearningGuideView.swift
├── ContentView.swift          3칸(macOS/visionOS) 또는 탭(iOS)
└── MyApp.swift
```

데이터 흐름: `AppModel.runRSI()` → `RSIEngine.run(...)`가 `AsyncStream<LoopEvent>` 반환 → `AppModel.handle(event)`가 `TimelineItem`/`ScorePoint`로 변환. 모델 호출 결과의 `ModelTrace`는 이벤트에 실려 그대로 UI에 도달한다.

## 8. Claude API 연동 명세

| 항목 | 값 |
|---|---|
| 엔드포인트 | `POST https://api.anthropic.com/v1/messages` |
| 헤더 | `x-api-key`, `anthropic-version: 2023-06-01`, `anthropic-beta: server-side-fallback-2026-07-01` |
| 분류 요청 | `model`, `max_tokens: 512`, `system: policy.text`, `messages: [user: 티켓]`, `output_config.effort: "low"`, `fallbacks: "default"` |
| 수정 요청 | `model`, `max_tokens: 8000`, `messages: [user: 정책 + 실패표 + 형식 제약]`, `fallbacks: "default"` |
| 응답 처리 | HTTP ≠ 200 → `error.message` 표출. `stop_reason == "refusal"` → 카테고리와 함께 오류. `content[].text` 결합 후 첫 JSON 객체 파싱 |
| 수정 결과 검증 | 코드 펜스 제거 후 `Rule.parse`가 1개 이상 규칙을 찾지 못하면 오류 |

thinking 파라미터는 보내지 않는다(Opus 5는 기본 adaptive). Haiku 4.5 선택 시 `output_config.effort`가 거부될 수 있으므로 오류 메시지가 그대로 화면에 표시된다(교육적으로 그대로 둔다).

## 9. 데이터 명세

Sim 12건은 맞춤법이 맞고 요청이 하나이며 키워드가 또렷하다. Real 12건은 다음을 의도적으로 포함한다.

| 격차 유형 | 예 |
|---|---|
| 동의어 | 택배 ↔ 배송 |
| 오타 | 결재 ↔ 결제 |
| 줄임말 | 비번 ↔ 비밀번호 |
| 복합 요청 | "결재가 2번 빠져나갔어요 빨리 환불해주세요" (결제가 정답, 환불 규칙에 오분류) |
| 불만이지만 요청 없음 | "박스 찌그러져서 왔는데 그냥 쓸게요" (일반문의) |
| 운 좋은 전이 | "오늘 생일인데" ← Sim에서 배운 `"오늘" → 배송 / 긴급` |

## 10. 성공 지표 (교육)

- 수강자가 전이 후 틀린 티켓 2건을 골라 격차 원인을 동의어/오타/복합요청 중 하나로 분류해 설명할 수 있다.
- 수강자가 RSI 안전장치 3가지를 코드 위치와 함께 말할 수 있다.
- 수강자가 과적합 키워드(예: "누가", "오늘")를 찾아 그 규칙이 망칠 수 있는 문장을 만들어 낼 수 있다.

## 11. 위험과 대응

| 위험 | 대응 |
|---|---|
| 스크립트 모델이 "AI처럼" 보여 오해 | 화면·가이드에 "결정적 모의 모델"임을 반복 명시, 코드 탭에서 구현 공개 |
| API 비용 | 분류 호출 effort low, 세대 수 상한 8, README에 호출 횟수 안내 |
| 안전 분류기 거절 | 서버 측 fallbacks 사용, 거절 시 카테고리 표시 |
| 베타 헤더 변경 | `ClaudeModel.swift` 상단 주석에 제거 방법 명시 |
| 다른 기기에서 소스 열람 불가 | 저장소 경로 안내 메시지로 대체 |

## 12. 향후 과제

- Swift Testing 타깃: `Rule.parseLine`, `Evaluator`, 스크립트 궤적(50→75→92→100)을 고정하는 테스트.
- Claude 모델로 측정한 전이 결과를 `Docs/`에 기록.
- 정책 버전 히스토리 되감기(이전 버전 선택 후 채점).
- 사용자 정의 티켓 추가 UI.
