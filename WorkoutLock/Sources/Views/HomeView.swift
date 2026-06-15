import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingWorkout = false
    @State private var selectedRecord: WorkoutRecord?

    var body: some View {
        ZStack {
            WorkoutTheme.orange.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    buddyCard
                    mainCounter
                    goalCompass
                    startControls
                    autoLogPreview
                    recentRecords
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
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
        .sheet(item: $selectedRecord) { record in
            WorkoutRecordDetailView(record: record)
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("筋トレロック")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("アプリ解禁まで \(store.targetReps) 回")
                        .font(.headline)
                        .foregroundStyle(WorkoutTheme.mutedInk)
                }
                Spacer()
                Text(store.primaryTriggerLabel)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }

            HStack(spacing: 22) {
                MetricHeader(value: "\(store.targetReps)", label: "目標回数")
                MetricHeader(value: "\(store.streakDays)", label: "連続日数")
                MetricHeader(value: "\(store.todayRecordCount)", label: "今日のセット")
            }
        }
        .workoutPanelSurface()
    }

    private var goalCompass: some View {
        let progress = store.goalProgress

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目標まで")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.58))
                    Text(store.goalSummary)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WorkoutTheme.orange)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(WorkoutTheme.orange)
                        .frame(width: max(10, proxy.size.width * progress))
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                GoalPill(title: "今日の目標", value: "\(store.targetReps)回")
                GoalPill(title: "現在", value: "\(store.currentPlanWeek + 1)週目")
                GoalPill(title: "次の目標", value: store.nextPlanTargetValue)
            }
        }
        .padding(18)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
    }

    private var buddyCard: some View {
        HStack(spacing: 18) {
            WorkoutBuddyView(
                phase: store.hasCompletedToday ? .complete : .ready,
                progress: store.hasCompletedToday ? 1 : 0,
                isComplete: store.hasCompletedToday,
                size: .compact
            )
            .frame(width: 132, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                Text("もちトレ相棒")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
                Text(store.hasCompletedToday ? "今日は解除済み" : "一緒にスクワット")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(store.hasCompletedToday ? "明日また待機します" : "\(store.targetReps)回でロック解除")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(WorkoutTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
    }

    private var mainCounter: some View {
        let isDone = store.hasCompletedToday
        let detailText: String = {
            if isDone {
                let reps = store.todayReps
                let count = store.todayRecordCount
                return count > 1 ? "今日は\(reps)回 / \(count)セット完了" : "今日は\(reps)回完了"
            }

            if let calibration = store.tutorialCalibration {
                return "補正済み判定: \(calibration.qualityScore)%"
            }

            return "達成でアプリのロック解除"
        }()

        return VStack(spacing: 8) {
            if isDone {
                Text("OPEN")
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
                    .foregroundStyle(.black)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(store.targetReps)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .monospacedDigit()
                        .foregroundStyle(.black)
                    Text("回")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(WorkoutTheme.mutedInk)
                        .padding(.bottom, 14)
                }
            }

            Text(detailText)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(WorkoutTheme.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if !isDone {
                todayNextStrip
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var todayNextStrip: some View {
        HStack(spacing: 10) {
            TodayNextChip(title: "今日", value: "\(store.targetReps)回", emphasized: true)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WorkoutTheme.mutedInk)
            TodayNextChip(title: "次", value: store.nextPlanTargetValue, emphasized: false)
        }
    }

    private var startControls: some View {
        Button {
            Haptics.mediumTap()
            isShowingWorkout = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .black))
                Text("開始")
                    .font(.system(size: 28, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .foregroundStyle(.white)
            .background(.black, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筋トレ開始")
    }

    private var autoLogPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("自動ログ")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Spacer()
                Text("\(store.recordSnapshotCount)枚")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(WorkoutTheme.mutedInk)
            }

            if let latest = store.records.first {
                Button {
                    selectedRecord = latest
                } label: {
                    WorkoutSnapshotCard(record: latest, isCompact: false)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 42, weight: .black))
                    Text("トレーニング完了時に自動で1枚残ります")
                        .font(.headline.weight(.black))
                    Text("手動で写真を選ぶ必要はありません")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .foregroundStyle(.white)
                .background(.black, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .workoutPanelSurface()
    }

    private var recentRecords: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("最近の記録")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(store.totalReps)回")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }

            if store.records.isEmpty {
                Text("まだ0回。最初の1セットを完了すると、回数・時間・その瞬間の映像が残ります。")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.records.prefix(4)) { record in
                    Button {
                        selectedRecord = record
                    } label: {
                        WorkoutRecordRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .workoutPanelSurface(padding: 22)
        .background(WorkoutTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
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
                .foregroundStyle(emphasized ? .white.opacity(0.9) : WorkoutTheme.mutedInk)
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
                .foregroundStyle(WorkoutTheme.mutedInk)
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
                .foregroundStyle(.white.opacity(0.48))
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

struct WorkoutBuddyView: View {
    let phase: RepPhase
    let progress: Double
    let isComplete: Bool
    let size: WorkoutBuddySize

    private var pose: BuddyPose {
        if isComplete {
            return BuddyPose(bodyY: 4.25, bodyWidth: 7.7, bodyHeight: 5.8, footSpread: 1.15, kneeDrop: 0.25, armLift: -2.3, smileLift: -0.18)
        }

        switch phase {
        case .ready:
            return BuddyPose(bodyY: 4.55, bodyWidth: 7.25, bodyHeight: 5.95, footSpread: 0.25, kneeDrop: 0.15, armLift: 0.15, smileLift: 0)
        case .standing:
            return BuddyPose(bodyY: 4.2, bodyWidth: 7.05, bodyHeight: 6.25, footSpread: 0.05, kneeDrop: 0, armLift: 0, smileLift: 0)
        case .lowered:
            return BuddyPose(bodyY: 5.55, bodyWidth: 8.0, bodyHeight: 4.9, footSpread: 1.45, kneeDrop: 1.05, armLift: 1.05, smileLift: 0.15)
        case .complete:
            return BuddyPose(bodyY: 4.25, bodyWidth: 7.7, bodyHeight: 5.8, footSpread: 1.15, kneeDrop: 0.25, armLift: -2.3, smileLift: -0.18)
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let unit = min(canvasSize.width / 16, canvasSize.height / 13)
            let origin = CGPoint(
                x: (canvasSize.width - (16 * unit)) / 2,
                y: (canvasSize.height - (13 * unit)) / 2
            )
            let pose = pose
            let body = Color(red: 1.0, green: 0.78, blue: 0.38)
            let bodyShade = Color(red: 0.95, green: 0.52, blue: 0.23)
            let blush = Color(red: 1.0, green: 0.36, blue: 0.42)
            let shoe = Color(red: 0.14, green: 0.18, blue: 0.2)
            let ink = Color.black
            let glow = WorkoutTheme.orange.opacity(0.3 + (min(max(progress, 0), 1) * 0.45))

            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                let frame = CGRect(
                    x: origin.x + (x * unit),
                    y: origin.y + (y * unit),
                    width: width * unit,
                    height: height * unit
                )
                context.fill(Path(frame), with: .color(color))
            }

            func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, _ color: Color) {
                let frame = CGRect(
                    x: origin.x + (x * unit),
                    y: origin.y + (y * unit),
                    width: width * unit,
                    height: height * unit
                )
                context.fill(Path(roundedRect: frame, cornerRadius: radius * unit), with: .color(color))
            }

            func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                let frame = CGRect(
                    x: origin.x + (x * unit),
                    y: origin.y + (y * unit),
                    width: width * unit,
                    height: height * unit
                )
                context.fill(Path(ellipseIn: frame), with: .color(color))
            }

            func line(from start: CGPoint, to end: CGPoint, color: Color, width: CGFloat) {
                var path = Path()
                path.move(to: CGPoint(x: origin.x + (start.x * unit), y: origin.y + (start.y * unit)))
                path.addLine(to: CGPoint(x: origin.x + (end.x * unit), y: origin.y + (end.y * unit)))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * unit, lineCap: .round))
            }

            let bodyX = (16 - pose.bodyWidth) / 2
            let bodyY = pose.bodyY
            let bodyCenterX: CGFloat = 8
            let faceY = bodyY + 2.25
            let handY = bodyY + 2.55 + pose.armLift
            let footY = bodyY + pose.bodyHeight + 1.8 + pose.kneeDrop

            ellipse(2.0, 10.8, 12.0, 0.85, .black.opacity(0.28))
            rounded(3.45, 10.0, 9.1 * min(max(progress, 0.08), 1), 0.34, 0.17, glow)

            line(from: CGPoint(x: bodyX + 0.45, y: bodyY + 2.95), to: CGPoint(x: 2.35, y: handY), color: bodyShade, width: 0.64)
            line(from: CGPoint(x: bodyX + pose.bodyWidth - 0.45, y: bodyY + 2.95), to: CGPoint(x: 13.65, y: handY), color: bodyShade, width: 0.64)
            rounded(1.75, handY - 0.3, 1.2, 0.62, 0.31, shoe)
            rounded(13.05, handY - 0.3, 1.2, 0.62, 0.31, shoe)
            rect(1.55, handY - 0.08, 1.6, 0.18, .white.opacity(0.74))
            rect(12.85, handY - 0.08, 1.6, 0.18, .white.opacity(0.74))

            ellipse(bodyX, bodyY, pose.bodyWidth, pose.bodyHeight, body)
            ellipse(bodyX + 0.78, bodyY + 0.45, pose.bodyWidth - 1.55, pose.bodyHeight - 1.15, Color.white.opacity(0.14))
            rounded(bodyX + 1.08, bodyY + 0.42, pose.bodyWidth - 2.16, 0.72, 0.36, WorkoutTheme.orange)
            rounded(bodyCenterX - 1.08, bodyY + 0.2, 2.16, 0.36, 0.18, .white.opacity(0.92))

            ellipse(5.15, faceY, 0.68, 0.92, ink)
            ellipse(10.17, faceY, 0.68, 0.92, ink)
            ellipse(4.35, faceY + 1.25, 1.0, 0.55, blush.opacity(0.58))
            ellipse(10.65, faceY + 1.25, 1.0, 0.55, blush.opacity(0.58))
            line(
                from: CGPoint(x: 6.78, y: faceY + 1.63 + pose.smileLift),
                to: CGPoint(x: 9.22, y: faceY + 1.63 + pose.smileLift),
                color: ink.opacity(0.72),
                width: 0.18
            )
            ellipse(7.1, bodyY + 4.12, 1.8, 0.42, .white.opacity(0.68))

            line(from: CGPoint(x: 6.15 - pose.footSpread * 0.45, y: bodyY + pose.bodyHeight - 0.2), to: CGPoint(x: 5.2 - pose.footSpread, y: footY), color: bodyShade, width: 0.78)
            line(from: CGPoint(x: 9.85 + pose.footSpread * 0.45, y: bodyY + pose.bodyHeight - 0.2), to: CGPoint(x: 10.8 + pose.footSpread, y: footY), color: bodyShade, width: 0.78)
            rounded(4.35 - pose.footSpread, footY - 0.18, 1.9, 0.62, 0.31, shoe)
            rounded(9.75 + pose.footSpread, footY - 0.18, 1.9, 0.62, 0.31, shoe)

            if isComplete {
                ellipse(2.35, 2.2, 0.55, 0.55, WorkoutTheme.orange)
                ellipse(12.95, 2.65, 0.55, 0.55, WorkoutTheme.orange)
                ellipse(3.8, 1.05, 0.48, 0.48, .white.opacity(0.82))
                ellipse(11.35, 1.15, 0.48, 0.48, .white.opacity(0.82))
            }

            if size == .hero {
                rounded(6.35, 11.9, 3.3, 0.35, 0.18, WorkoutTheme.orange.opacity(0.75))
            }
        }
        .aspectRatio(16.0 / 13.0, contentMode: .fit)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: phase.rawValue)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isComplete)
        .accessibilityHidden(true)
    }
}

private struct BuddyPose {
    let bodyY: CGFloat
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat
    let footSpread: CGFloat
    let kneeDrop: CGFloat
    let armLift: CGFloat
    let smileLift: CGFloat
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
                    .foregroundStyle(.black)
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
                .foregroundStyle(.white.opacity(0.5))
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
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Text("\(Int(record.duration))秒")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.65))
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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ログ")
                            .font(.system(size: 42, weight: .black, design: .rounded))
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
                                .font(.title3.weight(.black))
                            Text("ワークアウトを完了すると、自動でここに残ります。")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))
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
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 24)
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
        let track = WorkoutMusicTrack.randomPool.randomElement() ?? store.selectedMusicTrack
        musicPlayer.start(
            track: track,
            volume: store.workoutMusicVolume,
            isEnabled: store.workoutMusicEnabled
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
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars) { bar in
                    VStack(spacing: 8) {
                        Text("\(bar.reps)")
                            .font(.caption2.monospacedDigit().weight(.black))
                            .foregroundStyle(.white.opacity(bar.reps > 0 ? 0.95 : 0.35))

                        GeometryReader { proxy in
                            let height = max(4, proxy.size.height * (Double(bar.reps) / Double(maxReps)))
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(bar.reps > 0 ? WorkoutTheme.orange : Color.white.opacity(0.12))
                                    .frame(height: height)
                            }
                        }
                        .frame(height: 96)

                        Text(bar.weekdaySymbol)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(bar.isToday ? WorkoutTheme.orange : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
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
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                HStack(spacing: 8) {
                    Label("\(Int(record.duration))秒", systemImage: "timer")
                    Label(record.exercise.title, systemImage: record.exercise.systemImage)
                }
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.46))
            }
            .padding(.top, 7)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.36))
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
                        .workoutPanelSurface()

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
                .foregroundStyle(WorkoutTheme.mutedInk)
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
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .foregroundStyle(.white)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
    }
}
