//
//  VisionService.swift
//  XiangqiApp
//
//  调用 OpenAI 兼容多模态接口（/chat/completions），把棋盘图片识别为 FEN 字符串。
//

import UIKit

enum VisionError: LocalizedError {
    case notConfigured
    case badImage
    case badURL
    case http(Int, String)
    case noContent
    case noFEN(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "接口未配置"
        case .badImage: return "图片无法编码"
        case .badURL: return "Base URL 无效"
        case .http(let code, let msg): return "HTTP \(code) \(msg)"
        case .noContent: return "接口未返回内容"
        case .noFEN(let s): return "未从回复中解析出 FEN：\(s)"
        }
    }
}

enum VisionService {

    /// 从主线程隔离的 AppSettings 中快照出的不可变配置，便于在后台使用。
    private struct VisionConfig {
        let baseURL: String
        let apiKey: String
        let model: String
        var isConfigured: Bool { !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty }

        @MainActor init(settings: AppSettings) {
            baseURL = settings.visionBaseURL
            apiKey = settings.visionAPIKey
            model = settings.visionModel
        }
    }

    private static let prompt = """
    你是中国象棋识别助手。请仔细识别这张中国象棋棋盘图片，输出该局面的 FEN 字符串。
    要求：
    - 使用标准象棋 FEN，10 行用 / 分隔，从上到下（黑方底线在最上）。
    - 棋子字母：车 r/R、马 n/N、炮 c/C、相象 b/B、仕士 a/A、将帅 k/K、兵卒 p/P；红方大写、黑方小写。
    - 连续空位用数字表示，每行合计 9 列。
    - 结尾附走子方（w 红 / b 黑），无法判断默认 w。
    - 只输出一行 FEN，不要任何解释、不要代码块标记。
    """

    static func recognizeFEN(from image: UIImage, settings: AppSettings) async throws -> String {
        let config = await VisionConfig(settings: settings)
        guard config.isConfigured else { throw VisionError.notConfigured }
        // 压缩，避免请求体过大
        let resized = image.resizedForVision(maxDimension: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { throw VisionError.badImage }
        let base64 = jpeg.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(base64)"

        let base = config.baseURL.hasSuffix("/")
            ? String(config.baseURL.dropLast())
            : config.baseURL
        guard let url = URL(string: base + "/chat/completions") else { throw VisionError.badURL }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
            ]],
            "temperature": 0
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw VisionError.http(http.statusCode, String(msg.prefix(200)))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw VisionError.noContent
        }

        guard let fen = extractFEN(from: content) else { throw VisionError.noFEN(content) }
        return fen
    }

    /// 从模型回复中提取 FEN（含至少 9 个 / 的 token）。
    private static func extractFEN(from text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: "`", with: "")
        for line in cleaned.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.filter({ $0 == "/" }).count >= 9 {
                return trimmed
            }
        }
        // 退而求其次：整段里找连续 token
        for token in cleaned.split(separator: " ") where token.filter({ $0 == "/" }).count >= 9 {
            return String(token)
        }
        return nil
    }
}

private extension UIImage {
    func resizedForVision(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
