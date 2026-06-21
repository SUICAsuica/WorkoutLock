import SwiftUI
#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
#endif

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var shielding = ScreenShieldingService()
    @State private var showBlockPicker = false

    var body: some View {
        ZStack {
            WorkoutTheme.orange.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("設定")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("ロック")
                            .font(.title2.weight(.black))
                        Toggle("完了まで閉じにくくする", isOn: $store.inAppLockEnabled)
                            .font(.headline.weight(.bold))
                            .onChange(of: store.inAppLockEnabled) { _, _ in
                                Haptics.selection()
                            }
                        SettingsLine(title: "状態", value: store.inAppLockEnabled ? "有効" : "無効")
                    }
                    .settingsPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("通知")
                            .font(.title2.weight(.black))
                        SettingsLine(title: "起動条件", value: store.triggerPreference.title)
                        SettingsLine(title: "今の表示", value: store.primaryTriggerLabel)
                        SettingsLine(title: "時刻通知", value: store.triggerPreference == .homeArrival ? "停止中" : store.nextAlarmLabel)
                        SettingsLine(title: "帰宅後通知", value: store.homeTriggerLabel ?? "未設定")
                    }
                    .settingsPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("体重・目標")
                            .font(.title2.weight(.black))
                        SettingsLine(title: "現在の体重", value: "\(store.currentWeightKg.formatted(.number.precision(.fractionLength(1))))kg")
                        SettingsLine(title: "目標体重", value: "\(store.goalWeightKg.formatted(.number.precision(.fractionLength(1))))kg")
                        SettingsLine(title: "次の入力", value: store.nextWeightCheckInLabel)
                        if let latest = store.latestWeightCheckIn {
                            SettingsLine(
                                title: "直近の調整",
                                value: "\(latest.targetRepsBefore)回 -> \(latest.targetRepsAfter)回"
                            )
                        }
                    }
                    .settingsPanel()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("BGM")
                            .font(.title2.weight(.black))

                        Toggle("ワークアウト中に流す", isOn: $store.workoutMusicEnabled)
                            .font(.headline.weight(.bold))
                            .onChange(of: store.workoutMusicEnabled) { _, _ in
                                Haptics.selection()
                            }

                        Picker("曲", selection: $store.selectedMusicTrack) {
                            ForEach(WorkoutMusicTrack.allCases) { track in
                                Text(track.title).tag(track)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.black)
                        .disabled(!store.workoutMusicEnabled)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("音量")
                                    .foregroundStyle(Color.black.opacity(0.62))
                                Spacer()
                                Text("\(Int(store.workoutMusicVolume * 100))%")
                                    .fontWeight(.black)
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(.bold))

                            Slider(value: $store.workoutMusicVolume, in: 0.1...1)
                                .tint(.black)
                                .disabled(!store.workoutMusicEnabled)
                        }

                        SettingsLine(title: "選択中", value: store.selectedMusicTrack.subtitle)
                    }
                    .settingsPanel()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("アプリ制限")
                            .font(.title2.weight(.black))
                        BlockingReadinessRow(
                            title: "ロック状態",
                            value: shielding.readinessText(isEnabled: store.appBlockingEnabled),
                            isReady: store.appBlockingEnabled && shielding.hasConfiguredSelection
                        )
                        Text(shielding.capabilityText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.62))

                        Toggle("アプリブロックをオン", isOn: $store.appBlockingEnabled)
                            .font(.headline.weight(.bold))

                        Button {
                            Haptics.selection()
                            Task { await shielding.requestAuthorization() }
                        } label: {
                            Label("Screen Time権限を確認", systemImage: "lock.shield")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)

                        Button {
                            Haptics.selection()
                            showBlockPicker = true
                        } label: {
                            Label("ブロックするアプリを選ぶ", systemImage: "app.badge")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(.black)

                        SettingsLine(title: "ブロック対象", value: shielding.selectionSummary)
                        SettingsLine(title: "接続状態", value: shielding.statusText)
                    }
                    .settingsPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("判定")
                            .font(.title2.weight(.black))
                        SettingsLine(title: "姿勢モデル", value: "Apple Vision")
                        SettingsLine(title: "現在の種目", value: store.selectedExercise.title)
                        SettingsLine(title: "解除条件", value: "\(store.targetReps)回")
                    }
                    .settingsPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("その他")
                            .font(.title2.weight(.black))

                        Button {
                            Haptics.selection()
                            store.onboardingCompleted = false
                        } label: {
                            Label("オンボーディングをやり直す", systemImage: "arrow.counterclockwise")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(.black)

                        Text("記録・ログ・設定は残したまま、最初の流れをもう一度見られます。")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.62))
                    }
                    .settingsPanel()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .familyActivityPicker(isPresented: $showBlockPicker, selection: $shielding.selection)
        .onChange(of: showBlockPicker) { _, isPresented in
            if !isPresented {
                shielding.applyShielding(isEnabled: store.appBlockingEnabled)
            }
        }
        #endif
        .onChange(of: store.appBlockingEnabled) { _, isEnabled in
            if !isEnabled {
                shielding.applyShielding(isEnabled: false)
            }
        }
    }
}

private struct SettingsLine: View {
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

private struct BlockingReadinessRow: View {
    let title: String
    let value: String
    let isReady: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.black.opacity(0.62))
            Spacer()
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(isReady ? WorkoutInk.primary : Color.black.opacity(0.62))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isReady ? .black.opacity(0.12) : .black.opacity(0.06),
                    in: Capsule()
                )
        }
    }
}

private extension View {
    func settingsPanel() -> some View {
        self
            .padding(20)
            .liquidGlass(cornerRadius: 24)
    }
}
