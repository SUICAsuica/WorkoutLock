import Foundation

enum WorkoutPlanEstimator {
    static func makePlans(
        gender: UserGender,
        heightCm: Double,
        currentWeightKg: Double,
        goalWeightKg: Double,
        goalDurationMonths: Int,
        calibration: TutorialCalibration?,
        recentRecords: [WorkoutRecord]
    ) -> [TrainingPlan] {
        let profile = profileEstimate(
            gender: gender,
            heightCm: heightCm,
            currentWeightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            goalDurationMonths: goalDurationMonths
        )
        let calibratedStart = calibratedStartReps(profileStart: profile.baseStartReps, calibration: calibration)
        let adaptation = adaptationFactor(from: recentRecords)
        let targetBoost = Int((Double(profile.targetBoost) * adaptation).rounded())
        let targetWeeks = max(4, min(52, goalDurationMonths * 4))
        let shortWeeks = max(4, targetWeeks - 4)
        let longWeeks = min(52, targetWeeks + 4)

        return [
            makePlan(
                id: "gentle",
                title: "継続重視",
                stance: "\(longWeeks / 4)ヶ月で無理なく続ける",
                durationWeeks: longWeeks,
                startReps: max(6, calibratedStart - 1),
                endReps: max(24, profile.goalEndReps - 8 + targetBoost),
                weeklyIncrease: weeklyIncrease(start: max(6, calibratedStart - 1), end: max(24, profile.goalEndReps - 8 + targetBoost), weeks: longWeeks),
                dailySessions: 1,
                profile: profile,
                calibration: calibration,
                mode: .gentle
            ),
            makePlan(
                id: "standard",
                title: "目標ペース",
                stance: "\(targetWeeks / 4)ヶ月で目標に合わせる",
                durationWeeks: targetWeeks,
                startReps: calibratedStart,
                endReps: profile.goalEndReps + targetBoost,
                weeklyIncrease: weeklyIncrease(start: calibratedStart, end: profile.goalEndReps + targetBoost, weeks: targetWeeks),
                dailySessions: 1,
                profile: profile,
                calibration: calibration,
                mode: .standard
            ),
            makePlan(
                id: "hard",
                title: "強制力高め",
                stance: "\(shortWeeks / 4)ヶ月で攻める",
                durationWeeks: shortWeeks,
                startReps: max(10, calibratedStart + 2),
                endReps: profile.goalEndReps + targetBoost + 10,
                weeklyIncrease: weeklyIncrease(start: max(10, calibratedStart + 2), end: profile.goalEndReps + targetBoost + 10, weeks: shortWeeks),
                dailySessions: 1,
                profile: profile,
                calibration: calibration,
                mode: .hard
            )
        ]
    }

    private static func profileEstimate(
        gender: UserGender,
        heightCm: Double,
        currentWeightKg: Double,
        goalWeightKg: Double,
        goalDurationMonths: Int
    ) -> ProfileEstimate {
        let heightM = max(1.2, heightCm / 100)
        let bmi = currentWeightKg / (heightM * heightM)
        let targetGap = max(0, currentWeightKg - goalWeightKg)
        let months = max(1, min(12, goalDurationMonths))
        let monthlyGap = targetGap / Double(months)
        let goalPressure = min(1.4, (targetGap / 10.0) + (monthlyGap / 2.5))
        let bmiPressure = min(1.0, max(0, bmi - 22.0) / 10.0)
        let genderAdjustment: Double
        switch gender {
        case .male:
            genderAdjustment = 1.12
        case .female:
            genderAdjustment = 0.96
        case .noAnswer:
            genderAdjustment = 1.0
        }
        let baseStart = max(6, min(18, Int(((currentWeightKg / 12.5) * genderAdjustment + goalPressure * 2.2).rounded())))
        let targetBoost = min(30, Int(((targetGap * 2.4) + (monthlyGap * 4.0) + (bmiPressure * 10)).rounded()))
        let goalEndReps = max(24, min(90, 28 + Int((goalPressure * 18 + bmiPressure * 12).rounded())))

        return ProfileEstimate(
            bmi: bmi,
            goalPressure: goalPressure,
            bmiPressure: bmiPressure,
            baseStartReps: baseStart,
            targetBoost: targetBoost,
            goalEndReps: goalEndReps
        )
    }

    private static func calibratedStartReps(
        profileStart: Int,
        calibration: TutorialCalibration?
    ) -> Int {
        guard let calibration, calibration.actualReps > 0 else {
            return profileStart
        }

        let speedAdjustment: Int
        if calibration.secondsPerRep <= 2.7 {
            speedAdjustment = 2
        } else if calibration.secondsPerRep <= 4.2 {
            speedAdjustment = 1
        } else if calibration.secondsPerRep <= 6.0 {
            speedAdjustment = 0
        } else {
            speedAdjustment = -1
        }

        let qualityAdjustment: Int
        if calibration.qualityScore >= 80 {
            qualityAdjustment = 1
        } else if calibration.qualityScore < 45 {
            qualityAdjustment = -2
        } else if calibration.qualityScore < 60 {
            qualityAdjustment = -1
        } else {
            qualityAdjustment = 0
        }

        return max(6, min(20, profileStart + speedAdjustment + qualityAdjustment))
    }

    private static func weeklyIncrease(start: Int, end: Int, weeks: Int) -> Int {
        max(1, Int((Double(max(1, end - start)) / Double(max(1, weeks))).rounded(.up)))
    }

    private static func adaptationFactor(from records: [WorkoutRecord]) -> Double {
        let recent = Array(records.prefix(7))
        guard !recent.isEmpty else { return 1.0 }
        let completionRate = Double(recent.filter { $0.actualReps >= $0.targetReps }.count) / Double(recent.count)
        if completionRate >= 0.85 {
            return 1.08
        }
        if completionRate < 0.55 {
            return 0.9
        }
        return 1.0
    }

    private static func makePlan(
        id: String,
        title: String,
        stance: String,
        durationWeeks: Int,
        startReps: Int,
        endReps: Int,
        weeklyIncrease: Int,
        dailySessions: Int,
        profile: ProfileEstimate,
        calibration: TutorialCalibration?,
        mode: EstimatorPlanMode
    ) -> TrainingPlan {
        let weeklyRamp = Double(max(1, endReps - startReps)) / Double(max(1, durationWeeks))
        let fatiguePenalty = min(30, Int(weeklyRamp * 4.5 + Double(startReps) * 0.9))
        let calibrationBonus = calibration.map { $0.qualityScore >= 75 ? 4 : ($0.qualityScore < 50 ? -8 : 0) } ?? 0
        let goalBonus = Int((1.0 - min(1.0, profile.goalPressure)) * 8)
        let adherence = max(30, min(92, 84 - fatiguePenalty + goalBonus + calibrationBonus - mode.adherencePenalty))
        let loadScore = max(mode.minimumLoad, min(mode.maximumLoad, Int((profile.bmiPressure + profile.goalPressure) * Double(mode.loadMultiplier)) + mode.loadBase))
        let rationale: String

        if let calibration {
            rationale = "目標期間と5回チュートリアルの速度\(calibration.secondsPerRep.formatted(.number.precision(.fractionLength(1))))秒/回、検出安定度\(calibration.qualityScore)%から回数を決めました。"
        } else {
            rationale = "身長・体重・性別・目標体重・目標期間から回数を決めました。"
        }

        return TrainingPlan(
            id: id,
            title: title,
            stance: stance,
            durationWeeks: durationWeeks,
            startReps: startReps,
            endReps: max(startReps + durationWeeks, endReps),
            weeklyIncrease: weeklyIncrease,
            dailySessions: dailySessions,
            loadScore: loadScore,
            predictedAdherence: adherence,
            rationale: rationale
        )
    }
}

private struct ProfileEstimate {
    let bmi: Double
    let goalPressure: Double
    let bmiPressure: Double
    let baseStartReps: Int
    let targetBoost: Int
    let goalEndReps: Int
}

private enum EstimatorPlanMode {
    case gentle
    case standard
    case hard

    var minimumLoad: Int {
        switch self {
        case .gentle: return 25
        case .standard: return 45
        case .hard: return 62
        }
    }

    var maximumLoad: Int {
        switch self {
        case .gentle: return 55
        case .standard: return 78
        case .hard: return 96
        }
    }

    var loadBase: Int {
        switch self {
        case .gentle: return 28
        case .standard: return 42
        case .hard: return 58
        }
    }

    var loadMultiplier: Int {
        switch self {
        case .gentle: return 24
        case .standard: return 30
        case .hard: return 34
        }
    }

    var adherencePenalty: Int {
        switch self {
        case .gentle: return 0
        case .standard: return 5
        case .hard: return 12
        }
    }
}
