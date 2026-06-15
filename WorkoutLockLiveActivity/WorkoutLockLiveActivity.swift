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
                    Text("\(context.state.targetReps)回")
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.triggerLabel)
                            .font(.caption.weight(.bold))
                        Text(timerInterval: Date()...context.state.startAt, countsDown: true)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.startAt, countsDown: true)
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
                    .frame(width: 42)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            }
        }
    }
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
                Text(context.state.message)
                    .font(.headline.weight(.black))
                Text("\(context.attributes.exerciseTitle) \(context.state.targetReps)回")
                    .font(.subheadline.weight(.bold))
                Text(context.state.triggerLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.62))
            }

            Spacer()

            Text(timerInterval: Date()...context.state.startAt, countsDown: true)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .padding(16)
    }
}
