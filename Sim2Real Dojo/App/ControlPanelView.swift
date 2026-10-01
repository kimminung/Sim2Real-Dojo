import SwiftUI
import Charts

// MARK: - 왼쪽 패널: 제어판 + 점수 차트

struct ControlPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("심투리얼 도장")
                        .font(.title2.bold())
                    Text("Sim에서 정책을 재귀적으로 개선하고, Real로 옮겨 현실 격차를 재는 연습장")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("1. 환경 (World)") {
                Picker("환경", selection: $model.world) {
                    ForEach(World.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.world.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("2. 모델 (Model)") {
                Picker("모델", selection: $model.backend) {
                    ForEach(AppModel.Backend.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if model.backend == .claude {
                    Picker("모델 ID", selection: $model.claudeModelID) {
                        ForEach(ClaudeModelID.allCases) { Text($0.rawValue).tag($0) }
                    }
                    SecureField("ANTHROPIC_API_KEY", text: $model.apiKey)
                        .textContentType(.password)
                    Text("키는 메모리에만 보관되며 저장되지 않습니다. 호출마다 요청/응답 JSON이 '모델 호출' 탭에 기록됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("LLM 없이 규칙표를 그대로 실행하는 결정적 모의 모델. 네트워크 없이 전 과정을 체험할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("3. RSI 루프") {
                Stepper("세대 수: \(model.generations)", value: $model.generations, in: 1...8)
                Button {
                    model.runRSI()
                } label: {
                    Label("RSI 실행 (\(model.world.rawValue) 환경)", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)

                Button {
                    model.evaluateOnly(in: model.world)
                } label: {
                    Label("현재 정책 v\(model.policy.version) 채점만", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isRunning)
            }

            Section("4. Sim → Real 전이") {
                Button {
                    model.transferToReal()
                } label: {
                    Label("정책 v\(model.policy.version)을 Real로 전이", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(model.isRunning)

                if let report = model.transfer {
                    TransferCard(report: report)
                }
            }

            Section {
                HStack {
                    if model.isRunning { ProgressView().controlSize(.small) }
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("취소", role: .cancel) { model.cancel() }
                        .disabled(!model.isRunning)
                    Button("리셋", role: .destructive) { model.reset() }
                    Spacer()
                    Button {
                        model.showGuide = true
                    } label: {
                        Label("학습 가이드", systemImage: "book")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 전이 보고서 카드

struct TransferCard: View {
    let report: TransferReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                scoreTile("Sim", report.simScore, .blue)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                scoreTile("Real", report.realScore, .purple)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("현실 격차").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%+.0f%%p", report.gap * 100))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(report.gap > 0.25 ? .red : report.gap > 0.05 ? .orange : .green)
                }
            }
            Text(report.verdict)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func scoreTile(_ name: String, _ score: Double, _ color: Color) -> some View {
        VStack {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.0f%%", score * 100))
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
        }
    }
}

// MARK: - 세대별 점수 차트

struct ScoreChartView: View {
    let points: [AppModel.ScorePoint]

    var body: some View {
        if points.isEmpty {
            ContentUnavailableView("아직 점수가 없습니다", systemImage: "chart.xyaxis.line",
                                   description: Text("RSI를 실행하면 세대별 점수가 그려집니다."))
        } else {
            Chart {
                ForEach(points.filter(\.accepted)) { point in
                    LineMark(x: .value("세대", point.generation), y: .value("점수", point.score * 100))
                        .foregroundStyle(by: .value("환경", point.world.rawValue))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("세대", point.generation), y: .value("점수", point.score * 100))
                        .foregroundStyle(by: .value("환경", point.world.rawValue))
                }
                ForEach(points.filter { !$0.accepted }) { point in
                    PointMark(x: .value("세대", point.generation), y: .value("점수", point.score * 100))
                        .foregroundStyle(.gray)
                        .symbol(.cross)
                        .annotation(position: .trailing) {
                            Text("기각").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("점수 (%)")
            .chartXAxisLabel("세대")
            .chartForegroundStyleScale(["Sim": Color.blue, "Real": Color.purple])
        }
    }
}
