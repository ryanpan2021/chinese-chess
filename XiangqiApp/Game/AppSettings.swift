//
//  AppSettings.swift
//  XiangqiApp
//
//  应用设置：OpenAI 兼容多模态接口配置，持久化到 UserDefaults。
//

import Foundation
import Combine

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

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseURL = "vision.baseURL"
        static let apiKey = "vision.apiKey"
        static let model = "vision.model"
        static let thinkTime = "engine.thinkTimeMs"
    }

    private init() {
        visionBaseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        visionAPIKey = defaults.string(forKey: Keys.apiKey) ?? ""
        visionModel = defaults.string(forKey: Keys.model) ?? "gpt-4o"
        let t = defaults.integer(forKey: Keys.thinkTime)
        thinkTimeMs = t == 0 ? 1000 : t
    }

    var visionConfigured: Bool {
        !visionBaseURL.isEmpty && !visionAPIKey.isEmpty && !visionModel.isEmpty
    }
}
