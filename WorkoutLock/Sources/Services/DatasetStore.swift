import Foundation

@MainActor
final class DatasetStore: ObservableObject {
    @Published private(set) var files: [DatasetFile] = []
    @Published var statusText = "まだ収録データはありません"

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        reload()
    }

    var directoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("WorkoutLockTrainingData", isDirectory: true)
    }

    func save(recording: DatasetRecording) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let filename = makeFilename(for: recording.metadata)
            let url = directoryURL.appendingPathComponent(filename)
            let data = try encoder.encode(recording)
            try data.write(to: url, options: [.atomic])
            statusText = "保存しました: \(filename)"
            Haptics.success()
            reload()
        } catch {
            statusText = "保存に失敗しました: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }

            files = urls
                .map { url in
                    let recording = readRecording(from: url)
                    return DatasetFile(
                        url: url,
                        metadata: recording?.metadata,
                        estimatedReps: recording.map(estimatedReps(in:)) ?? 0
                    )
                }
                .sorted { lhs, rhs in
                    let leftDate = lhs.metadata?.createdAt ?? .distantPast
                    let rightDate = rhs.metadata?.createdAt ?? .distantPast
                    return leftDate > rightDate
                }

            statusText = files.isEmpty ? "まだ収録データはありません" : "\(files.count)件の収録データ"
        } catch {
            statusText = "読み込みに失敗しました: \(error.localizedDescription)"
            files = []
        }
    }

    func delete(_ file: DatasetFile) {
        do {
            try FileManager.default.removeItem(at: file.url)
            statusText = "削除しました"
            Haptics.lightTap()
            reload()
        } catch {
            statusText = "削除に失敗しました: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    func totalEstimatedReps(
        exercise: DatasetExerciseKind? = nil,
        label: DatasetRepLabel? = nil,
        angle: DatasetCameraAngle? = nil
    ) -> Int {
        files.reduce(0) { total, file in
            guard let metadata = file.metadata else { return total }
            if let exercise, metadata.exercise != exercise { return total }
            if let label, metadata.label != label { return total }
            if let angle, metadata.cameraAngle != angle { return total }
            return total + file.estimatedReps
        }
    }

    private func readRecording(from url: URL) -> DatasetRecording? {
        guard
            let data = try? Data(contentsOf: url),
            let recording = try? decoder.decode(DatasetRecording.self, from: data)
        else {
            return nil
        }

        return recording
    }

    private func estimatedReps(in recording: DatasetRecording) -> Int {
        recording.samples.map(\.repCount).max() ?? 0
    }

    private func makeFilename(for metadata: DatasetRecordingMetadata) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let datePart = formatter.string(from: metadata.createdAt)
        let participant = metadata.participantCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let safeParticipant = participant.isEmpty ? "participant" : participant
        return "\(datePart)_\(safeParticipant)_\(metadata.exercise.rawValue)_\(metadata.label.rawValue).json"
    }
}
