import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationTrigger: LocationTriggerService
    @State private var locationKind: TriggerLocationKind = .home
    @State private var delayMinutes = 10

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

                        Stepper(value: $store.targetReps, in: 3...50) {
                            HStack {
                                Text("回数")
                                Spacer()
                                Text("\(store.targetReps)回")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                        .onChange(of: store.targetReps) { _, _ in
                            Haptics.lightTap()
                        }
                    }
                    .schedulePanel()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("起動条件")
                            .font(.title2.weight(.black))

                        Picker("起動条件", selection: $store.triggerPreference) {
                            Text("時刻").tag(TriggerPreference.time)
                            Text("帰宅後").tag(TriggerPreference.homeArrival)
                            Text("両方").tag(TriggerPreference.both)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: store.triggerPreference) { _, preference in
                            Haptics.selection()
                            if preference == .homeArrival {
                                Task { await store.scheduleDailyAlarm() }
                            }
                        }

                        SettingsLikeLine(title: "現在", value: store.primaryTriggerLabel)
                    }
                    .schedulePanel()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("時刻通知")
                            .font(.title2.weight(.black))

                        DatePicker("毎日の時刻", selection: $store.alarmTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .disabled(store.triggerPreference == .homeArrival)
                            .opacity(store.triggerPreference == .homeArrival ? 0.45 : 1)

                        Toggle("通知を有効化", isOn: $store.isAlarmEnabled)
                            .disabled(store.triggerPreference == .homeArrival)
                            .opacity(store.triggerPreference == .homeArrival ? 0.45 : 1)
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
                            Text(store.triggerPreference == .homeArrival ? "帰宅後通知を使う" : "時刻通知を更新")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WorkoutTheme.accent)

                        Text(store.notificationMessage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutInk.secondary)

                        if store.triggerPreference == .homeArrival {
                            Text("帰宅後だけを使う場合、毎日9:30のような時刻通知は予約しません。")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WorkoutInk.secondary)
                        }
                    }
                    .schedulePanel()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("場所トリガー")
                            .font(.title2.weight(.black))

                        Picker("場所", selection: $locationKind) {
                            ForEach(TriggerLocationKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        Stepper("到着\(delayMinutes)分後", value: $delayMinutes, in: 10...60, step: 5)
                            .font(.headline.weight(.black))

                        Button {
                            Haptics.selection()
                            store.triggerPreference = .homeArrival
                            locationTrigger.requestLocation(kind: locationKind, delayMinutes: delayMinutes)
                        } label: {
                            Label("今いる場所を登録", systemImage: "location.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WorkoutTheme.accent)

                        Button {
                            Haptics.selection()
                            locationTrigger.runForegroundTriggerTest(afterSeconds: 30)
                        } label: {
                            Label("動作テスト（30秒後に自動開始）", systemImage: "bolt.fill")
                                .font(.subheadline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(WorkoutTheme.accent)

                        if store.triggerLocations.isEmpty {
                            Text(locationTrigger.statusText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WorkoutInk.secondary)
                        } else {
                            ForEach(store.triggerLocations) { location in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(location.triggerSummary)
                                            .font(.headline.weight(.black))
                                        Text(location.shortLabel)
                                            .font(.caption.monospacedDigit().weight(.bold))
                                            .foregroundStyle(WorkoutInk.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        Haptics.lightTap()
                                        store.removeTriggerLocation(location)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .schedulePanel()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: locationTrigger.capturedHomeLocation) { _, location in
            guard let location else { return }
            store.triggerPreference = .homeArrival
            store.upsertTriggerLocation(location)
            locationTrigger.startMonitoring(locations: store.triggerLocations)
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
