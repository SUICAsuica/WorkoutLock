import AuthenticationServices
import MapKit
import SwiftUI
#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
#endif

private enum OnboardingStep: Int {
    case quickTrial
    case signIn
    case consent
    case profile
    case goal
    case plan
    case commitmentBlock
    case commitmentTrigger
    case tutorialIntro
    case trigger
}

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationTrigger: LocationTriggerService
    @StateObject private var shielding = ScreenShieldingService()
    @State private var step: OnboardingStep = .quickTrial
    @State private var showTutorial = false
    @State private var nextStepAfterTutorial: OnboardingStep = .trigger
    @State private var signInErrorMessage: String?
    @State private var showBlockPicker = false
    @State private var isGeneratingPlan = false
    @State private var locationKind: TriggerLocationKind = .home
    @State private var locationDelayMinutes = 10
    @State private var showMapPicker = false

    var body: some View {
        ZStack {
            WorkoutTheme.orange.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    progressHeader

                    switch step {
                    case .quickTrial:
                        quickTrialStep
                    case .signIn:
                        signInStep
                    case .consent:
                        consentStep
                    case .profile:
                        profileStep
                    case .goal:
                        goalStep
                    case .plan:
                        planStep
                    case .commitmentBlock:
                        commitmentBlockStep
                    case .commitmentTrigger:
                        commitmentTriggerStep
                    case .tutorialIntro:
                        tutorialIntroStep
                    case .trigger:
                        triggerStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            WorkoutSessionView(
                exercise: .squat,
                targetReps: 5,
                tutorialPlan: store.selectedPlan
            ) {
                store.markTutorialCompleted()
                showTutorial = false
                step = nextStepAfterTutorial
            }
            .environmentObject(store)
        }
        .onChange(of: locationTrigger.capturedHomeLocation) { _, location in
            guard let location else { return }
            store.upsertTriggerLocation(location)
        }
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
        .sheet(isPresented: $showMapPicker) {
            LocationMapPickerView(
                kind: locationKind,
                delayMinutes: locationDelayMinutes
            ) { location in
                store.triggerPreference = .homeArrival
                store.upsertTriggerLocation(location)
                locationTrigger.startMonitoring(locations: store.triggerLocations)
            }
        }
    }

    private var usesHomeTrigger: Bool {
        store.triggerPreference == .homeArrival || store.triggerPreference == .both
    }

    private var progressHeader: some View {
        HStack {
            Text("SETUP")
                .font(.caption.weight(.black))
                .tracking(2)
            Spacer()
            Text("\(step.rawValue + 1)/10")
                .font(.caption.monospacedDigit().weight(.black))
        }
        .foregroundStyle(WorkoutTheme.mutedInk)
    }

    private var quickTrialStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingTitle(
                title: "まず5回だけ試す",
                subtitle: "設定より先に、カメラでスクワットが数えられるか確認します。ここで取った動きは、あとで判定補正に使います。"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34, weight: .black))
                        .frame(width: 58, height: 58)
                        .foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("全身が入ればOK")
                            .font(.title3.weight(.black))
                        Text("iPhoneを少し離して置いて、まずは5回だけ。")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutTheme.mutedInk)
                    }
                }

                if let calibration = store.tutorialCalibration {
                    SettingsLineLike(title: "前回の判定品質", value: "\(calibration.qualityScore)%")
                    SettingsLineLike(title: "平均ペース", value: "\(calibration.secondsPerRep.formatted(.number.precision(.fractionLength(1))))秒/回")
                }
            }
            .onboardingPanel()

            Button {
                Haptics.mediumTap()
                nextStepAfterTutorial = .signIn
                showTutorial = true
            } label: {
                FullWidthPrimaryLabel(title: "5回だけ試す", systemImage: "play.fill", minHeight: 72)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                step = .signIn
            } label: {
                FullWidthSecondaryLabel(title: "設定から始める")
            }
            .buttonStyle(.plain)
        }
    }

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingTitle(
                title: "まずは本人確認",
                subtitle: "記録とプランをあなたの端末に紐づけます。"
            )

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success:
                    signInErrorMessage = nil
                    store.markAppleSignedIn()
                    step = .consent
                case .failure(let error):
                    signInErrorMessage = appleSignInErrorMessage(for: error)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let signInErrorMessage {
                Text(signInErrorMessage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(WorkoutTheme.mutedInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            #if DEBUG
            Button {
                Haptics.selection()
                signInErrorMessage = nil
                store.markAppleSignedIn()
                step = .consent
            } label: {
                FullWidthSecondaryLabel(title: "Appleログインなしで開発確認")
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private func appleSignInErrorMessage(for error: Error) -> String {
        if let authorizationError = error as? ASAuthorizationError {
            switch authorizationError.code {
            case .canceled:
                return "Appleログインがキャンセルされました。もう一度試すか、開発確認で進めます。"
            case .failed:
                return "Appleログインに失敗しました。SimulatorのApple ID状態、またはApple Developer側のCapabilityを確認してください。"
            case .invalidResponse:
                return "Appleから不正な応答が返りました。少し待って再試行してください。"
            case .notHandled:
                return "Appleログインが処理されませんでした。Simulatorでは開発確認で進めます。"
            case .unknown:
                return "Appleログインで不明なエラーが出ました。Simulatorでは開発確認で進めます。"
            case .notInteractive:
                return "対話式ログインを開始できませんでした。Simulatorを前面にして再試行してください。"
            case .preferSignInWithApple:
                return "この端末ではAppleログインが推奨されています。もう一度Appleログインを試してください。"
            case .deviceNotConfiguredForPasskeyCreation:
                return "端末側のパスキー設定が未完了です。Simulatorでは開発確認で進めます。"
            case .matchedExcludedCredential:
                return "このApple IDではログインを続行できませんでした。"
            case .credentialImport:
                return "認証情報の取り込みに失敗しました。"
            case .credentialExport:
                return "認証情報の書き出しに失敗しました。"
            @unknown default:
                return "Appleログインに失敗しました: \(error.localizedDescription)"
            }
        }

        return "Appleログインに失敗しました: \(error.localizedDescription)"
    }

    private var consentStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "データ取得の同意",
                subtitle: "身長・体重・ワークアウトログを使って、回数と期間を調整します。"
            )

            VStack(alignment: .leading, spacing: 12) {
                ConsentLine(text: "体重や目標体重から3つのプランを作る")
                ConsentLine(text: "Apple Visionの骨格ログを自動保存して精度改善に使う")
                ConsentLine(text: "ワークアウト完了時のカメラ映像をログに残す")
                ConsentLine(text: "同意しなくても、手動設定で続けられる")
            }
            .onboardingPanel()

            HStack(spacing: 12) {
                Button {
                    Haptics.selection()
                    store.setDataConsent(false)
                    step = .profile
                } label: {
                    FullWidthSecondaryLabel(title: "同意しない")
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    store.setDataConsent(true)
                    step = .profile
                } label: {
                    FullWidthPrimaryLabel(title: "同意する", systemImage: "checkmark")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "今の状態",
                subtitle: "ざっくりで大丈夫です。プランの初期回数を決めます。"
            )

            VStack(spacing: 18) {
                Picker("性別", selection: $store.userGender) {
                    ForEach(UserGender.allCases) { gender in
                        Text(gender.title).tag(gender)
                    }
                }
                .pickerStyle(.segmented)

                WheelNumberPickerRow(
                    title: "身長",
                    suffix: "cm",
                    value: $store.heightCm,
                    range: 120...220,
                    step: 1,
                    fractionDigits: 0
                )

                WheelNumberPickerRow(
                    title: "現在の体重",
                    suffix: "kg",
                    value: $store.currentWeightKg,
                    range: 35...160,
                    step: 0.5,
                    fractionDigits: 1
                )
            }
            .onboardingPanel()

            Button {
                Haptics.selection()
                step = .goal
            } label: {
                FullWidthPrimaryLabel(title: "次へ", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "目標",
                subtitle: "目標体重と続ける期間から、回数と増加ペースを逆算します。"
            )

            VStack(spacing: 18) {
                WheelNumberPickerRow(
                    title: "目標体重",
                    suffix: "kg",
                    value: $store.goalWeightKg,
                    range: 35...160,
                    step: 0.5,
                    fractionDigits: 1
                )

                HStack {
                    Text("差分")
                    Spacer()
                    Text("\(abs(store.currentWeightKg - store.goalWeightKg), specifier: "%.1f")kg")
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                }

                Stepper(value: $store.goalDurationMonths, in: 1...12) {
                    HStack {
                        Text("続ける期間")
                        Spacer()
                        Text("\(store.goalDurationMonths)ヶ月")
                            .font(.title2.weight(.black))
                            .monospacedDigit()
                    }
                }
                .font(.headline.weight(.black))
            }
            .onboardingPanel()

            Button {
                Haptics.mediumTap()
                generatePlan()
            } label: {
                FullWidthPrimaryLabel(title: "予測してプラン作成", systemImage: "sparkles")
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPlan)

            if isGeneratingPlan {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.black)
                    Text("継続率と負荷を予測中")
                        .font(.headline.weight(.black))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onboardingPanel()
            }
        }
    }

    private func generatePlan() {
        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true

        Task {
            try? await Task.sleep(for: .milliseconds(1100))
            await MainActor.run {
                store.refreshPlanOptions()
                isGeneratingPlan = false
                Haptics.success()
                step = .plan
            }
        }
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "3つのプラン",
                subtitle: "目標期間に合わせて、継続重視・目標ペース・強制力高めを出しています。"
            )

            ForEach(store.planOptions) { plan in
                Button {
                    Haptics.mediumTap()
                    store.selectPlan(plan)
                    store.appBlockingEnabled = true
                    step = .commitmentBlock
                } label: {
                    PlanOptionCard(plan: plan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var commitmentBlockStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "自分に縛りをつけましょう",
                subtitle: "全てのアプリをブロックすることで筋トレから逃れられなくできます💪"
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 38, weight: .black))
                        .frame(width: 62, height: 62)
                        .foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("アプリブロック")
                            .font(.title2.weight(.black))
                        Text(store.appBlockingEnabled ? "オン" : "オフ")
                            .font(.headline.weight(.black))
                            .foregroundStyle(store.appBlockingEnabled ? .black : WorkoutTheme.mutedInk)
                    }

                    Spacer()

                    Toggle("", isOn: $store.appBlockingEnabled)
                        .labelsHidden()
                }

                SettingsLineLike(
                    title: "ロック状態",
                    value: shielding.readinessText(isEnabled: store.appBlockingEnabled)
                )

                Button {
                    Haptics.selection()
                    Task {
                        await shielding.requestAuthorization()
                        showBlockPicker = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("ブロック対象を選ぶ", systemImage: "app.badge")
                                .font(.headline.weight(.black))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.black))
                        }

                        Text(shielding.selectionSummary)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.black)

                        Text("SNS・動画・ブラウザなど、逃げ道になるアプリをまとめて選べます。")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.black.opacity(0.18), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    Task {
                        await shielding.requestAuthorization()
                    }
                } label: {
                    HStack {
                        Label("Screen Time権限を確認", systemImage: "checkmark.shield")
                            .font(.subheadline.weight(.black))
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.black))
                            .foregroundStyle(WorkoutTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(shielding.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutTheme.mutedInk)
            }
            .onboardingPanel()

            Button {
                Haptics.selection()
                step = .commitmentTrigger
            } label: {
                FullWidthPrimaryLabel(title: "次へ", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var commitmentTriggerStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "いつ・どこでやる？",
                subtitle: "時間帯を選んで、実際にやる場所を登録します。場所は複数追加できます。"
            )

            triggerSetupPanel

            Button {
                Haptics.selection()
                step = .tutorialIntro
            } label: {
                FullWidthPrimaryLabel(title: "チュートリアルへ", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var tutorialIntroStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "最初の5回",
                subtitle: "カメラを置いて全身が入る距離まで離れたら、まず5回だけやります。"
            )

            if let plan = store.selectedPlan {
                Text("今のあなた。\(plan.durationMonths)ヶ月後に見返して、達成感を味わおう。")
                    .font(.headline.weight(.black))
                    .foregroundStyle(WorkoutTheme.mutedInk)
            }

            Button {
                Haptics.mediumTap()
                nextStepAfterTutorial = .trigger
                showTutorial = true
                Task { @MainActor in
                    shielding.applyShielding(isEnabled: store.appBlockingEnabled)
                }
            } label: {
                FullWidthPrimaryLabel(title: "チュートリアル開始", systemImage: "play.fill", minHeight: 72)
            }
            .buttonStyle(.plain)
        }
    }

    private var triggerSetupPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("時間帯", selection: $store.workoutTimeBand) {
                    ForEach(WorkoutTimeBand.allCases) { band in
                        Text(band.title).tag(band)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.workoutTimeBand) { _, _ in
                    Haptics.selection()
                }

                Text(store.workoutTimeBand.subtitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutTheme.mutedInk)

                Stepper("ここに着いてから \(locationDelayMinutes)分後", value: $locationDelayMinutes, in: 10...60, step: 5)
                    .font(.headline.weight(.black))

                Picker("場所名", selection: $locationKind) {
                    ForEach(TriggerLocationKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button {
                        Haptics.selection()
                        store.triggerPreference = .homeArrival
                        locationTrigger.requestLocation(kind: locationKind, delayMinutes: locationDelayMinutes)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "location.fill")
                                .font(.title3.weight(.black))
                            Text("ここでやる")
                                .font(.caption.weight(.black))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .tint(.black)

                    Button {
                        Haptics.selection()
                        showMapPicker = true
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "map.fill")
                                .font(.title3.weight(.black))
                            Text("地図から選ぶ")
                                .font(.caption.weight(.black))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .tint(.black)
                }

                if store.triggerLocations.isEmpty {
                    Text(locationTrigger.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WorkoutTheme.mutedInk)
                } else {
                    ForEach(store.triggerLocations) { location in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(location.triggerSummary)
                                    .font(.subheadline.weight(.black))
                                Text(location.shortLabel)
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(WorkoutTheme.mutedInk)
                            }
                            Spacer()
                            Button {
                                Haptics.lightTap()
                                store.removeTriggerLocation(location)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text("その日1回やったら、その日はもう発動しません。")
                    .font(.caption.weight(.black))
                    .foregroundStyle(WorkoutTheme.mutedInk)
            }
            .onboardingPanel()
        }
    }

    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "設定完了",
                subtitle: "チュートリアルは完了です。明日から同じ条件でロックをかけます。"
            )

            VStack(alignment: .leading, spacing: 18) {
                SettingsLineLike(title: "トリガー", value: store.triggerPreference.title)
                if store.triggerPreference == .time || store.triggerPreference == .both {
                    SettingsLineLike(title: "開始時刻", value: store.alarmTime.formatted(date: .omitted, time: .shortened))
                }
                if store.triggerPreference == .homeArrival {
                    SettingsLineLike(title: "開始条件", value: store.homeTriggerLabel ?? "帰宅後")
                }
                SettingsLineLike(title: "登録場所", value: store.triggerLocations.isEmpty ? "未設定" : "\(store.triggerLocations.count)件")
                SettingsLineLike(title: "アプリブロック", value: store.appBlockingEnabled ? "オン" : "オフ")
                SettingsLineLike(title: "ロック状態", value: shielding.readinessText(isEnabled: store.appBlockingEnabled))
                SettingsLineLike(title: "ブロック対象", value: shielding.selectionSummary)

                ForEach(store.triggerLocations) { location in
                    SettingsLineLike(title: location.kind.title, value: location.triggerSummary)
                }

                Text(shielding.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutTheme.mutedInk)
            }
            .onboardingPanel()

            Button {
                Haptics.success()
                store.appBlockingEnabled = true
                shielding.applyShielding(isEnabled: false)
                Task { await store.scheduleDailyAlarm() }
                store.completeOnboarding()
            } label: {
                FullWidthPrimaryLabel(title: "設定完了", systemImage: "checkmark")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FullWidthPrimaryLabel: View {
    let title: String
    let systemImage: String
    var minHeight: CGFloat = 64

    var body: some View {
        HStack {
            Spacer()
            Label(title, systemImage: systemImage)
                .font(.system(size: 22, weight: .black, design: .rounded))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct FullWidthSecondaryLabel: View {
    let title: String
    var minHeight: CGFloat = 64

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.headline.weight(.black))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .padding(.horizontal, 16)
        .foregroundStyle(.black)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black, lineWidth: 3)
        )
        .contentShape(Rectangle())
    }
}

private struct LocationMapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: TriggerLocationKind
    let delayMinutes: Int
    let onSelect: (HomeLocation) -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var selectedName: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition)
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onMapCameraChange { context in
                        centerCoordinate = context.camera.centerCoordinate
                    }
                    .ignoresSafeArea(edges: .bottom)

                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(WorkoutTheme.orange)
                    .shadow(radius: 2)

                VStack {
                    searchPanel
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Spacer()

                    Button {
                        let location = HomeLocation(
                            name: selectedName ?? kind.title,
                            kind: kind,
                            latitude: centerCoordinate.latitude,
                            longitude: centerCoordinate.longitude,
                            startDelayMinutes: delayMinutes
                        )
                        onSelect(location)
                        Haptics.success()
                        dismiss()
                    } label: {
                        FullWidthPrimaryLabel(title: "地図の中心を登録", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
            }
            .navigationTitle("場所を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.black.opacity(0.5))

                TextField("場所を検索", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        searchPlaces()
                    }

                if isSearching {
                    ProgressView()
                        .tint(.black)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        selectedName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.headline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))

            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.prefix(5).enumerated()), id: \.offset) { _, item in
                        Button {
                            selectSearchResult(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "名称なし")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(.black)
                                Text(item.placemark.title ?? "")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WorkoutTheme.mutedInk)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item != searchResults.prefix(5).last {
                            Divider()
                        }
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func searchPlaces() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )

        Task {
            do {
                let response = try await MKLocalSearch(request: request).start()
                await MainActor.run {
                    searchResults = response.mapItems
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selectedName = item.name ?? kind.title
        centerCoordinate = coordinate
        searchText = item.name ?? searchText
        searchResults = []
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        Haptics.selection()
    }
}

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(subtitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(WorkoutTheme.mutedInk)
        }
    }
}

private struct ConsentLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
        }
        .font(.subheadline.weight(.bold))
    }
}

private struct TutorialLine: View {
    let index: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(index)
                .font(.headline.monospacedDigit().weight(.black))
                .frame(width: 34, height: 34)
                .foregroundStyle(.white)
                .background(.black, in: Circle())
            Text(text)
                .font(.headline.weight(.bold))
        }
    }
}

private struct SettingsLineLike: View {
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

private struct WheelNumberPickerRow: View {
    let title: String
    let suffix: String
    @Binding var value: Double
    let range: ClosedRange<Int>
    let step: Double
    let fractionDigits: Int

    private var scale: Int {
        max(1, Int((1 / step).rounded()))
    }

    private var lowerUnit: Int {
        Int((Double(range.lowerBound) * Double(scale)).rounded())
    }

    private var upperUnit: Int {
        Int((Double(range.upperBound) * Double(scale)).rounded())
    }

    private var selection: Binding<Int> {
        Binding(
            get: {
                min(max(Int((value * Double(scale)).rounded()), lowerUnit), upperUnit)
            },
            set: { unitValue in
                value = Double(unitValue) / Double(scale)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline.weight(.black))
                Spacer()
                Text(displayText(for: value))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(suffix)
                    .font(.headline.weight(.black))
                    .foregroundStyle(WorkoutTheme.mutedInk)
            }

            Picker(title, selection: selection) {
                ForEach(Array(stride(from: lowerUnit, through: upperUnit, by: 1)), id: \.self) { unitValue in
                    Text(displayText(for: Double(unitValue) / Double(scale)))
                        .font(.headline.weight(.black))
                        .tag(unitValue)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .clipped()
            .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(Text(title))
            .onChange(of: value) { _, _ in
                Haptics.selection()
            }
        }
    }

    private func displayText(for number: Double) -> String {
        if fractionDigits == 0 {
            return "\(Int(number.rounded()))"
        }

        return number.formatted(.number.precision(.fractionLength(fractionDigits)))
    }
}

private struct PlanOptionCard: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.title)
                    .font(.title2.weight(.black))
                Spacer()
                Text("\(plan.durationWeeks)週")
                    .font(.headline.monospacedDigit().weight(.black))
            }

            Text(plan.stance)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))

            HStack {
                PlanMetric(value: "\(plan.startReps)", label: "初日")
                PlanMetric(value: "\(plan.endReps)", label: "最終")
                PlanMetric(value: "+\(plan.weeklyIncrease)", label: "毎週")
            }

            HStack {
                PlanMetric(value: "\(plan.predictedAdherence)%", label: "継続予測")
                PlanMetric(value: "\(plan.loadScore)", label: "負荷")
                PlanMetric(value: "\(plan.dailySessions)", label: "回/日")
            }

            Text(plan.rationale)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.64))
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlanMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title.weight(.black))
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func onboardingPanel() -> some View {
        workoutPanelSurface()
    }

}
