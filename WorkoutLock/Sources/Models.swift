import CoreGraphics
import Foundation

enum ExerciseKind: String, CaseIterable, Codable, Identifiable {
    case squat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squat:
            return "スクワット"
        }
    }

    var systemImage: String {
        switch self {
        case .squat:
            return "figure.strengthtraining.traditional"
        }
    }

    var setupHint: String {
        switch self {
        case .squat:
            return "iPhoneを床から少し高い位置に置いて、全身が画面に入る距離まで下がってください。"
        }
    }
}

enum RepPhase: String {
    case ready
    case standing
    case lowered
    case complete
}

enum CameraStatus: Equatable {
    case idle
    case requestingAccess
    case running
    case denied
    case unavailable(String)

    var title: String {
        switch self {
        case .idle:
            return "待機中"
        case .requestingAccess:
            return "カメラ確認中"
        case .running:
            return "判定中"
        case .denied:
            return "カメラ権限がありません"
        case .unavailable:
            return "カメラが使えません"
        }
    }
}

enum BodyJoint: String, CaseIterable {
    case nose
    case neck
    case root
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

struct PosePoint: Identifiable {
    let id: BodyJoint
    let location: CGPoint
    let confidence: Float
}

struct PoseFrame {
    var points: [PosePoint]
    var repCount: Int
    var phase: RepPhase
    var guidance: String
    var kneeAngle: Double?
    var sourceAspectRatio: CGFloat = 9.0 / 16.0

    static let empty = PoseFrame(
        points: [],
        repCount: 0,
        phase: .ready,
        guidance: "画面のもちトレをスクワットさせよう",
        kneeAngle: nil
    )

    static func noPerson(count: Int, sourceAspectRatio: CGFloat = 9.0 / 16.0) -> PoseFrame {
        PoseFrame(
            points: [],
            repCount: count,
            phase: .ready,
            guidance: "全身を入れてもちトレを出そう",
            kneeAngle: nil,
            sourceAspectRatio: sourceAspectRatio
        )
    }

    func point(_ joint: BodyJoint) -> PosePoint? {
        points.first { $0.id == joint }
    }
}

struct WorkoutRecord: Codable, Identifiable {
    let id: UUID
    let completedAt: Date
    let exercise: ExerciseKind
    let targetReps: Int
    let actualReps: Int
    let duration: TimeInterval
    let snapshotData: Data?

    init(
        id: UUID = UUID(),
        completedAt: Date = .now,
        exercise: ExerciseKind,
        targetReps: Int,
        actualReps: Int,
        duration: TimeInterval,
        snapshotData: Data? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.exercise = exercise
        self.targetReps = targetReps
        self.actualReps = actualReps
        self.duration = duration
        self.snapshotData = snapshotData
    }
}

struct WeightCheckIn: Codable, Identifiable {
    let id: UUID
    let loggedAt: Date
    let weightKg: Double
    let previousWeightKg: Double
    let targetRepsBefore: Int
    let targetRepsAfter: Int
    let planTitle: String?

    init(
        id: UUID = UUID(),
        loggedAt: Date = .now,
        weightKg: Double,
        previousWeightKg: Double,
        targetRepsBefore: Int,
        targetRepsAfter: Int,
        planTitle: String?
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.weightKg = weightKg
        self.previousWeightKg = previousWeightKg
        self.targetRepsBefore = targetRepsBefore
        self.targetRepsAfter = targetRepsAfter
        self.planTitle = planTitle
    }
}

struct DailyRepBar: Identifiable {
    let date: Date
    let reps: Int

    var id: Date { date }

    /// 曜日1文字（月・火…）。
    var weekdaySymbol: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

struct TutorialCalibration: Codable, Equatable {
    let completedAt: Date
    let targetReps: Int
    let actualReps: Int
    let duration: TimeInterval
    let sampleCount: Int
    let visibleSampleRatio: Double
    let averageTrackedJoints: Double
    let averageKneeAngle: Double?
    let lowestKneeAngle: Double?
    let standingKneeAngle: Double?

    var secondsPerRep: Double {
        guard actualReps > 0 else { return duration }
        return duration / Double(actualReps)
    }

    var qualityScore: Int {
        let visibility = min(1, max(0, visibleSampleRatio))
        let jointCoverage = min(1, max(0, averageTrackedJoints / Double(BodyJoint.allCases.count)))
        let score = (visibility * 55) + (jointCoverage * 45)
        return Int(score.rounded())
    }

    var poseCalibration: PoseCalibration? {
        guard
            let lowestKneeAngle,
            let standingKneeAngle,
            standingKneeAngle > lowestKneeAngle
        else {
            return nil
        }

        let range = standingKneeAngle - lowestKneeAngle
        guard range >= 28 else { return nil }

        return PoseCalibration(
            loweredThreshold: min(132, max(92, lowestKneeAngle + range * 0.36)),
            standingThreshold: min(174, max(142, standingKneeAngle - range * 0.18))
        )
    }
}

struct PoseCalibration: Codable, Equatable {
    let loweredThreshold: Double
    let standingThreshold: Double
}

enum UserGender: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case noAnswer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:
            return "男性"
        case .female:
            return "女性"
        case .noAnswer:
            return "回答しない"
        }
    }
}

enum TriggerPreference: String, Codable, CaseIterable, Identifiable {
    case time
    case homeArrival
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time:
            return "時刻で開始"
        case .homeArrival:
            return "帰宅後すぐ"
        case .both:
            return "時刻 + 帰宅"
        }
    }

    var subtitle: String {
        switch self {
        case .time:
            return "毎日決めた時間にトリガー"
        case .homeArrival:
            return "家に着いたタイミングでトリガー"
        case .both:
            return "逃げ道を減らす強め設定"
        }
    }
}

enum WorkoutTimeBand: String, Codable, CaseIterable, Identifiable {
    case morning
    case noon
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:
            return "朝"
        case .noon:
            return "昼"
        case .evening:
            return "夕方以降"
        }
    }

    var defaultHour: Int {
        switch self {
        case .morning:
            return 8
        case .noon:
            return 12
        case .evening:
            return 21
        }
    }

    var subtitle: String {
        switch self {
        case .morning:
            return "起きてから先に終わらせる"
        case .noon:
            return "昼の区切りでやる"
        case .evening:
            return "帰ってから・寝る前にやる"
        }
    }
}

enum WorkoutMusicTrack: String, Codable, CaseIterable, Identifiable {
    case sunoSlot01
    case sunoSlot02
    case sunoSlot03
    case neonDrive
    case midnightRunner
    case kawaiiRep
    case heavyLock
    case cityPopJump
    case finalSprint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunoSlot01:
            return "Clean Neon Drive"
        case .sunoSlot02:
            return "Clean Rain Alley"
        case .sunoSlot03:
            return "Clean Midnight Gearshift"
        case .neonDrive:
            return "Neon Drive"
        case .midnightRunner:
            return "Midnight Runner"
        case .kawaiiRep:
            return "Kawaii Rep"
        case .heavyLock:
            return "Heavy Lock"
        case .cityPopJump:
            return "City Pop Jump"
        case .finalSprint:
            return "Final Sprint"
        }
    }

    var subtitle: String {
        switch self {
        case .sunoSlot01:
            return "Suno実音源 / ネオン系シンセ"
        case .sunoSlot02:
            return "Suno実音源 / ダークな映画系"
        case .sunoSlot03:
            return "Suno実音源 / 夜ドライブ系"
        case .neonDrive:
            return "ネオン系シンセでテンポよく"
        case .midnightRunner:
            return "暗めの映画っぽい集中ループ"
        case .kawaiiRep:
            return "軽くて可愛いチップ系"
        case .heavyLock:
            return "強めのロック解除用ビート"
        case .cityPopJump:
            return "明るめの跳ねるシティポップ"
        case .finalSprint:
            return "最後に追い込む高速ループ"
        }
    }

    var resourceName: String {
        switch self {
        case .sunoSlot01:
            return "suno_slot_01"
        case .sunoSlot02:
            return "suno_slot_02"
        case .sunoSlot03:
            return "suno_slot_03"
        case .neonDrive:
            return "music_neon_drive"
        case .midnightRunner:
            return "music_midnight_runner"
        case .kawaiiRep:
            return "music_kawaii_rep"
        case .heavyLock:
            return "music_heavy_lock"
        case .cityPopJump:
            return "music_city_pop_jump"
        case .finalSprint:
            return "music_final_sprint"
        }
    }

    var resourceExtension: String {
        "wav"
    }

    func bundledURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Music"
        ) ?? bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension
        )
    }

    static var randomPool: [WorkoutMusicTrack] {
        [.sunoSlot01, .sunoSlot02, .sunoSlot03]
    }

    static var lastWorkoutTrackDefaultsKey: String {
        "workout-lock.last-workout-track"
    }

    static func availableRandomPool(in bundle: Bundle = .main) -> [WorkoutMusicTrack] {
        randomPool.filter { $0.bundledURL(in: bundle) != nil }
    }

    static func randomWorkoutTrack(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        fallback: WorkoutMusicTrack
    ) -> WorkoutMusicTrack {
        let availableTracks = availableRandomPool(in: bundle)
        let pool: [WorkoutMusicTrack]
        if availableTracks.isEmpty, fallback.bundledURL(in: bundle) != nil {
            pool = [fallback]
        } else if availableTracks.isEmpty {
            pool = randomPool
        } else {
            pool = availableTracks
        }
        let lastTrack = defaults.string(forKey: lastWorkoutTrackDefaultsKey).flatMap { WorkoutMusicTrack(rawValue: $0) }
        let candidates = pool.count > 1 ? pool.filter { $0 != lastTrack } : pool
        return candidates.randomElement() ?? pool.randomElement() ?? fallback
    }

    static func saveLastWorkoutTrack(_ track: WorkoutMusicTrack, defaults: UserDefaults = .standard) {
        defaults.set(track.rawValue, forKey: lastWorkoutTrackDefaultsKey)
    }
}

struct TrainingPlan: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let stance: String
    let durationWeeks: Int
    let startReps: Int
    let endReps: Int
    let weeklyIncrease: Int
    let dailySessions: Int
    let loadScore: Int
    let predictedAdherence: Int
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case stance
        case durationWeeks
        case startReps
        case endReps
        case weeklyIncrease
        case dailySessions
        case loadScore
        case predictedAdherence
        case rationale
    }

    init(
        id: String,
        title: String,
        stance: String,
        durationWeeks: Int,
        startReps: Int,
        endReps: Int,
        weeklyIncrease: Int,
        dailySessions: Int,
        loadScore: Int = 50,
        predictedAdherence: Int = 70,
        rationale: String = "入力されたプロフィールから回数と期間を調整しました。"
    ) {
        self.id = id
        self.title = title
        self.stance = stance
        self.durationWeeks = durationWeeks
        self.startReps = startReps
        self.endReps = endReps
        self.weeklyIncrease = weeklyIncrease
        self.dailySessions = dailySessions
        self.loadScore = loadScore
        self.predictedAdherence = predictedAdherence
        self.rationale = rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        stance = try container.decode(String.self, forKey: .stance)
        durationWeeks = try container.decode(Int.self, forKey: .durationWeeks)
        startReps = try container.decode(Int.self, forKey: .startReps)
        endReps = try container.decode(Int.self, forKey: .endReps)
        weeklyIncrease = try container.decode(Int.self, forKey: .weeklyIncrease)
        dailySessions = try container.decode(Int.self, forKey: .dailySessions)
        loadScore = try container.decodeIfPresent(Int.self, forKey: .loadScore) ?? 50
        predictedAdherence = try container.decodeIfPresent(Int.self, forKey: .predictedAdherence) ?? 70
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? "入力されたプロフィールから回数と期間を調整しました。"
    }

    var durationMonths: Int {
        max(1, Int((Double(durationWeeks) / 4.0).rounded()))
    }

    var summary: String {
        "\(durationWeeks)週間 / \(startReps)回から\(endReps)回へ / 毎週+\(weeklyIncrease)回"
    }
}

enum TriggerLocationKind: String, Codable, CaseIterable, Identifiable {
    case home
    case office
    case school
    case gym
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "家"
        case .office:
            return "オフィス"
        case .school:
            return "学校"
        case .gym:
            return "ジム"
        case .other:
            return "その他"
        }
    }
}

struct HomeLocation: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let kind: TriggerLocationKind
    let latitude: Double
    let longitude: Double
    let capturedAt: Date
    let startDelayMinutes: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case latitude
        case longitude
        case capturedAt
        case startDelayMinutes
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: TriggerLocationKind,
        latitude: Double,
        longitude: Double,
        capturedAt: Date = .now,
        startDelayMinutes: Int = 10
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.capturedAt = capturedAt
        self.startDelayMinutes = startDelayMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) ?? .now
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(TriggerLocationKind.self, forKey: .kind) ?? .home
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? kind.title
        startDelayMinutes = try container.decodeIfPresent(Int.self, forKey: .startDelayMinutes) ?? 10
    }

    var shortLabel: String {
        "\(name) / \(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))"
    }

    var effectiveStartDelayMinutes: Int {
        max(10, startDelayMinutes)
    }

    var triggerSummary: String {
        "\(kind.title) 到着\(effectiveStartDelayMinutes)分後"
    }
}
