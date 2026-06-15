import SwiftUI

struct SkeletonOverlay: View {
    let frame: PoseFrame

    private let connections: [(BodyJoint, BodyJoint)] = [
        (.neck, .leftShoulder),
        (.neck, .rightShoulder),
        (.nose, .neck),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.rightShoulder, .rightElbow),
        (.leftElbow, .leftWrist),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.rightHip, .rightKnee),
        (.leftKnee, .leftAnkle),
        (.rightKnee, .rightAnkle),
        (.root, .leftHip),
        (.root, .rightHip)
    ]

    var body: some View {
        Canvas { context, size in
            drawSquatGuide(in: &context, size: size)

            for connection in connections {
                guard
                    let start = frame.point(connection.0),
                    let end = frame.point(connection.1)
                else {
                    continue
                }

                var path = Path()
                path.move(to: scaled(start.location, in: size))
                path.addLine(to: scaled(end.location, in: size))

                context.stroke(path, with: .color(.black.opacity(0.72)), lineWidth: 13)
                context.stroke(path, with: .color(connectionColor(for: connection)), lineWidth: 8)
            }

            for point in frame.points {
                let center = scaled(point.location, in: size)
                drawJoint(point.id, at: center, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawSquatGuide(in context: inout GraphicsContext, size: CGSize) {
        guard frame.phase != .complete else { return }

        let guideY = size.height * 0.68
        var guide = Path()
        guide.move(to: CGPoint(x: size.width * 0.12, y: guideY))
        guide.addLine(to: CGPoint(x: size.width * 0.88, y: guideY))
        context.stroke(
            guide,
            with: .color(WorkoutTheme.orange.opacity(frame.phase == .lowered ? 0.35 : 0.72)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [12, 10])
        )
    }

    private func drawJoint(_ joint: BodyJoint, at center: CGPoint, in context: inout GraphicsContext) {
        let radius: CGFloat = {
            switch joint {
            case .nose:
                return 10
            case .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
                return 8
            default:
                return 6
            }
        }()

        let outer = CGRect(
            x: center.x - radius - 3,
            y: center.y - radius - 3,
            width: (radius + 3) * 2,
            height: (radius + 3) * 2
        )
        let inner = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.fill(Path(ellipseIn: outer), with: .color(.black.opacity(0.76)))
        context.fill(Path(ellipseIn: inner), with: .color(jointColor(for: joint)))
    }

    private func connectionColor(for connection: (BodyJoint, BodyJoint)) -> Color {
        if isLeg(connection) {
            return WorkoutTheme.orange
        }

        if isArm(connection) {
            return Color(red: 0.36, green: 0.86, blue: 1.0)
        }

        return .white
    }

    private func jointColor(for joint: BodyJoint) -> Color {
        switch joint {
        case .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
            return WorkoutTheme.orange
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return Color(red: 0.36, green: 0.86, blue: 1.0)
        default:
            return .white
        }
    }

    private func isLeg(_ connection: (BodyJoint, BodyJoint)) -> Bool {
        switch connection {
        case (.leftHip, .rightHip),
            (.leftHip, .leftKnee),
            (.rightHip, .rightKnee),
            (.leftKnee, .leftAnkle),
            (.rightKnee, .rightAnkle),
            (.root, .leftHip),
            (.root, .rightHip):
            return true
        default:
            return false
        }
    }

    private func isArm(_ connection: (BodyJoint, BodyJoint)) -> Bool {
        switch connection {
        case (.leftShoulder, .leftElbow),
            (.rightShoulder, .rightElbow),
            (.leftElbow, .leftWrist),
            (.rightElbow, .rightWrist):
            return true
        default:
            return false
        }
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let sourceWidth = max(frame.sourceAspectRatio, 0.01)
        let sourceHeight: CGFloat = 1
        let scale = max(size.width / sourceWidth, size.height / sourceHeight)
        let displayedWidth = sourceWidth * scale
        let displayedHeight = sourceHeight * scale
        let xOffset = (size.width - displayedWidth) / 2
        let yOffset = (size.height - displayedHeight) / 2

        return CGPoint(
            x: xOffset + point.x * displayedWidth,
            y: yOffset + point.y * displayedHeight
        )
    }
}
