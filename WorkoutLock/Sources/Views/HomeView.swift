import SwiftUI
import UIKit

private enum HomeSheet: Identifiable {
    case record(WorkoutRecord)
    case weightCheckIn

    var id: String {
        switch self {
        case .record(let record):
            return "record-\(record.id.uuidString)"
        case .weightCheckIn:
            return "weight-check-in"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingWorkout = false
    @State private var activeSheet: HomeSheet?

    var body: some View {
        ZStack {
            WorkoutTheme.orange.ignoresSafeArea()
            GlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topBar
                    heroCard
                    startButton
                    statsRow
                    dietCard
                    recordsCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isShowingWorkout) {
            WorkoutSessionView(
                exercise: store.selectedExercise,
                targetReps: store.targetReps
            )
            .environmentObject(store)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .record(let record):
                WorkoutRecordDetailView(record: record)
            case .weightCheckIn:
                WeightCheckInSheet()
                    .environmentObject(store)
            }
        }
        .onAppear {
            consumeWorkoutLaunchRequest()
            showWeightCheckInIfDue()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutStartRequested)) { _ in
            consumeWorkoutLaunchRequest()
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("筋トレロック")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(WorkoutInk.primary)
            Spacer()
            Label(store.primaryTriggerLabel, systemImage: "clock")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(WorkoutInk.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlass(cornerRadius: 16)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatChip(value: "\(store.streakDays)", unit: "日連続")
            StatChip(value: "\(store.todayRecordCount)", unit: "今日セット")
            StatChip(value: "\(Int((store.goalProgress * 100).rounded()))%", unit: "目標達成")
        }
    }

    private var heroCard: some View {
        let isDone = store.hasCompletedToday
        return VStack(spacing: 12) {
            WorkoutBuddyView(
                phase: isDone ? .complete : .ready,
                progress: isDone ? 1 : store.goalProgress,
                isComplete: isDone,
                size: .hero
            )
            .frame(height: 124)

            if isDone {
                Text("OPEN")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(WorkoutInk.primary)
                Text(store.todayRecordCount > 1 ? "今日 \(store.todayReps)回 / \(store.todayRecordCount)セット" : "今日 \(store.todayReps)回 完了")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.62))
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(store.targetReps)")
                        .font(.system(size: 76, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WorkoutInk.primary)
                    Text("回")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.62))
                        .padding(.bottom, 12)
                }
                todayNextStrip
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .liquidGlass(cornerRadius: 30)
    }

    private var todayNextStrip: some View {
        HStack(spacing: 10) {
            TodayNextChip(title: "今日", value: "\(store.targetReps)回", emphasized: true)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color.black.opacity(0.62))
            TodayNextChip(title: "次", value: store.nextPlanTargetValue, emphasized: false)
        }
    }

    private var startButton: some View {
        Button {
            Haptics.mediumTap()
            isShowingWorkout = true
        } label: {
            Label(store.hasCompletedToday ? "もう1セット" : "開始", systemImage: "play.fill")
        }
        .buttonStyle(.glassPrimary)
        .accessibilityLabel("筋トレ開始")
    }

    private func consumeWorkoutLaunchRequest() {
        guard WorkoutLaunchRequest.consumePending() else { return }
        activeSheet = nil
        isShowingWorkout = true
    }

    private func showWeightCheckInIfDue() {
        guard activeSheet == nil, !isShowingWorkout, store.isWeeklyWeightCheckInDue else { return }
        activeSheet = .weightCheckIn
    }

    @ViewBuilder
    private var dietCard: some View {
        if let result = store.currentPlanResult {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("今日の食事")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(WorkoutInk.primary)
                    Spacer()
                    Text(result.dietLevel.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(WorkoutInk.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .liquidGlass(cornerRadius: 14)
                }

                ForEach(Array(result.dietLevel.foodRules.prefix(3)), id: \.self) { rule in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WorkoutTheme.deepOrange)
                        Text(rule)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WorkoutInk.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .liquidGlass(cornerRadius: 24)
        }
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("記録")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(WorkoutInk.primary)
                Spacer()
                Text("\(store.totalReps)回")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.black.opacity(0.62))
            }

            if store.records.isEmpty {
                Text("最初の1セットで記録が残ります")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(store.records.prefix(3)) { record in
                    Button {
                        activeSheet = .record(record)
                    } label: {
                        WorkoutRecordRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 24)
    }
}

private struct StatChip: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WorkoutInk.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .liquidGlass(cornerRadius: 18)
    }
}

private struct TodayNextChip: View {
    let title: String
    let value: String
    let emphasized: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(emphasized ? .white.opacity(0.9) : Color.black.opacity(0.62))
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(emphasized ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 84)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            emphasized ? AnyShapeStyle(.black) : AnyShapeStyle(.white.opacity(0.5)),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

private struct WeightCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var weightKg = 65.0
    @State private var didLoadInitialWeight = false
    @State private var didResolve = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("体重チェック")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("入力すると、今日以降の回数ペースを自動で調整します。")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("現在")
                            .font(.headline.weight(.black))
                        Spacer()
                        Text("\(weightKg, specifier: "%.1f")kg")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }

                    Stepper(value: $weightKg, in: 35...160, step: 0.5) {
                        Text("0.5kgずつ調整")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.62))
                    }
                    .tint(.black)

                    HStack {
                        Text("いまの目標")
                        Spacer()
                        Text("\(store.targetReps)回")
                            .fontWeight(.black)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.bold))
                }
                .padding(18)
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Spacer(minLength: 0)

                Button {
                    didResolve = true
                    store.completeWeeklyWeightCheckIn(weightKg: weightKg)
                    Haptics.success()
                    dismiss()
                } label: {
                    Label("入力して調整", systemImage: "checkmark")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)

                Button {
                    didResolve = true
                    store.deferWeeklyWeightCheckIn()
                    Haptics.lightTap()
                    dismiss()
                } label: {
                    Text("あとで")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.black)
            }
            .padding(24)
            .background(WorkoutTheme.orange.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                guard !didLoadInitialWeight else { return }
                weightKg = store.currentWeightKg
                didLoadInitialWeight = true
            }
            .onDisappear {
                guard !didResolve else { return }
                store.deferWeeklyWeightCheckIn()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MetricHeader: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GoalPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.74))
            Text(value)
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum WorkoutBuddySize {
    case compact
    case hero
}

/// もちトレ相棒のドット絵（ピクセルアート）。16x16グリッドのスプライト。
/// 表情は状態で出し分け: 通常 / 追い込み(lowered) / 達成(complete)。
struct WorkoutBuddyView: View {
    let phase: RepPhase
    let progress: Double
    let isComplete: Bool
    let size: WorkoutBuddySize

    private enum Mood {
        case normal, effort, happy
    }

    private var mood: Mood {
        if isComplete { return .happy }
        if phase == .lowered { return .effort }
        return .normal
    }

    var body: some View {
        Canvas { context, canvasSize in
            let unit = min(canvasSize.width, canvasSize.height) / 16
            let origin = CGPoint(
                x: (canvasSize.width - (16 * unit)) / 2,
                y: (canvasSize.height - (16 * unit)) / 2
            )

            let body = Color(red: 0.93, green: 0.525, blue: 0.22)
            let shade = Color(red: 0.85, green: 0.41, blue: 0.16)
            let ink = Color(red: 0.227, green: 0.141, blue: 0.063)
            let sweat = Color(red: 0.42, green: 0.72, blue: 0.91)

            func px(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
                let frame = CGRect(
                    x: origin.x + (CGFloat(x) * unit),
                    y: origin.y + (CGFloat(y) * unit),
                    width: CGFloat(w) * unit,
                    height: CGFloat(h) * unit
                )
                context.fill(Path(frame), with: .color(color))
            }

            px(4, 15, 8, 1, .black.opacity(0.16))

            px(7, 0, 2, 3, shade)
            px(5, 1, 1, 1, shade)
            px(10, 1, 1, 1, shade)

            px(6, 4, 4, 1, body)
            px(5, 5, 6, 1, body)
            px(4, 6, 8, 1, body)
            px(3, 7, 10, 2, body)
            px(2, 9, 12, 2, body)
            px(3, 11, 10, 1, body)
            px(4, 12, 8, 1, body)
            px(6, 13, 4, 1, body)
            px(12, 9, 1, 2, shade)
            px(4, 12, 8, 1, shade.opacity(0.55))

            switch mood {
            case .normal:
                px(5, 8, 2, 2, ink)
                px(9, 8, 2, 2, ink)
            case .effort:
                px(5, 8, 2, 2, ink)
                px(9, 8, 2, 2, ink)
                px(7, 11, 2, 1, ink)
                px(13, 5, 1, 2, sweat)
            case .happy:
                px(5, 8, 2, 1, ink)
                px(9, 8, 2, 1, ink)
                px(6, 11, 1, 1, ink)
                px(7, 12, 2, 1, ink)
                px(9, 11, 1, 1, ink)
                px(1, 3, 1, 1, .white)
                px(14, 4, 1, 1, .white)
                px(2, 6, 1, 1, .white.opacity(0.85))
            }

            if size == .hero {
                let glowWidth = max(2, Int((CGFloat(10) * min(max(progress, 0.08), 1)).rounded()))
                px(3, 15, glowWidth, 1, WorkoutTheme.orange.opacity(0.7))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct WorkoutSnapshotCard: View {
    let record: WorkoutRecord
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                SnapshotImage(data: record.snapshotData)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text("\(record.actualReps)/\(record.targetReps)")
                    .font(.system(size: isCompact ? 24 : 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .frame(width: isCompact ? 74 : 168, height: isCompact ? 132 : 298)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))

                Text("\(record.actualReps)回完了")
                    .font(.system(size: isCompact ? 18 : 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(Int(record.duration))秒")
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(WorkoutInk.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WorkoutTheme.orange, in: Capsule())

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SnapshotImage: View {
    let data: Data?

    var body: some View {
        if
            let data,
            let image = UIImage(data: data)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                WorkoutTheme.panel
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title)
                    Text("記録画像なし")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

private struct WorkoutRecordRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            SnapshotImage(data: record.snapshotData)
                .frame(width: 62, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(record.actualReps)回")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(WorkoutInk.primary)
                Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.62))
            }

            Spacer()

            Text("\(Int(record.duration))秒")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.black.opacity(0.62))
        }
    }
}

struct ProgressBoardView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var musicPlayer = WorkoutMusicPlayer()
    @State private var selectedRecord: WorkoutRecord?

    var body: some View {
        ZStack {
            WorkoutTheme.orange.ignoresSafeArea()
            GlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ログ")
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .foregroundStyle(WorkoutInk.primary)
                        Spacer()
                        if !store.records.isEmpty {
                            musicIndicator
                        }
                    }
                    .padding(.top, 18)

                    HStack(spacing: 12) {
                        LogMetric(value: "\(store.bestReps)", label: "自己ベスト")
                        LogMetric(value: "\(store.thisWeekReps)", label: "今週の回数")
                        LogMetric(value: "\(store.streakDays)", label: "連続日数")
                    }

                    if !store.records.isEmpty {
                        WeeklyBarChart(bars: store.weeklyRepBars)
                    }

                    HStack(spacing: 12) {
                        LogMetric(value: "\(store.records.count)", label: "セット")
                        LogMetric(value: "\(store.totalReps)", label: "総回数")
                        LogMetric(value: "\(Int(store.totalWorkoutDuration))", label: "総秒数")
                    }

                    if store.records.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 46, weight: .black))
                            Text("まだログがありません")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("完了すると自動で残ります")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.black.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .foregroundStyle(WorkoutInk.primary)
                        .liquidGlass(cornerRadius: 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.records.enumerated()), id: \.element.id) { index, record in
                                Button {
                                    selectedRecord = record
                                } label: {
                                    WorkoutTimelineRow(
                                        record: record,
                                        isFirst: index == 0,
                                        isLast: index == store.records.count - 1
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 24)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedRecord) { record in
            WorkoutRecordDetailView(record: record)
        }
        .onAppear { startLogMusic() }
        .onDisappear { musicPlayer.stop() }
        .onChange(of: store.workoutMusicEnabled) { _, _ in startLogMusic() }
        .onChange(of: store.workoutMusicVolume) { _, volume in
            musicPlayer.updateVolume(volume)
        }
    }

    private var musicIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: store.workoutMusicEnabled ? "music.note" : "music.note.list")
                .font(.system(size: 13, weight: .black))
            Text(store.workoutMusicEnabled ? musicPlayer.statusText : "オフ")
                .font(.caption.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func startLogMusic() {
        guard !store.records.isEmpty else {
            musicPlayer.stop()
            return
        }
        let availableTracks = WorkoutMusicTrack.availableRandomPool()
        let bundledTracks = WorkoutMusicTrack.allCases.filter { $0.bundledURL() != nil }
        let track = availableTracks.randomElement() ?? store.selectedMusicTrack
        musicPlayer.start(
            track: track,
            volume: store.workoutMusicVolume,
            isEnabled: store.workoutMusicEnabled,
            fallbackTracks: (availableTracks + bundledTracks).filter { $0 != track }
        )
    }
}

private struct WeeklyBarChart: View {
    let bars: [DailyRepBar]

    private var maxReps: Int {
        max(1, bars.map(\.reps).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("直近7日")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(WorkoutInk.primary)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars) { bar in
                    VStack(spacing: 8) {
                        Text("\(bar.reps)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(bar.reps > 0 ? WorkoutInk.primary : Color.black.opacity(0.62))

                        GeometryReader { proxy in
                            let height = max(4, proxy.size.height * (Double(bar.reps) / Double(maxReps)))
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(bar.reps > 0 ? WorkoutTheme.deepOrange : Color.black.opacity(0.1))
                                    .frame(height: height)
                            }
                        }
                        .frame(height: 96)

                        Text(bar.weekdaySymbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(bar.isToday ? WorkoutTheme.deepOrange : Color.black.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 24)
    }
}

private struct WorkoutTimelineRow: View {
    let record: WorkoutRecord
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? .clear : WorkoutTheme.orange.opacity(0.45))
                    .frame(width: 3, height: 18)
                Circle()
                    .fill(WorkoutTheme.orange)
                    .frame(width: 11, height: 11)
                Rectangle()
                    .fill(isLast ? .clear : WorkoutTheme.orange.opacity(0.45))
                    .frame(width: 3)
            }
            .frame(width: 16, height: 108)

            SnapshotImage(data: record.snapshotData)
                .frame(width: 54, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                Text("\(record.actualReps) / \(record.targetReps) 回")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(WorkoutInk.primary)
                Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.62))
                HStack(spacing: 8) {
                    Label("\(Int(record.duration))秒", systemImage: "timer")
                    Label(record.exercise.title, systemImage: record.exercise.systemImage)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.62))
            }
            .padding(.top, 7)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.black.opacity(0.62))
                .padding(.top, 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct WorkoutRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let record: WorkoutRecord

    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                WorkoutTheme.orange.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        SnapshotImage(data: record.snapshotData)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .background(.black, in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 14) {
                            Text("\(record.actualReps) / \(record.targetReps) 回")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .monospacedDigit()
                            RecordDetailLine(title: "日時", value: record.completedAt.formatted(date: .abbreviated, time: .shortened))
                            RecordDetailLine(title: "時間", value: "\(Int(record.duration))秒")
                            RecordDetailLine(title: "種目", value: record.exercise.title)
                        }
                        .padding(20)
                        .liquidGlass(cornerRadius: 24)

                        shareButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: prepareShareImage)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            ShareLink(
                item: shareURL,
                message: Text("筋トレロックで\(record.actualReps)回達成！ #筋トレロック"),
                preview: SharePreview("筋トレロック \(record.actualReps)回達成", image: shareURL)
            ) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22, weight: .black))
                    Text("結果をシェア")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .foregroundStyle(.white)
                .background(.black, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("シェア画像を準備中…")
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .foregroundStyle(.white.opacity(0.7))
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func prepareShareImage() {
        guard shareURL == nil else { return }
        shareURL = WorkoutShareImageRenderer.makeImageURL(
            record: record,
            streakDays: store.streakDays,
            totalReps: store.totalReps
        )
    }
}

private struct RecordDetailLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.black.opacity(0.62))
            Spacer()
            Text(value)
                .fontWeight(.black)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline.weight(.bold))
    }
}

private struct LogMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(WorkoutInk.primary)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .liquidGlass(cornerRadius: 18)
    }
}
