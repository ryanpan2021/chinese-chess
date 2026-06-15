//
//  SettingsView.swift
//  XiangqiApp
//
//  设置页：填写 OpenAI 兼容多模态接口（图片识别用）与引擎思考时间。
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Base URL")
                        TextField("https://api.openai.com/v1", text: $settings.visionBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("API Key")
                        SecureField("sk-...", text: $settings.visionAPIKey)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Model")
                        TextField("gpt-4o", text: $settings.visionModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("图片识别接口（OpenAI 兼容）")
                } footer: {
                    Text("使用 /v1/chat/completions 多模态接口，需支持图像输入。")
                }

                Section("引擎") {
                    Stepper(value: $settings.thinkTimeMs, in: 200...10000, step: 200) {
                        Text("思考时间：\(settings.thinkTimeMs) ms")
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
