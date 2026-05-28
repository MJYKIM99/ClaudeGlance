//
//  AgentPetAnimationSpeed.swift
//  ClaudeGlance
//
//  Playback presets for generated desktop pet sprite loops.
//

import Foundation

enum AgentPetAnimationSpeed: String, CaseIterable, Identifiable {
    case relaxed
    case normal
    case snappy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relaxed:
            return "Relaxed"
        case .normal:
            return "Normal"
        case .snappy:
            return "Snappy"
        }
    }

    var intervalMultiplier: Double {
        switch self {
        case .relaxed:
            return 1.25
        case .normal:
            return 1.0
        case .snappy:
            return 0.78
        }
    }

    static var current: AgentPetAnimationSpeed {
        let rawValue = UserDefaults.standard.string(forKey: Defaults.desktopPetAnimationSpeed)
            ?? AgentPetAnimationSpeed.normal.rawValue
        return AgentPetAnimationSpeed(rawValue: rawValue) ?? .normal
    }
}
