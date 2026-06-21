import SwiftUI
import UIKit

enum WorkoutTheme {
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let background = adaptive(light: "#F7ECDD", dark: "#1B1613")
    static let inkPrimary = adaptive(light: "#33231A", dark: "#F2E8DC")
    static let inkSecondary = adaptive(light: "#6E5A49", dark: "#B6A48F")
    static let accent = adaptive(light: "#EE7E2E", dark: "#FF9A4D")
    static let deepAccent = adaptive(light: "#D9631A", dark: "#F07A28")
    static let accentInk = Color(red: 0.20, green: 0.14, blue: 0.10)
    static let orange = accent
    static let deepOrange = deepAccent
    static let ink = inkPrimary
    static let panel = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let mutedInk = inkSecondary
    static let line = inkSecondary.opacity(0.28)

    private static func uiColor(hex: String) -> UIColor {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return .clear
        }

        return UIColor(
            red: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct AppView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--progress") ? 1 : 0

    var body: some View {
        Group {
            if store.onboardingCompleted || ProcessInfo.processInfo.arguments.contains("--skip-onboarding") {
                mainTabs
            } else {
                OnboardingFlowView()
            }
        }
        .onAppear {
            store.syncTargetRepsWithPlan()
            resumeWorkoutSessionLockIfNeeded()
            store.resumePendingShieldingIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.syncTargetRepsWithPlan()
                resumeWorkoutSessionLockIfNeeded()
                store.applyDueShieldingIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutStartRequested)) { _ in
            selectedTab = 0
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("今日", systemImage: "checkmark.seal")
            }
            .tag(0)

            NavigationStack {
                ProgressBoardView()
            }
            .tabItem {
                Label("ログ", systemImage: "rectangle.stack")
            }
            .tag(1)

            NavigationStack {
                ScheduleView()
            }
            .tabItem {
                Label("予定", systemImage: "alarm")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
            .tag(3)
        }
        .tint(WorkoutTheme.accent)
    }

    private func resumeWorkoutSessionLockIfNeeded() {
        ScreenShieldingService.reapplyWorkoutSessionLockIfActive()
        guard ScreenShieldingService.isWorkoutSessionLockActive else { return }
        selectedTab = 0
        NotificationCenter.default.post(name: .workoutStartRequested, object: nil)
    }
}

extension View {
    @ViewBuilder
    func workoutPanelSurface(padding amount: CGFloat = 20, cornerRadius: CGFloat = 8) -> some View {
        self
            .padding(amount)
    }
}
