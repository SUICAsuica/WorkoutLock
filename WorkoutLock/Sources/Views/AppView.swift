import SwiftUI

enum WorkoutTheme {
    static let orange = Color(red: 1, green: 0.55, blue: 0.16)
    static let deepOrange = Color(red: 0.92, green: 0.38, blue: 0.05)
    static let ink = Color.black
    static let panel = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let mutedInk = Color.black.opacity(0.48)
    static let line = Color.black.opacity(0.22)
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
            store.resumePendingShieldingIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.syncTargetRepsWithPlan()
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
        .tint(.black)
    }
}

extension View {
    @ViewBuilder
    func workoutPanelSurface(padding amount: CGFloat = 20, cornerRadius: CGFloat = 8) -> some View {
        self
            .padding(amount)
    }
}
