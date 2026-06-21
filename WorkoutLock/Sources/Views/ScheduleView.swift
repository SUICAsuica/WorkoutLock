import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationTrigger: LocationTriggerService

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
                        Text("起動条件")
                            .font(.title2.weight(.black))

                        Picker("起動条件", selection: $store.triggerPreference) {
                            ForEach(TriggerPreference.allCases) { preference in
                                Text(triggerSegmentTitle(for: preference))
                                    .tag(preference)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: store.triggerPreference) { _, preference in
                            Haptics.selection()
                            locationTrigger.startMonitoring(locations: store.triggerLocations)
                            if preference == .homeArrival {
                                Task { await store.scheduleDailyAlarm() }
                            }
                        }

                        Text(store.triggerPreference.subtitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutInk.secondary)
                    }
                    .schedulePanel()

                    if usesTimeTrigger {
                        timeTriggerPanel
                    }

                    locationTriggerPanel
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            locationTrigger.startMonitoring(locations: store.triggerLocations)
        }
        .onChange(of: locationTrigger.capturedHomeLocation) { _, location in
            guard let location else { return }
            store.upsertTriggerLocation(location)
            locationTrigger.startMonitoring(locations: store.triggerLocations)
        }
    }

    private var usesTimeTrigger: Bool {
        store.triggerPreference == .time || store.triggerPreference == .both
    }

    private var locationTriggerPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("場所トリガー")
                .font(.title2.weight(.black))

            Button {
                Haptics.selection()
                locationTrigger.requestLocation(kind: .home, delayMinutes: 10)
            } label: {
                Label("今いる場所を登録", systemImage: "location.fill")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkoutTheme.accent)

            if store.triggerLocations.isEmpty {
                Text(locationTrigger.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutInk.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.triggerLocations) { location in
                        TriggerLocationRow(location: location) {
                            Haptics.lightTap()
                            store.removeTriggerLocation(location)
                            locationTrigger.startMonitoring(locations: store.triggerLocations)
                        }
                    }
                }

                Text(locationTrigger.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutInk.secondary)
            }

            Text("帰宅後はアプリをロックして通知します。解除は完了後のみです。")
                .font(.caption.weight(.bold))
                .foregroundStyle(WorkoutInk.secondary)
        }
        .schedulePanel()
    }

    private var timeTriggerPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("時刻トリガー")
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

            Text("時刻になると通知し、選択したアプリをロックします。")
                .font(.caption.weight(.bold))
                .foregroundStyle(WorkoutInk.secondary)
        }
        .schedulePanel()
    }

    private func triggerSegmentTitle(for preference: TriggerPreference) -> String {
        switch preference {
        case .time:
            return "時刻"
        case .homeArrival:
            return "帰宅後"
        case .both:
            return "両方"
        }
    }
}

private struct TriggerLocationRow: View {
    let location: HomeLocation
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3.weight(.black))
                .foregroundStyle(WorkoutTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(location.triggerSummary)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(WorkoutInk.primary)
                Text(location.shortLabel)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(WorkoutInk.secondary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(WorkoutInk.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("場所トリガーを削除")
        }
        .padding(12)
        .background(WorkoutInk.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
