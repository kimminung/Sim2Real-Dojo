import SwiftUI

// MARK: - 가운데 패널: RSI 타임라인
//
// 엔진이 보낸 이벤트를 발생 순서대로 보여 줍니다. 각 항목을 펼치면
// 티켓별 채점표, 실패 목록, 정책 diff, 모델 호출 기록을 그대로 볼 수 있습니다.

struct TimelineView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 세대별 점수 차트: Sim(파랑)과 Real(보라)의 궤적, 기각된 제안은 회색 ×.
            VStack(alignment: .leading, spacing: 4) {
                Text("점수 추이")
                    .font(.headline)
                ScoreChartView(points: model.scores)
                    .frame(height: 150)
            }
            .padding([.horizontal, .top])

            Divider()
                .padding(.vertical, 8)

            HStack {
                Text("RSI 타임라인")
                    .font(.headline)
                Spacer()
                Text("\(model.items.count)개 이벤트")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            if model.items.isEmpty {
                ContentUnavailableView("타임라인이 비어 있습니다", systemImage: "clock.arrow.circlepath",
                                       description: Text("왼쪽에서 환경과 모델을 고르고 'RSI 실행'을 누르세요.\n실행→채점→수정→판정이 세대별로 기록됩니다."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(model.items) { item in
                        TimelineRow(item: item)
                            .id(item.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: model.items.count) {
                        if let last = model.items.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }
}

struct TimelineRow: View {
    let item: AppModel.TimelineItem
    @State private var expanded = false

    private var hasDetails: Bool {
        item.trial != nil || item.trace != nil || item.diff != nil || item.failures != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.symbol)
                    .foregroundStyle(item.tint)
                    .frame(width: 18)
                Text("G\(item.generation)")
                    .font(.caption2.monospacedDigit().bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if hasDetails {
                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 26)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let trial = item.trial { TrialTable(trial: trial) }
                    if let failures = item.failures { FailureList(failures: failures) }
                    if let diff = item.diff { DiffView(lines: diff) }
                    if let trace = item.trace { TraceView(trace: trace) }
                }
                .padding(.leading, 26)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 상세 뷰들

struct TrialTable: View {
    let trial: TrialResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("티켓별 채점 (정답은 채점에만 쓰이고 모델에게는 보이지 않음)")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(trial.rows) { row in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: row.isExact ? "checkmark.circle.fill" : row.points > 0 ? "minus.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(row.isExact ? .green : row.points > 0 ? .orange : .red)
                        .font(.caption)
                    Text(row.ticket.id).font(.caption.monospaced()).frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.ticket.text).font(.caption).lineLimit(2)
                        HStack(spacing: 4) {
                            Text("예측 \(row.predicted.label)")
                                .foregroundStyle(row.isExact ? .green : .primary)
                            Text("· 정답 \(row.ticket.expected.label)")
                                .foregroundStyle(.secondary)
                            Text("· \(row.trace.title)")
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption2)
                    }
                }
            }
        }
    }
}

struct FailureList: View {
    let failures: [TrialRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("수정자에게 전달되는 실패 사례").font(.caption2).foregroundStyle(.secondary)
            ForEach(failures) { row in
                Text("\(row.ticket.id) \"\(row.ticket.text)\" → 예측 \(row.predicted.label), 정답 \(row.ticket.expected.label)")
                    .font(.caption)
            }
        }
    }
}

struct DiffView: View {
    let lines: [Policy.DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("정책 diff (+ 추가 / − 삭제)").font(.caption2).foregroundStyle(.secondary)
            ForEach(lines) { line in
                HStack(spacing: 4) {
                    Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                        .frame(width: 10)
                    Text(line.text)
                }
                .font(.caption.monospaced())
                .foregroundStyle(line.kind == .added ? .green : line.kind == .removed ? .red : .secondary)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct TraceView: View {
    let trace: ModelTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("모델 호출 · \(trace.model)").font(.caption2).foregroundStyle(.secondary)
            Text("요청").font(.caption2.bold())
            Text(trace.request).font(.caption2.monospaced()).textSelection(.enabled)
            Text("응답").font(.caption2.bold())
            Text(trace.response).font(.caption2.monospaced()).textSelection(.enabled)
        }
        .padding(6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}
