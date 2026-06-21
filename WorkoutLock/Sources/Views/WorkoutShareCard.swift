import SwiftUI
import UIKit

/// SNS共有用の縦長カード。記録1件＋連続日数をビジュアル化する。
struct WorkoutShareCard: View {
    let record: WorkoutRecord
    let streakDays: Int
    let totalReps: Int

    private let shareAccent = Color(red: 1, green: 0.55, blue: 0.16)
    private let shareDeepAccent = Color(red: 0.92, green: 0.38, blue: 0.05)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 18) {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 18, weight: .black))
                    Text("筋トレロック")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                }
                .foregroundStyle(shareAccent)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(record.actualReps)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("回 達成")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .padding(.bottom, 10)
                }
                .foregroundStyle(.white)

                HStack(spacing: 10) {
                    ShareStat(icon: "flame.fill", text: "\(streakDays)日連続")
                    ShareStat(icon: "figure.strengthtraining.traditional", text: record.exercise.title)
                    ShareStat(icon: "sum", text: "累計\(totalReps)回")
                }

                Text("#筋トレロック でロック解除")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(28)
        }
        .frame(width: 360, height: 480)
        .background(WorkoutTheme.panel)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let data = record.snapshotData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 360, height: 480)
                .clipped()
        } else {
            LinearGradient(
                colors: [shareAccent, shareDeepAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct ShareStat: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
            Text(text)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.16), in: Capsule())
    }
}

enum WorkoutShareImageRenderer {
    /// シェアカードをPNG画像化し、共有可能な一時ファイルURLを返す。
    @MainActor
    static func makeImageURL(record: WorkoutRecord, streakDays: Int, totalReps: Int) -> URL? {
        let card = WorkoutShareCard(record: record, streakDays: streakDays, totalReps: totalReps)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3

        guard
            let uiImage = renderer.uiImage,
            let data = uiImage.pngData()
        else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workoutlock-share-\(record.id.uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
