import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            WorkoutTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("予定")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("解除条件")
                            .font(.title2.weight(.black))

                        Picker("種目", selection: $store.selectedExercise) {
                            ForEach(ExerciseKind.allCases) { exercise in
                                Label(exercise.title, systemImage: exercise.systemImage)
                                    .tag(exercise)
                            }
                        }
                        .onChange(of: store.selectedExercise) { _, _ in
                            Haptics.selection()
                        }

                        SettingsLikeLine(title: "今日", value: "\(store.targetReps)回")
                        SettingsLikeLine(title: "次", value: store.nextPlanTargetSummary)
                    }
                    .schedulePanel()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("時刻通知")
                            .font(.title2.weight(.black))

                        DatePicker("毎日の時刻", selection: $store.alarmTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)

                        Toggle("通知を有効化", isOn: $store.isAlarmEnabled)
                            .onChange(of: store.isAlarmEnabled) { _, isEnabled in
                                Haptics.selection()
                                Task {
                                    if isEnabled {
                                        await store.scheduleDailyAlarm()
                                    } else {
                                        await store.cancelDailyAlarm()
                                    }
                                }
                            }

                        Button {
                            Haptics.selection()
                            Task { await store.scheduleDailyAlarm() }
                        } label: {
                            Text("時刻通知を更新")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WorkoutTheme.accent)

                        Text(store.notificationMessage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutInk.secondary)

                        Text("通知をタップするとワークアウトを開始できます。アプリを閉じている間の自動開始はしません。")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutInk.secondary)
                    }
                    .schedulePanel()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if store.triggerPreference != .time {
                store.triggerPreference = .time
            }
        }
    }
}

private extension View {
    func schedulePanel() -> some View {
        self
            .padding(20)
            .liquidGlass(cornerRadius: 24)
    }
}

private struct SettingsLikeLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(WorkoutInk.secondary)
            Spacer()
            Text(value)
                .fontWeight(.black)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .font(.subheadline.weight(.bold))
    }
}
