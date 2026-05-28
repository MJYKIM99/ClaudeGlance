//
//  AgentPetTheme.swift
//  ClaudeGlance
//
//  Generated desktop pet sprite themes.
//

import Foundation

enum AgentPetTheme: String, CaseIterable, Identifiable {
    case robot
    case crab
    case polarBear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .robot:
            return "Pixel Robot"
        case .crab:
            return "Orange Pixel Crab"
        case .polarBear:
            return "White Pixel Polar Bear"
        }
    }

    var assetPrefix: String {
        switch self {
        case .robot:
            return "AgentPet"
        case .crab:
            return "AgentPetCrab"
        case .polarBear:
            return "AgentPetPolarBear"
        }
    }

    static var current: AgentPetTheme {
        let rawValue = UserDefaults.standard.string(forKey: Defaults.desktopPetTheme) ?? AgentPetTheme.robot.rawValue
        return AgentPetTheme(rawValue: rawValue) ?? .robot
    }
}
