import CarPlay
import UIKit

/// CarPlay's maneuver from Dart's: the sentence, the icon Dart drew, the
/// distance, and on iOS 17.4+ the type, exit angle and lanes for the
/// instrument cluster and head-up display.
enum ManeuverBuilder {
  /// The distance in the unit the phone shows it in: metres below a
  /// kilometre, then kilometres with one decimal, from ten whole ones.
  /// CarPlay formats the measurement itself, in the phone's locale.
  static func distance(_ meters: Double) -> Measurement<UnitLength> {
    if meters < 1000 { return Measurement(value: meters.rounded(), unit: UnitLength.meters) }
    if meters < 10000 { return Measurement(value: (meters / 100).rounded() / 10, unit: UnitLength.kilometers) }
    return Measurement(value: (meters / 1000).rounded(), unit: UnitLength.kilometers)
  }

  static func estimates(meters: Double, seconds: Double) -> CPTravelEstimates {
    CPTravelEstimates(distanceRemaining: distance(meters), timeRemaining: seconds)
  }

  static func maneuver(_ m: CarManeuver) -> CPManeuver {
    let maneuver = CPManeuver()
    var variants = [m.instruction]
    if let short = m.shortAction, short != m.instruction { variants.append(short) }
    maneuver.instructionVariants = variants
    // At an exit: briefly what you do, with the sign (exit number, road
    // shields, directions) as an image on the line below, as the phone's
    // header shows it.
    if let key = m.signIconKey, let sign = CarHost.shared.images[key] {
      let text = NSMutableAttributedString(string: (m.shortAction ?? m.instruction) + "\n")
      let attachment = NSTextAttachment()
      attachment.image = sign
      let height: CGFloat = 24
      attachment.bounds = CGRect(x: 0, y: -6, width: sign.size.width * height / sign.size.height, height: height)
      text.append(NSAttributedString(attachment: attachment))
      maneuver.attributedInstructionVariants = [text]
    }
    if let image = CarHost.shared.images[m.iconKey] { maneuver.symbolImage = image }
    maneuver.initialTravelEstimates = estimates(meters: m.metersToNext, seconds: 0)
    maneuver.userInfo = m.iconKey
    if #available(iOS 17.4, *) {
      maneuver.maneuverType = type(m)
      if let angle = m.roundaboutAngle {
        maneuver.junctionExitAngle = Measurement(value: angle, unit: UnitAngle.degrees)
      }
      if !m.streets.isEmpty { maneuver.roadFollowingManeuverVariants = m.streets }
    }
    return maneuver
  }

  @available(iOS 17.4, *)
  static func type(_ m: CarManeuver) -> CPManeuverType {
    switch m.type {
    case .depart: return .startRoute
    case .destination, .destinationLeft, .destinationRight: return .arriveAtDestination
    case .straight, .keepStraight, .onRampStraight: return .straightAhead
    case .nameChange, .merge: return .followRoad
    case .slightRight: return .slightRightTurn
    case .right: return .rightTurn
    case .sharpRight: return .sharpRightTurn
    case .uturnRight, .uturnLeft: return .uTurn
    case .sharpLeft: return .sharpLeftTurn
    case .left: return .leftTurn
    case .slightLeft: return .slightLeftTurn
    case .onRampRight, .onRampLeft: return .onRamp
    case .offRampRight, .offRampLeft: return .offRamp
    case .keepRight, .mergeRight: return .keepRight
    case .keepLeft, .mergeLeft: return .keepLeft
    case .roundabout: return .enterRoundabout
    case .roundaboutExit: return .exitRoundabout
    case .ferryEnter, .ferryExit: return .followRoad
    }
  }

  /// A lane's direction as an angle, 0 = straight on, clockwise.
  static func angle(_ direction: String) -> Double {
    switch direction {
    case "slight right": return 45
    case "right": return 90
    case "sharp right": return 135
    case "uturn": return 180
    case "sharp left": return 225
    case "left": return 270
    case "slight left": return 315
    default: return 0
    }
  }

  @available(iOS 18.0, *)
  static func laneGuidance(_ lanes: [CarLane], instruction: String) -> CPLaneGuidance {
    let guidance = CPLaneGuidance()
    guidance.instructionVariants = [instruction]
    guidance.lanes = lanes.map { lane in
      let directions = lane.directions.isEmpty ? ["straight"] : lane.directions
      let angles = directions.map { Measurement(value: angle($0), unit: UnitAngle.degrees) }
      if lane.correct {
        let highlighted = Measurement(value: angle(lane.usage ?? directions[0]), unit: UnitAngle.degrees)
        return CPLane(angles: angles, highlightedAngle: highlighted, isPreferred: true)
      }
      return CPLane(angles: angles)
    }
    return guidance
  }
}
