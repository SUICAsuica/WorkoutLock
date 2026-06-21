import SwiftUI

struct WorkoutSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var camera = WorkoutCameraModel()
    @StateObject private var shielding = ScreenShieldingService()
    @StateObject private var datasetStore = DatasetStore()
    @StateObject private var musicPlayer = WorkoutMusicPlayer()
    @State private var startedAt = Date()
    @State private var isComplete = false
    @State private var didSave = false
    @State private var poseSamples: [DatasetPoseSample] = []
    @State private var lastPoseSampleAt = Date.distantPast
    @State private var visibleSampleCount = 0
    @State private var analyzedSampleCount = 0
    @State private var trackedJointTotal = 0
    @State private var kneeAngleTotal = 0.0
    @State private var kneeAngleSampleCount = 0
    @State private var lowestKneeAngle: Double?
    @State private var standingKneeAngle: Double?
    @State private var activeMusicTrack: WorkoutMusicTrack = .sunoSlot01
    @State private var hasStartedMusic = false
    @State private var shareURL: URL?
    @State private var shareStatusText: String?
    @State private var completedSets = 0
    @State private var setStartRepOffset = 0
    @State private var workoutSessionLockTask: Task<Void, Never>?
    @State private var didClearWorkoutSessionLock = false

    let exercise: ExerciseKind
    let targetReps: Int
    let tutorialPlan: TrainingPlan?
    let onFinished: (() -> Void)?

    init(
        exercise: ExerciseKind,
        targetReps: Int,
        tutorialPlan: TrainingPlan? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        self.targetReps = targetReps
        self.tutorialPlan = tutorialPlan
        self.onFinished = onFinished
    }

    private var isTutorial: Bool {
        tutorialPlan != nil || onFinished != nil
    }

    private var setsTarget: Int { isTutorial ? 1 : max(1, store.setsTarget) }
    private var repsPerSet: Int { isTutorial ? max(1, targetReps) : max(1, store.repsPerSet) }
    private var withinSetReps: Int { min(repsPerSet, max(0, camera.frame.repCount - setStartRepOffset)) }
    private var displaySetIndex: Int { min(setsTarget, completedSets + 1) }

    private var progress: Double {
        let done = Double(completedSets) + (Double(withinSetReps) / Double(repsPerSet))
        return min(1, done / Double(setsTarget))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            SkeletonOverlay(frame: camera.frame)
                .ignoresSafeArea()
                .opacity(0.78)

            VStack(spacing: 28) {
                topBar
                Spacer()
                centerPanel
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .foregroundStyle(.white)
        .interactiveDismissDisabled(store.inAppLockEnabled && !isComplete)
        .onAppear {
            startedAt = .now
            poseSamples.removeAll()
            lastPoseSampleAt = .distantPast
            visibleSampleCount = 0
            analyzedSampleCount = 0
            shareURL = nil
            shareStatusText = nil
            trackedJointTotal = 0
            kneeAngleTotal = 0
            kneeAngleSampleCount = 0
            lowestKneeAngle = nil
            standingKneeAngle = nil
            Haptics.mediumTap()
            didClearWorkoutSessionLock = false
            workoutSessionLockTask?.cancel()
            if !isTutorial {
                workoutSessionLockTask = Task {
                    await shielding.applyWorkoutSessionLock()
                }
            }
            camera.applyCalibration(isTutorial ? nil : store.tutorialCalibration)
            activeMusicTrack = WorkoutMusicTrack.randomWorkoutTrack(fallback: store.selectedMusicTrack)
            hasStartedMusic = false
            completedSets = 0
            setStartRepOffset = 0
            camera.start()
            if !isTutorial {
                WorkoutLiveActivityService.start(exercise: exercise, targetReps: repsPerSet, totalSets: setsTarget)
            }
        }
        .onDisappear {
            workoutSessionLockTask?.cancel()
            workoutSessionLockTask = nil
            camera.stop()
            musicPlayer.stop()
            WorkoutLiveActivityService.end()
        }
        .onChange(of: store.workoutMusicVolume) { _, volume in
            musicPlayer.updateVolume(volume)
        }
        .onChange(of: store.workoutMusicEnabled) { _, isEnabled in
            if isEnabled {
                startWorkoutMusic(forceRestart: true)
            } else {
                musicPlayer.start(track: activeMusicTrack, volume: store.workoutMusicVolume, isEnabled: false)
                hasStartedMusic = false
            }
        }
        .onChange(of: camera.status) { _, status in
            guard status == .running else { return }
            startWorkoutMusic(forceRestart: false)
        }
        .onChange(of: store.tutorialCalibration) { _, calibration in
            guard !isTutorial else { return }
            camera.applyCalibration(calibration)
        }
        .onChange(of: camera.frame.repCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            handleRepProgress(newRepCount: newValue)
        }
        .onChange(of: camera.firstPoseSnapshotData) { oldValue, newValue in
            guard oldValue == nil, newValue != nil else { return }
            Haptics.lightTap()
        }
        .onReceive(camera.$frame) { frame in
            appendAutoPoseSample(frame)
        }
    }

    private func startWorkoutMusic(forceRestart: Bool) {
        guard store.workoutMusicEnabled else {
            musicPlayer.start(track: activeMusicTrack, volume: store.workoutMusicVolume, isEnabled: false)
            hasStartedMusic = false
            return
        }
        guard camera.status == .running else { return }
        guard forceRestart || !hasStartedMusic else { return }

        let bundledTracks = WorkoutMusicTrack.allCases.filter { $0.bundledURL() != nil }
        let fallbackTracks = (WorkoutMusicTrack.availableRandomPool() + bundledTracks).filter { $0 != activeMusicTrack }
        if let startedTrack = musicPlayer.start(
            track: activeMusicTrack,
            volume: store.workoutMusicVolume,
            isEnabled: true,
            fallbackTracks: fallbackTracks
        ) {
            activeMusicTrack = startedTrack
            hasStartedMusic = true
            WorkoutMusicTrack.saveLastWorkoutTrack(startedTrack)
        } else {
            hasStartedMusic = false
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            SessionMetric(value: "\(repsPerSet)", label: "1セット")
            SessionMetric(value: "\(min(completedSets, setsTarget))/\(setsTarget)", label: "セット")
            SessionMetric(value: isComplete ? "OPEN" : "LOCK", label: "状態")
        }
    }

    private var centerPanel: some View {
        VStack(spacing: 8) {
            Text("\(withinSetReps)")
                .font(.system(size: 148, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.55)

            Text("/ \(repsPerSet)回")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(WorkoutTheme.orange)

            Text(isComplete ? exercise.title : "セット \(displaySetIndex) / \(setsTarget)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.top, 4)

            WorkoutBuddyView(
                phase: camera.frame.phase,
                progress: progress,
                isComplete: isComplete,
                size: .hero
            )
            .frame(width: 174, height: 136)
            .padding(.vertical, 4)

            Text(camera.frame.guidance)
                .font(.headline.weight(.heavy))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Label(camera.status.title, systemImage: "camera.viewfinder")
                if let kneeAngle = camera.frame.kneeAngle {
                    Text("\(Int(kneeAngle))°")
                        .monospacedDigit()
                }
            }
            .font(.caption.weight(.black))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.black)
            .background(WorkoutTheme.orange, in: Capsule())

            if case .unavailable(let reason) = camera.status {
                Text(reason)
                    .font(.caption.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.74))
            }

            if store.workoutMusicEnabled {
                Label(musicPlayer.statusText, systemImage: "music.note")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if isTutorial {
                Text(camera.firstPoseSnapshotData == nil ? "立ち姿を検出したら今のあなたを自動で記録します" : "今のあなたを記録しました。あとは5回だけ。")
                    .font(.caption.weight(.black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
            ProgressView(value: progress)
                .tint(WorkoutTheme.orange)
                .scaleEffect(x: 1, y: 2.4, anchor: .center)

            if isComplete {
                Button {
                    Haptics.selection()
                    if let onFinished {
                        onFinished()
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(isTutorial ? "設定を続ける" : "解除")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkoutTheme.orange)
                .foregroundStyle(.black)

                if !isTutorial, let shareURL {
                    VStack(spacing: 10) {
                        ShareLink(
                            item: shareURL,
                            message: Text("筋トレロックで\(min(camera.frame.repCount, targetReps))回達成！ #筋トレロック"),
                            preview: SharePreview("筋トレロック \(min(camera.frame.repCount, targetReps))回達成", image: shareURL)
                        ) {
                            Label("結果をシェア", systemImage: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button(action: shareToInstagramStories) {
                            Label("Instagramでシェア", systemImage: "camera")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        if let shareStatusText {
                            Text(shareStatusText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                Text(isTutorial ? "まずは5回成功させよう" : "終わるまでアプリ制限中")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white.opacity(0.74))
            }

            #if targetEnvironment(simulator)
            Button {
                Haptics.lightTap()
                camera.debugAddRep()
            } label: {
                Label("シミュレーターで1回加算", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(WorkoutTheme.orange)
            #endif
        }
    }

    private func handleRepProgress(newRepCount: Int) {
        let within = newRepCount - setStartRepOffset
        if within >= repsPerSet {
            completedSets += 1
            setStartRepOffset = newRepCount
            Haptics.success()
            if completedSets >= setsTarget {
                updateLiveActivity(isComplete: true)
                completeIfNeeded(actualReps: newRepCount)
                return
            }
        } else {
            Haptics.mediumTap()
        }
        updateLiveActivity(isComplete: false)
    }

    private func updateLiveActivity(isComplete: Bool) {
        guard !isTutorial else { return }
        WorkoutLiveActivityService.update(
            currentReps: withinSetReps,
            targetReps: repsPerSet,
            currentSet: displaySetIndex,
            totalSets: setsTarget,
            isComplete: isComplete
        )
    }

    private func completeIfNeeded(actualReps: Int) {
        isComplete = true
        guard !didSave else { return }
        didSave = true
        Haptics.success()
        camera.stop()
        musicPlayer.stop()
        clearWorkoutSessionLockIfNeeded()
        store.completeWorkout(
            actualReps: actualReps,
            duration: Date().timeIntervalSince(startedAt),
            snapshotData: isTutorial ? camera.firstPoseSnapshotData ?? camera.latestSnapshotData : camera.latestSnapshotData,
            targetReps: targetReps,
            countsTowardDailyCompletion: !isTutorial
        )
        if isTutorial {
            store.applyTutorialCalibration(makeTutorialCalibration(actualReps: actualReps))
        } else if let latest = store.records.first {
            shareStatusText = nil
            shareURL = WorkoutShareImageRenderer.makeImageURL(
                record: latest,
                streakDays: store.streakDays,
                totalReps: store.totalReps
            )
        }
        saveAutoDatasetIfNeeded(actualReps: actualReps)
    }

    private func clearWorkoutSessionLockIfNeeded() {
        workoutSessionLockTask?.cancel()
        workoutSessionLockTask = nil
        guard !isTutorial, !didClearWorkoutSessionLock else { return }
        didClearWorkoutSessionLock = true
        shielding.clearWorkoutSessionLock()
    }

    private func shareToInstagramStories() {
        shareStatusText = nil
        guard let latest = store.records.first,
              let pngData = WorkoutShareImageRenderer.makePNGData(
                record: latest,
                streakDays: store.streakDays,
                totalReps: store.totalReps
              ) else {
            shareStatusText = "シェア画像を準備できませんでした。"
            return
        }

        WorkoutInstagramShare.shareToStories(pngData: pngData) { success in
            guard !success else { return }
            shareStatusText = "Instagramを開けませんでした。通常の共有を使えます。"
        }
    }

    private func appendAutoPoseSample(_ frame: PoseFrame) {
        guard !isComplete else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPoseSampleAt) >= 0.1 else { return }
        lastPoseSampleAt = now
        updateSessionMetrics(frame)
        guard store.dataConsentAccepted != false else { return }

        let joints = frame.points.map { point in
            DatasetJointSample(
                joint: point.id.rawValue,
                x: point.location.x,
                y: point.location.y,
                confidence: point.confidence
            )
        }

        poseSamples.append(DatasetPoseSample(
            id: UUID(),
            elapsedSeconds: now.timeIntervalSince(startedAt),
            recordedAt: now,
            repCount: frame.repCount,
            phase: frame.phase.rawValue,
            guidance: frame.guidance,
            kneeAngle: frame.kneeAngle,
            joints: joints
        ))
    }

    private func updateSessionMetrics(_ frame: PoseFrame) {
        analyzedSampleCount += 1
        if !frame.points.isEmpty {
            visibleSampleCount += 1
        }
        trackedJointTotal += frame.points.count
        if let kneeAngle = frame.kneeAngle {
            kneeAngleTotal += kneeAngle
            kneeAngleSampleCount += 1
            lowestKneeAngle = min(lowestKneeAngle ?? kneeAngle, kneeAngle)
            if frame.phase == .standing {
                standingKneeAngle = max(standingKneeAngle ?? kneeAngle, kneeAngle)
            }
        }
    }

    private func makeTutorialCalibration(actualReps: Int) -> TutorialCalibration {
        let sampleCount = max(1, analyzedSampleCount)
        let averageKneeAngle = kneeAngleSampleCount > 0 ? kneeAngleTotal / Double(kneeAngleSampleCount) : nil
        return TutorialCalibration(
            completedAt: .now,
            targetReps: targetReps,
            actualReps: actualReps,
            duration: Date().timeIntervalSince(startedAt),
            sampleCount: sampleCount,
            visibleSampleRatio: Double(visibleSampleCount) / Double(sampleCount),
            averageTrackedJoints: Double(trackedJointTotal) / Double(sampleCount),
            averageKneeAngle: averageKneeAngle,
            lowestKneeAngle: lowestKneeAngle,
            standingKneeAngle: standingKneeAngle
        )
    }

    private func saveAutoDatasetIfNeeded(actualReps: Int) {
        guard store.dataConsentAccepted != false else { return }
        guard actualReps > 0, !poseSamples.isEmpty else { return }

        let metadata = DatasetRecordingMetadata(
            id: UUID(),
            appSchemaVersion: 1,
            createdAt: startedAt,
            participantCode: "auto-p01",
            exercise: datasetExercise(from: exercise),
            label: .good,
            cameraAngle: .unknown,
            phonePlacement: "通常ワークアウト",
            environmentNote: "自動収集",
            freeNote: isTutorial ? "tutorial-auto" : "workout-auto",
            sampleCount: poseSamples.count,
            duration: Date().timeIntervalSince(startedAt)
        )
        datasetStore.save(recording: DatasetRecording(metadata: metadata, samples: poseSamples))
    }

    private func datasetExercise(from exercise: ExerciseKind) -> DatasetExerciseKind {
        switch exercise {
        case .squat:
            return .squat
        }
    }
}

private struct SessionMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
    }
}
