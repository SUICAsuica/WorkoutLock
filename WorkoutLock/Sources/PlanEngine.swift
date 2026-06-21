import Foundation

enum FoodPreference: String, Codable, CaseIterable, Identifiable {
    case strict
    case balanced
    case loose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict:
            return "しっかり変える"
        case .balanced:
            return "バランス"
        case .loose:
            return "ゆるめ"
        }
    }

    var squatShareBase: Double {
        switch self {
        case .strict:
            return 0.12
        case .balanced:
            return 0.18
        case .loose:
            return 0.27
        }
    }
}

enum FitnessLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case normal
    case active
    case athlete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner:
            return "初心者"
        case .normal:
            return "普通"
        case .active:
            return "運動できる"
        case .athlete:
            return "かなり鍛えている"
        }
    }

    var met: Double {
        switch self {
        case .beginner:
            return 3.0
        case .normal:
            return 5.0
        case .active:
            return 5.0
        case .athlete:
            return 6.5
        }
    }

    var activityFactor: Double {
        switch self {
        case .beginner:
            return 1.4
        case .normal:
            return 1.55
        case .active:
            return 1.7
        case .athlete:
            return 1.8
        }
    }

    var recommendedTrainingDays: Int {
        switch self {
        case .beginner, .normal:
            return 3
        case .active, .athlete:
            return 4
        }
    }

    var startRatio: Double {
        switch self {
        case .beginner:
            return 0.40
        case .normal:
            return 0.30
        case .active:
            return 0.40
        case .athlete:
            return 0.45
        }
    }
}

enum KneeBackConcern: String, Codable, CaseIterable, Identifiable {
    case none
    case mild
    case present

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "なし"
        case .mild:
            return "少しある"
        case .present:
            return "ある"
        }
    }
}

enum DietLevel: Int, Codable, CaseIterable, Identifiable {
    case loose = 1
    case standard = 2
    case strong = 3
    case hard = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .loose:
            return "ゆるめ"
        case .standard:
            return "標準"
        case .strong:
            return "強め"
        case .hard:
            return "ハード"
        }
    }

    var foodRules: [String] {
        switch self {
        case .loose:
            return [
                "間食は1日1回まで",
                "夜食をやめる",
                "甘い飲み物は週2まで",
                "主食を少し減らす"
            ]
        case .standard:
            return [
                "ラーメンは週1まで",
                "飲みは週1・2杯まで",
                "夜の主食は小盛り",
                "タンパク質を毎食",
                "甘い飲み物なし"
            ]
        case .strong:
            return [
                "外食は週2まで",
                "揚げ物は週1まで",
                "夜の主食は半分",
                "間食は高タンパク",
                "酒は週1まで"
            ]
        case .hard:
            return [
                "外食は週1まで",
                "揚げ物はなし",
                "夜の主食はなし",
                "間食はなし",
                "酒はなし"
            ]
        }
    }
}

struct PlanInput {
    let gender: UserGender
    let age: Int
    let heightCm: Double
    let currentWeightKg: Double
    let goalWeightKg: Double
    let days: Int
    let foodPreference: FoodPreference
    let fitnessLevel: FitnessLevel
    let trainingDaysPerWeek: Int
    let kneeBack: KneeBackConcern
}

enum PlanMode: String {
    case leanDown
    case weightLoss
    case maintenance
    case caution

    var title: String {
        switch self {
        case .leanDown:
            return "引き締め"
        case .weightLoss:
            return "減量"
        case .maintenance:
            return "維持"
        case .caution:
            return "注意"
        }
    }

    var description: String {
        switch self {
        case .leanDown:
            return "体重より体型を整える"
        case .weightLoss:
            return "脂肪を落とす"
        case .maintenance:
            return "無理に減らさない"
        case .caution:
            return "減量は控えめに"
        }
    }
}

struct PlanResult {
    let mode: PlanMode
    let currentBMI: Double
    let targetBMI: Double
    let days: Int
    let ree: Double
    let tdee: Double
    let dailyDeficit: Double
    let squatShare: Double
    let met: Double
    let kcalPerSquat: Double
    let repsPerTrainingDay: Int
    let dietLevel: DietLevel
    let foodDeficit: Double
    let weeks: Int
    let startReps: Int
    let finalReps: Int
    let weeklyIncrease: Int

    func weekTargetReps(week: Int) -> Int {
        let percents = PlanEngine.rampPercents(weeks: weeks)
        guard !percents.isEmpty else { return finalReps }

        let index = min(percents.count - 1, max(0, week - 1))
        let reps = Double(finalReps) * percents[index]
        return max(1, Int(reps.rounded()))
    }
}

enum PlanEngine {
    static func make(_ input: PlanInput) -> PlanResult {
        let heightM = input.heightCm / 100
        let currentBMI = input.currentWeightKg / (heightM * heightM)
        let targetBMI = input.goalWeightKg / (heightM * heightM)
        let lossKg = max(0, input.currentWeightKg - input.goalWeightKg)

        // REE uses Mifflin-St Jeor; noAnswer takes the male/female midpoint.
        let reeBase = 10 * input.currentWeightKg + 6.25 * input.heightCm - 5 * Double(input.age)
        let ree: Double
        switch input.gender {
        case .male:
            ree = reeBase + 5
        case .female:
            ree = reeBase - 161
        case .noAnswer:
            ree = ((reeBase + 5) + (reeBase - 161)) / 2
        }

        let tdee = ree * input.fitnessLevel.activityFactor
        // 7000kcal/kg is an in-app MVP constant for rough body-weight planning.
        let dailyDeficit = input.days > 0 ? lossKg * 7000 / Double(input.days) : 0

        let durationBonus: Double
        if input.days >= 300 {
            durationBonus = 0.05
        } else if input.days >= 200 {
            durationBonus = 0.02
        } else {
            durationBonus = 0
        }
        let squatShare = clamp(input.foodPreference.squatShareBase + durationBonus, lower: 0.10, upper: 0.30)

        let met = input.fitnessLevel.met
        let averageWeight = (input.currentWeightKg + input.goalWeightKg) / 2
        let cadence = 10.0
        // MET kcal estimate follows the ACSM oxygen-cost convention.
        let kcalPerSquat = ((met - 1) * 3.5 * averageWeight / 200) / cadence
        let dailySquatKcal = dailyDeficit * squatShare
        let averageRepsPerDay = kcalPerSquat > 0 ? dailySquatKcal / kcalPerSquat : 0
        let rawRepsPerTrainingDay = input.trainingDaysPerWeek > 0
            ? Int((averageRepsPerDay * 7 / Double(input.trainingDaysPerWeek)).rounded(.up))
            : 0
        let repsPerTrainingDay = min(400, max(10, rawRepsPerTrainingDay))
        let foodDeficit = dailyDeficit * (1 - squatShare)
        let dietLevel: DietLevel
        if foodDeficit < 150 {
            dietLevel = .loose
        } else if foodDeficit < 250 {
            dietLevel = .standard
        } else if foodDeficit < 350 {
            dietLevel = .strong
        } else {
            dietLevel = .hard
        }

        let weeks = min(52, max(4, Int((Double(input.days) / 7).rounded())))
        let finalReps = repsPerTrainingDay
        let startReps = max(8, Int((Double(finalReps) * input.fitnessLevel.startRatio).rounded()))
        let weeklyIncrease = max(1, Int((Double(max(1, finalReps - startReps)) / Double(max(1, weeks))).rounded(.up)))
        let mode: PlanMode
        if currentBMI < 18.5 {
            mode = .caution
        } else if currentBMI < 25 && targetBMI >= 19.5 {
            mode = .leanDown
        } else if currentBMI >= 25 {
            mode = .weightLoss
        } else {
            mode = .maintenance
        }

        return PlanResult(
            mode: mode,
            currentBMI: currentBMI,
            targetBMI: targetBMI,
            days: input.days,
            ree: ree,
            tdee: tdee,
            dailyDeficit: dailyDeficit,
            squatShare: squatShare,
            met: met,
            kcalPerSquat: kcalPerSquat,
            repsPerTrainingDay: repsPerTrainingDay,
            dietLevel: dietLevel,
            foodDeficit: foodDeficit,
            weeks: weeks,
            startReps: startReps,
            finalReps: finalReps,
            weeklyIncrease: weeklyIncrease
        )
    }

    static func rampPercents(weeks: Int) -> [Double] {
        guard weeks > 0 else { return [] }

        var percents: [Double] = []
        percents.reserveCapacity(weeks)

        for weekIndex in 0..<weeks {
            let block = weekIndex / 4
            let position = weekIndex % 4
            let percent: Double

            if position == 3 {
                percent = 0.35 + Double(block) * 0.10
            } else {
                percent = 0.40 + Double(block) * 0.15 + Double(position) * 0.05
            }

            percents.append(clamp(percent, lower: 0.10, upper: 1.0))
        }

        percents[weeks - 1] = 1.0
        return percents
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}
