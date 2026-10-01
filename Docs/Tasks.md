# 태스크 문서 — 심투리얼 도장

기준일: 2026-10-01. 체크 표시는 이 저장소의 현재 상태입니다.

## M1. Core 엔진

- [x] 과제·환경 정의: `TicketCategory`, `TicketPriority`, `Prediction`, `Ticket`, `World` (Sim 12건 · Real 12건) — `Core/Ticket.swift`
- [x] 정책 모델: `Policy`, 규칙 줄 파서 `Rule.parseLine`, 기본값 파서, 줄 단위 `Policy.diff` — `Core/Policy.swift`
- [x] 모델 프로토콜 `LanguageModel` (`classify`, `revise`)과 호출 기록 `ModelTrace` — `Core/LanguageModel.swift`
- [x] 스크립트 모델: 규칙표 실행, 키워드 후보 추출(조사 제거·불용어), 세대당 최대 3개 규칙 추가, `attempt`로 후보 순환
- [x] 평가자: category 0.5 + priority 0.5, `TrialResult.failures`, 취소 지원 — `Core/Evaluator.swift`
- [x] RSI 엔진: `AsyncStream<LoopEvent>`, 0세대 측정, 조기 종료, 언덕 오르기 판정, 버전 증가 — `Core/RSIEngine.swift`
- [x] 전이 보고서 `TransferReport` (gap, verdict)
- [x] 코드 지도 `SourceAtlas` (`#filePath` 기반 실제 소스 열람)

## M2. Claude 어댑터

- [x] Messages API 직접 호출 (`URLSession`), 헤더·본문 구성 — `Core/ClaudeModel.swift`
- [x] 분류 요청: `system = policy.text`, `effort: low`, JSON 응답 파싱(첫 `{…}`)
- [x] 수정 요청: 정책 + 실패표 + 형식 제약, 코드 펜스 제거, 규칙 파싱 검증
- [x] 오류 처리: HTTP 상태, `refusal` stop reason, 파싱 실패 메시지
- [x] 서버 측 fallbacks (`fallbacks: "default"`, beta 헤더)
- [x] 요청/응답 JSON 전문을 `ModelTrace`로 기록
- [ ] 실제 키로 Sim/Real 전이 측정값을 `Docs/`에 기록 (키 보유자가 수행)

## M3. 화면

- [x] `AppModel`: 설정(환경·모델·세대·키), 상태, `LoopEvent → TimelineItem/ScorePoint` 변환, 취소·리셋
- [x] 제어판 `ControlPanelView`: 환경/모델 선택, 세대 Stepper, RSI 실행, 단독 채점, 전이, 전이 카드, 상태·취소·리셋·가이드
- [x] 타임라인 `TimelineView`: 점수 차트(Swift Charts, Sim/Real 시리즈, 기각 ×), 이벤트 목록, 펼침(채점표·실패·diff·호출 기록), 자동 스크롤
- [x] 정책/코드/모델 호출 `PolicyCodeView`: 정책 편집기 + Sim/Real 채점, 개념별 소스 열람, 마지막 호출 JSON
- [x] 학습 가이드 `LearningGuideView`: 6장, `NavigationSplitView`, 코드 위치 연동
- [x] 루트 `ContentView`: macOS/visionOS 3칸, iOS 탭, 가이드 시트, 오류 알림
- [x] 표시 이름 "심투리얼 도장", 기본 창 크기 1360×840
- [x] DEBUG 실행 인자 `-autoDemo`, `-showGuide`, `-showCode`

## M4. 검증

- [x] macOS 빌드 성공, 컴파일 경고 0건
- [x] iOS Simulator · visionOS Simulator 빌드 (xcodebuild, 서명 비활성)
- [x] 스크립트 궤적 확인: Sim 50→75→92→100 (3세대), 전이 67% (격차 33%p), Real 67→88→100 (2세대)
- [ ] Swift Testing 타깃 추가 (`Rule.parseLine`, `Evaluator`, 궤적 고정 테스트)
- [ ] Claude 모델 경로 실측 (네트워크·키 필요)
- [ ] iPhone 시뮬레이터 실제 실행·스크린샷

## M5. 문서와 배포

- [x] `README.md` (한국어 + English summary, Mermaid, 스크린샷, 코드 지도)
- [x] `Docs/TechPRD.md`, `Docs/Tasks.md`
- [x] 다이어그램 SVG 4종: 아키텍처, RSI 루프, 환경×모델 매트릭스, 세대 시퀀스
- [x] 스크린샷 3종: 메인, 코드 투명성 탭, 학습 가이드
- [x] `LICENSE` (Apache-2.0 원문), `NOTICE`, `.gitignore`
- [x] `git init -b main`
- [ ] GitHub Desktop에서 첫 커밋·푸시 (사용자 수행)
- [ ] 저장소 이름 `sim2real-dojo` 권장, 필요 시 `.xcodeproj` 이름 변경

## 교육 운영 체크리스트

1. 리셋 → Sim RSI 4세대 → 타임라인에서 G1의 네 항목 펼쳐 설명 (약 10분)
2. Real로 전이 → 전이 카드와 티켓별 채점표에서 틀린 5건의 원인 분류 (약 10분)
3. Real RSI 2세대 → 추가된 규칙 중 과적합 키워드 찾기 토론 (약 10분)
4. (키 보유 시) 모델을 Claude로 바꿔 같은 정책으로 전이 → 격차 비교 (약 15분)
5. 코드 탭에서 `Evaluator`와 `RSIEngine.run` 읽기, 안전장치 3가지 확인 (약 15분)
