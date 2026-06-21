import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WorkoutLockLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLockLiveActivity()
    }
}

struct WorkoutLockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 1, green: 0.55, blue: 0.16))
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.exerciseTitle, systemImage: "figure.strengthtraining.traditional")
                        .font(.caption.weight(.black))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isComplete ? "OPEN" : "\(context.state.currentSet)/\(context.state.totalSets)セット")
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.isComplete ? "達成！ロック解除" : "今のセット")
                            .font(.caption.weight(.bold))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(context.state.currentReps)")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .monospacedDigit()
                            Text("/ \(context.state.targetReps) 回")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.orange)
                        }
                        ProgressView(value: progress(context.state))
                            .tint(.orange)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.isComplete ? "OPEN" : "\(context.state.currentReps)/\(context.state.targetReps)")
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
                    .frame(width: 48)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private func progress(_ state: WorkoutLiveActivityAttributes.ContentState) -> Double {
    guard state.targetReps > 0 else { return state.isComplete ? 1 : 0 }
    return min(1, Double(state.currentReps) / Double(state.targetReps))
}

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34, weight: .black))
                .frame(width: 52, height: 52)
                .background(.black, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.isComplete ? "達成！ロック解除" : "\(context.attributes.exerciseTitle) \(context.state.currentSet)/\(context.state.totalSets)セット")
                    .font(.headline.weight(.black))
                Text("\(context.state.currentReps) / \(context.state.targetReps) 回")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }

            Spacer()

            Text(context.state.isComplete ? "OPEN" : "\(Int(progress(context.state) * 100))%")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .padding(16)
    }
}
