//
//  AppSettings.swift
//  XiangqiApp
//
//  应用设置：OpenAI 兼容多模态接口配置，持久化到 UserDefaults。
//

import Foundation
import Combine

/// 电脑（引擎）执方设置。
enum EngineSide: String, CaseIterable {
    case red    // 电脑执红，玩家执黑
    case black  // 电脑执黑，玩家执红
    case off    // 关闭，双方纯手动/手动触发

    var label: String {
        switch self {
        case .red: return "电脑执红"
        case .black: return "电脑执黑"
        case .off: return "关闭"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @Published var visionBaseURL: String {
        didSet { defaults.set(visionBaseURL, forKey: Keys.baseURL) }
    }
    @Published var visionAPIKey: String {
        didSet { defaults.set(visionAPIKey, forKey: Keys.apiKey) }
    }
    @Published var visionModel: String {
        didSet { defaults.set(visionModel, forKey: Keys.model) }
    }
    /// AI 思考时间（毫秒）。
    @Published var thinkTimeMs: Int {
        didSet { defaults.set(thinkTimeMs, forKey: Keys.thinkTime) }
    }
    /// 图片识别超时时间（秒）。
    @Published var visionTimeout: Int {
        didSet { defaults.set(visionTimeout, forKey: Keys.visionTimeout) }
    }
    /// 是否启用音效。
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }
    /// 电脑执方（红/黑/关闭）。
    @Published var engineSide: EngineSide {
        didSet { defaults.set(engineSide.rawValue, forKey: Keys.engineSide) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseURL = "vision.baseURL"
        static let apiKey = "vision.apiKey"
        static let model = "vision.model"
        static let thinkTime = "engine.thinkTimeMs"
        static let visionTimeout = "vision.timeoutSec"
        static let soundEnabled = "game.soundEnabled"
        static let engineSide = "engine.side"
    }

    private init() {
        visionBaseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        visionAPIKey = defaults.string(forKey: Keys.apiKey) ?? ""
        visionModel = defaults.string(forKey: Keys.model) ?? "gpt-4o"
        let t = defaults.integer(forKey: Keys.thinkTime)
        thinkTimeMs = t == 0 ? 1000 : t
        let vt = defaults.integer(forKey: Keys.visionTimeout)
        visionTimeout = vt == 0 ? 120 : vt
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        engineSide = EngineSide(rawValue: defaults.string(forKey: Keys.engineSide) ?? "") ?? .black
    }

    var visionConfigured: Bool {
        !visionBaseURL.isEmpty && !visionAPIKey.isEmpty && !visionModel.isEmpty
    }
}
