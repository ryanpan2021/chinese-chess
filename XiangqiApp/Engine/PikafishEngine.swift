//
//  PikafishEngine.swift
//  XiangqiApp
//
//  Swift 引擎管理器：封装 PikafishBridge，提供异步友好的 UCI 接口。
//  负责：启动引擎、握手(uci/isready)、设置局面(position)、请求计算(go)、
//  解析 bestmove 与 info score，并把状态发布给 SwiftUI。
//

import Foundation
import Combine

/// 一次搜索的结果：最佳着法 + 评估分。
struct SearchResult {
    /// UCI 着法，如 "h2e2"；可能为 "(none)"。
    let bestMove: String
    /// 评估分（厘兵 centipawn），站在「当前走子方」视角；正值表示走子方占优。
    let scoreCp: Int?
    /// 杀棋步数（mate in N），正为走子方将杀；nil 表示无杀。
    let mateIn: Int?
}

@MainActor
final class PikafishEngine: ObservableObject {

    /// 引擎是否已就绪（收到 uciok + readyok）。
    @Published var isReady: Bool = false
    /// 最近一次引擎返回的最佳着法，例如 "h2e2"。
    @Published var bestMove: String?
    /// 原始日志输出，便于调试。
    @Published var log: [String] = []
    /// NNUE 权重加载状态描述（用于界面排查）。
    @Published var networkStatus: String = "未设置"

    private let bridge = PikafishBridge()
    private var didHandshake = false

    /// 一次性回调（go 完成时触发）。
    private var resultContinuation: CheckedContinuation<SearchResult, Never>?
    /// 本次搜索最近一次 info 行解析出的分值。
    private var pendingScoreCp: Int?
    private var pendingMateIn: Int?
    /// 是否有搜索正在进行（用于串行化，防止 continuation 被覆盖）。
    private var isSearching = false

    init() {
        bridge.outputHandler = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in
                self.handleLine(line)
            }
        }
    }

    /// 启动引擎并完成 UCI 握手。
    /// - Parameter networkPath: NNUE 权重文件路径（可选）。若提供，将在 isready 前设置 EvalFile。
    func start(networkPath: String? = nil) {
        bridge.start()
        bridge.sendCommand("uci")
        if let networkPath {
            bridge.sendCommand("setoption name EvalFile value \(networkPath)")
            networkStatus = "已设置：\((networkPath as NSString).lastPathComponent)"
        } else {
            networkStatus = "缺失：未找到 pikafish.nnue"
        }
        bridge.sendCommand("isready")
    }

    /// 停止引擎。
    func stop() {
        bridge.stop()
        isReady = false
    }

    // MARK: - 设置局面

    /// 用 FEN 设置当前局面。
    func setPosition(fen: String, moves: [String] = []) {
        var cmd = "position fen \(fen)"
        if !moves.isEmpty {
            cmd += " moves " + moves.joined(separator: " ")
        }
        bridge.sendCommand(cmd)
    }

    /// 用起始局面 + 着法列表设置当前局面。
    func setStartPosition(moves: [String] = []) {
        var cmd = "position startpos"
        if !moves.isEmpty {
            cmd += " moves " + moves.joined(separator: " ")
        }
        bridge.sendCommand(cmd)
    }

    // MARK: - 搜索

    /// 请求引擎按给定思考时间(毫秒)计算，返回最佳着法 + 评估分。
    func search(moveTimeMs: Int) async -> SearchResult {
        await runSearch(command: "go movetime \(moveTimeMs)")
    }

    /// 请求引擎按搜索深度计算，返回最佳着法 + 评估分。
    func search(depth: Int) async -> SearchResult {
        await runSearch(command: "go depth \(depth)")
    }

    private func runSearch(command: String) async -> SearchResult {
        // 串行化：等待上一次搜索完成，避免单一 continuation 被覆盖导致永久挂起。
        while isSearching {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        isSearching = true
        return await withCheckedContinuation { continuation in
            self.resultContinuation = continuation
            self.pendingScoreCp = nil
            self.pendingMateIn = nil
            bridge.sendCommand(command)
        }
    }

    // MARK: - 输出解析

    private func handleLine(_ line: String) {
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }

        if line == "uciok" {
            didHandshake = true
        } else if line == "readyok" {
            isReady = true
        } else if line.hasPrefix("info ") {
            parseInfoScore(line)
        } else if line.hasPrefix("bestmove") {
            // 格式: "bestmove h2e2 ponder ..."
            let parts = line.split(separator: " ")
            let move = parts.count >= 2 ? String(parts[1]) : "(none)"
            bestMove = move
            let result = SearchResult(bestMove: move, scoreCp: pendingScoreCp, mateIn: pendingMateIn)
            let cont = resultContinuation
            resultContinuation = nil
            isSearching = false
            cont?.resume(returning: result)
        }
    }

    /// 从 info 行解析 "score cp N" 或 "score mate N"。
    private func parseInfoScore(_ line: String) {
        let tokens = line.split(separator: " ").map(String.init)
        guard let idx = tokens.firstIndex(of: "score"), idx + 2 < tokens.count else { return }
        let kind = tokens[idx + 1]
        let value = Int(tokens[idx + 2])
        if kind == "cp" {
            pendingScoreCp = value
            pendingMateIn = nil
        } else if kind == "mate" {
            pendingMateIn = value
            pendingScoreCp = nil
        }
    }
}
