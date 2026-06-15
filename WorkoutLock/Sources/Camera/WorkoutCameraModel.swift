import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UIKit
import Vision

final class WorkoutCameraModel: NSObject, ObservableObject {
    @Published var frame = PoseFrame.empty
    @Published var status: CameraStatus = .idle
    @Published private(set) var latestSnapshotData: Data?
    @Published private(set) var firstPoseSnapshotData: Data?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "workout-lock.camera.session")
    private let videoQueue = DispatchQueue(label: "workout-lock.camera.video", qos: .userInitiated)
    private lazy var pipeline = PosePipeline(
        onFrame: { [weak self] frame in
            self?.frame = frame
        },
        onSnapshot: { [weak self] snapshotData in
            self?.latestSnapshotData = snapshotData
        },
        onFirstPoseSnapshot: { [weak self] snapshotData in
            self?.firstPoseSnapshotData = snapshotData
        }
    )
    private var isConfigured = false

    @MainActor
    func start() {
        guard status != .running else { return }
        status = .requestingAccess

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                status = .denied
                return
            }

            configureAndStartSession()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func applyCalibration(_ calibration: TutorialCalibration?) {
        videoQueue.async { [weak self] in
            self?.pipeline.applyCalibration(calibration?.poseCalibration)
        }
    }

    @MainActor
    func debugAddRep() {
        frame.repCount += 1
        frame.guidance = "シミュレーター確認用に1回加算しました"
        frame.phase = .standing
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }

                guard
                    let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                        ?? AVCaptureDevice.default(for: .video)
                else {
                    Task { @MainActor in
                        self.status = .unavailable("シミュレーターでは実カメラが使えません")
                    }
                    self.session.commitConfiguration()
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                    }
                } catch {
                    Task { @MainActor in
                        self.status = .unavailable(error.localizedDescription)
                    }
                    self.session.commitConfiguration()
                    return
                }

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self.pipeline, queue: self.videoQueue)

                if self.session.canAddOutput(output) {
                    self.session.addOutput(output)
                }

                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }

                self.session.commitConfiguration()
                self.isConfigured = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            Task { @MainActor in
                self.status = .running
            }
        }
    }
}

private final class PosePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let counter = SquatPoseCounter()
    private let onFrame: (PoseFrame) -> Void
    private let onSnapshot: (Data) -> Void
    private let onFirstPoseSnapshot: (Data) -> Void
    private let ciContext = CIContext()
    private var lastAnalysisDate = Date.distantPast
    private var lastSnapshotDate = Date.distantPast
    private var didCaptureFirstPoseSnapshot = false
    private let minimumFrameInterval: TimeInterval = 0.08
    private let minimumSnapshotInterval: TimeInterval = 0.85

    init(
        onFrame: @escaping (PoseFrame) -> Void,
        onSnapshot: @escaping (Data) -> Void,
        onFirstPoseSnapshot: @escaping (Data) -> Void
    ) {
        self.onFrame = onFrame
        self.onSnapshot = onSnapshot
        self.onFirstPoseSnapshot = onFirstPoseSnapshot
    }

    func applyCalibration(_ calibration: PoseCalibration?) {
        counter.applyCalibration(calibration)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= minimumFrameInterval else {
            return
        }
        lastAnalysisDate = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let sourceAspectRatio = portraitAspectRatio(for: pixelBuffer)

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .leftMirrored,
            options: [:]
        )

        do {
            try handler.perform([request])
            guard let observation = bestObservation(from: request.results ?? []) else {
                deliver(PoseFrame.noPerson(count: counter.count, sourceAspectRatio: sourceAspectRatio))
                return
            }

            let frame = counter.update(with: observation, sourceAspectRatio: sourceAspectRatio)
            deliver(frame)
            captureSnapshotIfNeeded(from: pixelBuffer, at: now, frame: frame)
        } catch {
            deliver(PoseFrame(
                points: [],
                repCount: counter.count,
                phase: .ready,
                guidance: "姿勢判定に失敗しました",
                kneeAngle: nil,
                sourceAspectRatio: sourceAspectRatio
            ))
        }
    }

    private func portraitAspectRatio(for pixelBuffer: CVPixelBuffer) -> CGFloat {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0 else {
            return 9.0 / 16.0
        }

        return min(width, height) / max(width, height)
    }

    private func deliver(_ frame: PoseFrame) {
        DispatchQueue.main.async { [onFrame] in
            onFrame(frame)
        }
    }

    private func bestObservation(from observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { lhs, rhs in
            confidenceScore(for: lhs) < confidenceScore(for: rhs)
        }
    }

    private func confidenceScore(for observation: VNHumanBodyPoseObservation) -> Float {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        let importantJoints: [VNHumanBodyPoseObservation.JointName] = [
            .neck,
            .root,
            .leftShoulder,
            .rightShoulder,
            .leftHip,
            .rightHip,
            .leftKnee,
            .rightKnee,
            .leftAnkle,
            .rightAnkle
        ]

        return importantJoints.reduce(0) { score, joint in
            score + (points[joint]?.confidence ?? 0)
        }
    }

    private func captureSnapshotIfNeeded(from pixelBuffer: CVPixelBuffer, at date: Date, frame: PoseFrame) {
        guard
            !frame.points.isEmpty,
            date.timeIntervalSince(lastSnapshotDate) >= minimumSnapshotInterval,
            let data = makeSnapshotData(from: pixelBuffer)
        else {
            return
        }

        lastSnapshotDate = date
        DispatchQueue.main.async { [onSnapshot] in
            onSnapshot(data)
        }

        guard !didCaptureFirstPoseSnapshot, frame.phase == .standing else {
            return
        }

        didCaptureFirstPoseSnapshot = true
        DispatchQueue.main.async { [onFirstPoseSnapshot] in
            onFirstPoseSnapshot(data)
        }
    }

    private func makeSnapshotData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.leftMirrored)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}

private final class SquatPoseCounter {
    private(set) var count = 0
    private var phase: RepPhase = .ready
    private var loweredThreshold = 112.0
    private var standingThreshold = 158.0
    private let minimumConfidence: Float = 0.25
    private let smoothingAlpha: CGFloat = 0.42
    private var smoothedPoints: [BodyJoint: PosePoint] = [:]

    func applyCalibration(_ calibration: PoseCalibration?) {
        loweredThreshold = calibration?.loweredThreshold ?? 112.0
        standingThreshold = calibration?.standingThreshold ?? 158.0
    }

    func update(with observation: VNHumanBodyPoseObservation, sourceAspectRatio: CGFloat) -> PoseFrame {
        guard let recognized = try? observation.recognizedPoints(.all) else {
            return PoseFrame.noPerson(count: count, sourceAspectRatio: sourceAspectRatio)
        }

        let posePoints = makePosePoints(from: recognized)
        let leftAngle = kneeAngle(
            hip: point(.leftHip, in: posePoints),
            knee: point(.leftKnee, in: posePoints),
            ankle: point(.leftAnkle, in: posePoints)
        )
        let rightAngle = kneeAngle(
            hip: point(.rightHip, in: posePoints),
            knee: point(.rightKnee, in: posePoints),
            ankle: point(.rightAnkle, in: posePoints)
        )
        let angles = [leftAngle, rightAngle].compactMap { $0 }

        guard !angles.isEmpty else {
            return PoseFrame(
                points: posePoints,
                repCount: count,
                phase: phase,
                guidance: "ひざ・腰・足首まで人形に入れよう",
                kneeAngle: nil,
                sourceAspectRatio: sourceAspectRatio
            )
        }

        let averageAngle = angles.reduce(0, +) / Double(angles.count)
        var guidance = "もちトレのお尻をもう少し下げよう"

        if averageAngle < loweredThreshold {
            phase = .lowered
            guidance = "もちトレを立ち上がらせよう"
        } else if averageAngle > standingThreshold {
            if phase == .lowered {
                count += 1
                guidance = "\(count)回目 OK"
            } else {
                guidance = "もちトレをスクワットさせよう"
            }
            phase = .standing
        }

        return PoseFrame(
            points: posePoints,
            repCount: count,
            phase: phase,
            guidance: guidance,
            kneeAngle: averageAngle,
            sourceAspectRatio: sourceAspectRatio
        )
    }

    private func makePosePoints(
        from recognized: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> [PosePoint] {
        let mapping: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose),
            (.neck, .neck),
            (.root, .root),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        return mapping.compactMap { bodyJoint, visionJoint in
            guard
                let point = recognized[visionJoint],
                point.confidence >= minimumConfidence
            else {
                return nil
            }

            let rawLocation = CGPoint(x: point.location.x, y: 1 - point.location.y)
            let location: CGPoint
            if let previous = smoothedPoints[bodyJoint] {
                location = CGPoint(
                    x: previous.location.x + (rawLocation.x - previous.location.x) * smoothingAlpha,
                    y: previous.location.y + (rawLocation.y - previous.location.y) * smoothingAlpha
                )
            } else {
                location = rawLocation
            }

            let smoothed = PosePoint(
                id: bodyJoint,
                location: location,
                confidence: point.confidence
            )
            smoothedPoints[bodyJoint] = smoothed
            return smoothed
        }
    }

    private func point(_ joint: BodyJoint, in points: [PosePoint]) -> CGPoint? {
        points.first { $0.id == joint }?.location
    }

    private func kneeAngle(hip: CGPoint?, knee: CGPoint?, ankle: CGPoint?) -> Double? {
        guard let hip, let knee, let ankle else { return nil }

        let hipVector = CGVector(dx: hip.x - knee.x, dy: hip.y - knee.y)
        let ankleVector = CGVector(dx: ankle.x - knee.x, dy: ankle.y - knee.y)
        let dot = hipVector.dx * ankleVector.dx + hipVector.dy * ankleVector.dy
        let hipLength = hypot(hipVector.dx, hipVector.dy)
        let ankleLength = hypot(ankleVector.dx, ankleVector.dy)
        guard hipLength > 0, ankleLength > 0 else { return nil }

        let cosine = max(-1, min(1, dot / (hipLength * ankleLength)))
        return acos(cosine) * 180 / .pi
    }
}
