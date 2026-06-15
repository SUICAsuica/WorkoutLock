import Foundation

enum DatasetExerciseKind: String, CaseIterable, Codable, Identifiable {
    case squat
    case jumpingJack
    case lunge
    case plank
    case pushup
    case crunch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squat:
            return "スクワット"
        case .jumpingJack:
            return "ジャンピングジャック"
        case .lunge:
            return "ランジ"
        case .plank:
            return "プランク"
        case .pushup:
            return "腕立て"
        case .crunch:
            return "クランチ"
        }
    }
}

enum DatasetRepLabel: String, CaseIterable, Codable, Identifiable {
    case good
    case shallow
    case badForm
    case partial
    case outOfFrame
    case noPerson
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good:
            return "成功"
        case .shallow:
            return "浅い"
        case .badForm:
            return "フォーム崩れ"
        case .partial:
            return "途中"
        case .outOfFrame:
            return "画角外"
        case .noPerson:
            return "人物なし"
        case .other:
            return "その他"
        }
    }
}

enum DatasetCameraAngle: String, CaseIterable, Codable, Identifiable {
    case front
    case diagonal
    case side
    case low
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front:
            return "正面"
        case .diagonal:
            return "斜め"
        case .side:
            return "横"
        case .low:
            return "低い位置"
        case .unknown:
            return "未指定"
        }
    }
}

struct DatasetJointSample: Codable {
    let joint: String
    let x: Double
    let y: Double
    let confidence: Float
}

struct DatasetPoseSample: Codable, Identifiable {
    let id: UUID
    let elapsedSeconds: TimeInterval
    let recordedAt: Date
    let repCount: Int
    let phase: String
    let guidance: String
    let kneeAngle: Double?
    let joints: [DatasetJointSample]
}

struct DatasetRecordingMetadata: Codable, Identifiable {
    let id: UUID
    let appSchemaVersion: Int
    let createdAt: Date
    let participantCode: String
    let exercise: DatasetExerciseKind
    let label: DatasetRepLabel
    let cameraAngle: DatasetCameraAngle
    let phonePlacement: String
    let environmentNote: String
    let freeNote: String
    let sampleCount: Int
    let duration: TimeInterval
}

struct DatasetRecording: Codable, Identifiable {
    let metadata: DatasetRecordingMetadata
    let samples: [DatasetPoseSample]

    var id: UUID { metadata.id }
}

struct DatasetFile: Identifiable {
    let id = UUID()
    let url: URL
    let metadata: DatasetRecordingMetadata?
    let estimatedReps: Int

    var title: String {
        if let metadata {
            return "\(metadata.exercise.title) / \(metadata.label.title)"
        }
        return url.deletingPathExtension().lastPathComponent
    }

    var subtitle: String {
        guard let metadata else {
            return url.lastPathComponent
        }

        let duration = Int(metadata.duration)
        return "\(metadata.createdAt.formatted(date: .numeric, time: .shortened)) / \(estimatedReps) rep / \(metadata.sampleCount) samples / \(duration)s"
    }
}
