import Foundation

struct PushUpConfig: Codable {
    let depthFrontThreshold: Double
    let depthSideThreshold: Double
    let lockoutFrontThreshold: Double
    let lockoutSideThreshold: Double
    let lockoutHoldMS: Int
    let minDownVelocityFront: Double
    let minUpVelocityFront: Double
    let minDownVelocitySide: Double
    let minUpVelocitySide: Double
    let dwellFrontMS: Int
    let dwellSideMS: Int
    
    let hipBaseDefault: Double
    let flareBaseDefault: Double
    let shoulderAsymYellow: Double
    let shoulderAsymRed: Double
    let elbowDiffYellow: Double
    let elbowDiffRed: Double
    
    let hipPenaltyMax: Double
    let flarePenaltyMax: Double
    let depthPenaltyMax: Double
    let asymPenaltyMax: Double
    let hipPenaltyScale: Double
    let flarePenaltyScale: Double
    let depthPenaltyScale: Double
    let asymPenaltyScale: Double

    let feedbackRules: [FeedbackRule]
    let fsmFront: PushUpFSMConfig?
    let fsmSide: PushUpFSMConfig?
}

struct SquatConfig: Codable {
    let depthThreshold: Double
    let lockoutAngle: Double
    let kneeValgusThreshold: Double
    let tempoMinSec: Double
    let feedbackRules: [FeedbackRule]
}

struct PullUpConfig: Codable {
    let chinOverBarAngle: Double
    let bottomAngle: Double
    let asymmetryAngleDiff: Double
    let tempoMinSec: Double
    let feedbackRules: [FeedbackRule]
}

enum RuleSeverity: String, Codable {
    case critical
    case important
    case minor
}

struct FeedbackRule: Codable {
    let id: String
    let severity: RuleSeverity
    let message: String
    let metric: String
    let op: String
    let threshold: Double
    let appliesIn: [String]?
}

struct PushUpFSMConfig: Codable {
    let stateOrder: [String]
    let states: [String: PushUpFSMState]
    let counter: PushUpFSMCounter
    let minRepDurationSec: Double
}

struct PushUpFSMState: Codable {
    let condition: String
}

struct PushUpFSMCounter: Codable {
    let from: String
    let to: String
}

final class ExerciseDefinitionStore {
    static let shared = ExerciseDefinitionStore()
    
    let pushUp: PushUpConfig
    let squat: SquatConfig
    let pullUp: PullUpConfig
    
    private init() {
        self.pushUp = Self.load("push_up", as: PushUpConfig.self) ?? PushUpConfig(
            depthFrontThreshold: 110,
            depthSideThreshold: 100,
            lockoutFrontThreshold: 145,
            lockoutSideThreshold: 165,
            lockoutHoldMS: 300,
            minDownVelocityFront: -1,
            minUpVelocityFront: 1,
            minDownVelocitySide: -20,
            minUpVelocitySide: 20,
            dwellFrontMS: 40,
            dwellSideMS: 80,
            hipBaseDefault: 0.18,
            flareBaseDefault: 0.5,
            shoulderAsymYellow: 0.08,
            shoulderAsymRed: 0.12,
            elbowDiffYellow: 15.0,
            elbowDiffRed: 25.0,
            hipPenaltyMax: 40,
            flarePenaltyMax: 30,
            depthPenaltyMax: 30,
            asymPenaltyMax: 25,
            hipPenaltyScale: 60,
            flarePenaltyScale: 50,
            depthPenaltyScale: 60,
            asymPenaltyScale: 60,
            feedbackRules: [],
            fsmFront: nil,
            fsmSide: nil
        )
        
        self.squat = Self.load("squat", as: SquatConfig.self) ?? SquatConfig(
            depthThreshold: 95,
            lockoutAngle: 170,
            kneeValgusThreshold: 15,
            tempoMinSec: 0.6,
            feedbackRules: []
        )
        
        self.pullUp = Self.load("pull_up", as: PullUpConfig.self) ?? PullUpConfig(
            chinOverBarAngle: 65,
            bottomAngle: 160,
            asymmetryAngleDiff: 15,
            tempoMinSec: 0.6,
            feedbackRules: []
        )
    }
    
    private static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "ExerciseDefinitions")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        guard let url = url else {
            print("Missing \(name).json in app bundle (checked ExerciseDefinitions/ and root)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Failed to load \(name).json: \(error)")
            return nil
        }
    }
}
