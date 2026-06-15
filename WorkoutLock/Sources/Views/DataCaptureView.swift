import SwiftUI

struct DataCaptureView: View {
    @StateObject private var camera = WorkoutCameraModel()
    @StateObject private var datasetStore = DatasetStore()

    @State private var participantCode = "p01"
    @State private var exercise: DatasetExerciseKind = .squat
    @State private var label: DatasetRepLabel = .good
    @State private var cameraAngle: DatasetCameraAngle = .front
    @State private var phonePlacement = "胸くらいの高さ"
    @State private var environmentNote = "室内・通常照明"
    @State private var freeNote = ""
    @State private var samples: [DatasetPoseSample] = []
    @State private var recordingStartedAt: Date?
    @State private var lastSampleAt = Date.distantPast
    @State private var showingDetails = false

    private let dailyTasks = [
        CapturePlanTask(title: "成功・正面", label: .good, angle: .front, environment: "室内・通常照明", note: "普通の深さで成功スクワット", targetReps: 50),
        CapturePlanTask(title: "成功・斜め", label: .good, angle: .diagonal, environment: "室内・通常照明", note: "斜めから普通の成功スクワット", targetReps: 50),
        CapturePlanTask(title: "成功・横", label: .good, angle: .side, environment: "室内・通常照明", note: "横から普通の成功スクワット", targetReps: 50),
        CapturePlanTask(title: "浅い・正面", label: .shallow, angle: .front, environment: "室内・通常照明", note: "あえて浅く止める", targetReps: 50),
        CapturePlanTask(title: "崩れ・正面", label: .badForm, angle: .front, environment: "室内・通常照明", note: "膝だけ曲げる/前傾しすぎ", targetReps: 50),
        CapturePlanTask(title: "画角外・正面", label: .outOfFrame, angle: .front, environment: "室内・通常照明", note: "足首切れ/近すぎ/遠すぎ", targetReps: 50)
    ]

    private var isRecording: Bool {
        recordingStartedAt != nil
    }

    private var currentEstimatedReps: Int {
        samples.map(\.repCount).max() ?? 0
    }

    private var phaseOneReps: Int {
        datasetStore.totalEstimatedReps(exercise: .squat)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.78), .clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            SkeletonOverlay(frame: camera.frame)
                .ignoresSafeArea()
                .opacity(0.82)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    currentTaskCard
                    recordingControls
                    phaseProgress
                    todaysPlan
                    detailsPanel
                    savedFiles
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("学習データ収録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black.opacity(0.3), for: .navigationBar)
        .foregroundStyle(.white)
        .onAppear {
            camera.start()
            datasetStore.reload()
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(camera.$frame) { frame in
            appendSampleIfNeeded(frame)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("収録")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text(isRecording ? "このセットを終えたら保存" : "メニューを選んで10回やる")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            Spacer()
            Circle()
                .fill(isRecording ? .red : WorkoutTheme.orange)
                .frame(width: 14, height: 14)
                .shadow(color: isRecording ? .red.opacity(0.8) : .clear, radius: 10)
                .padding(.top, 8)
        }
    }

    private var currentTaskCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(WorkoutTheme.orange)
                    Text("\(cameraAngle.title) / \(participantCode)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Text("\(currentEstimatedReps)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                MiniStatus(value: "\(samples.count)", title: "samples")
                MiniStatus(value: camera.frame.kneeAngle.map { "\(Int($0))°" } ?? "--", title: "knee")
                MiniStatus(value: camera.status.title, title: "status")
            }
        }
        .padding(16)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    }

    private var phaseProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Phase 1")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Spacer()
                Text("\(phaseOneReps)/600 回")
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(WorkoutTheme.orange)
            }

            ProgressView(value: min(Double(phaseOneReps) / 600.0, 1))
                .tint(WorkoutTheme.orange)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            Text("成功 \(datasetStore.totalEstimatedReps(exercise: .squat, label: .good))/300  浅い \(datasetStore.totalEstimatedReps(exercise: .squat, label: .shallow))/100  崩れ \(datasetStore.totalEstimatedReps(exercise: .squat, label: .badForm))/100  画角外 \(datasetStore.totalEstimatedReps(exercise: .squat, label: .outOfFrame))/100")
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
        }
        .padding(14)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var todaysPlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("次にやる")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Spacer()
                Text("各50回")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
            }

            ForEach(dailyTasks) { task in
                let progress = datasetStore.totalEstimatedReps(
                    exercise: .squat,
                    label: task.label,
                    angle: task.angle
                )
                Button {
                    apply(task)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: progress >= task.targetReps ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.black))
                            .foregroundStyle(progress >= task.targetReps ? WorkoutTheme.orange : .white.opacity(0.42))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.headline.weight(.black))
                        }

                        Spacer()

                        Text("\(min(progress, task.targetReps))/\(task.targetReps)")
                            .font(.caption.monospacedDigit().weight(.black))
                            .foregroundStyle(WorkoutTheme.orange)
                    }
                    .padding(12)
                    .background(isCurrent(task) ? WorkoutTheme.orange.opacity(0.22) : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Label(isRecording ? "停止して保存" : "収録開始", systemImage: isRecording ? "stop.fill" : "record.circle")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : WorkoutTheme.orange)
                .foregroundStyle(isRecording ? .white : .black)

                Button {
                    Haptics.lightTap()
                    samples.removeAll()
                    recordingStartedAt = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.black))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(samples.isEmpty && !isRecording)
            }

            Text(isRecording ? "\(currentEstimatedReps)回くらい取れたら停止して保存" : camera.frame.guidance)
                .font(.headline.weight(.black))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))

            if case .unavailable(let reason) = camera.status {
                Text(reason)
                    .font(.caption.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WorkoutTheme.orange)
            }
        }
        .padding(14)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detailsPanel: some View {
        DisclosureGroup(isExpanded: $showingDetails) {
            setupPanel
                .padding(.top, 10)
        } label: {
            HStack {
                Text("詳細設定")
                    .font(.headline.weight(.black))
                Spacer()
                Text("\(exercise.title) / \(label.title)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .tint(WorkoutTheme.orange)
        .padding(14)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("participant", text: $participantCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .captureFieldStyle()

            CapturePicker(title: "種目", selection: $exercise) { item in
                item.title
            }

            CapturePicker(title: "正解ラベル", selection: $label) { item in
                item.title
            }

            CapturePicker(title: "撮影角度", selection: $cameraAngle) { item in
                item.title
            }

            TextField("スマホ位置", text: $phonePlacement)
                .captureFieldStyle()

            TextField("環境", text: $environmentNote)
                .captureFieldStyle()

            TextField("メモ", text: $freeNote, axis: .vertical)
                .lineLimit(2...4)
                .captureFieldStyle()
        }
    }

    private var savedFiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("記録")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Spacer()
                Text("\(datasetStore.files.count)件")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            if datasetStore.files.isEmpty {
                Text("停止して保存するとJSONがここに出ます。AirDropやFiles経由でRTX側に送れます。")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                ForEach(datasetStore.files) { file in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.title)
                                .font(.headline.weight(.black))
                            Text("\(file.estimatedReps) 回")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer()
                        ShareLink(item: file.url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline.weight(.black))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(.black)
                                .background(WorkoutTheme.orange, in: Circle())
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .swipeActions {
                        Button(role: .destructive) {
                            datasetStore.delete(file)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private func startRecording() {
        Haptics.mediumTap()
        samples.removeAll()
        recordingStartedAt = .now
        lastSampleAt = .distantPast
    }

    private func stopRecording() {
        guard let startedAt = recordingStartedAt else { return }
        recordingStartedAt = nil
        guard !samples.isEmpty else {
            Haptics.warning()
            return
        }

        let metadata = DatasetRecordingMetadata(
            id: UUID(),
            appSchemaVersion: 1,
            createdAt: startedAt,
            participantCode: participantCode,
            exercise: exercise,
            label: label,
            cameraAngle: cameraAngle,
            phonePlacement: phonePlacement,
            environmentNote: environmentNote,
            freeNote: freeNote,
            sampleCount: samples.count,
            duration: Date().timeIntervalSince(startedAt)
        )
        datasetStore.save(recording: DatasetRecording(metadata: metadata, samples: samples))
        samples.removeAll()
    }

    private func apply(_ task: CapturePlanTask) {
        Haptics.selection()
        exercise = .squat
        label = task.label
        cameraAngle = task.angle
        environmentNote = task.environment
        freeNote = task.note
    }

    private func isCurrent(_ task: CapturePlanTask) -> Bool {
        exercise == .squat
            && label == task.label
            && cameraAngle == task.angle
            && freeNote == task.note
    }

    private func appendSampleIfNeeded(_ frame: PoseFrame) {
        guard let startedAt = recordingStartedAt else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSampleAt) >= 0.1 else { return }
        lastSampleAt = now

        let joints = frame.points.map { point in
            DatasetJointSample(
                joint: point.id.rawValue,
                x: point.location.x,
                y: point.location.y,
                confidence: point.confidence
            )
        }

        samples.append(DatasetPoseSample(
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
}

private struct MiniStatus: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.black))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CapturePlanTask: Identifiable {
    let id = UUID()
    let title: String
    let label: DatasetRepLabel
    let angle: DatasetCameraAngle
    let environment: String
    let note: String
    let targetReps: Int
}

private struct CapturePicker<Value: CaseIterable & Identifiable & Hashable>: View {
    let title: String
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(Array(Value.allCases)) { item in
                    Text(label(item)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .tint(WorkoutTheme.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func captureFieldStyle() -> some View {
        self
            .font(.headline.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
