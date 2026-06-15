//
//  WinRate.swift
//  XiangqiApp
//
//  将引擎评估分（centipawn / mate）转换为胜率百分比，并统一为「红方视角」。
//

import Foundation

enum WinRate {

    /// 把「当前走子方视角」的评估转换为「红方视角」的 centipawn 与胜率。
    /// - Parameters:
    ///   - result: 引擎搜索结果（scoreCp / mateIn 站在 sideToMove 视角）。
    ///   - sideToMove: 该评估对应局面的走子方。
    /// - Returns: (红方视角分值文本, 红方胜率0...1, 是否杀棋)
    static func redPerspective(result: SearchResult, sideToMove: Side) -> (scoreText: String, redWinProb: Double) {
        let sign: Int = sideToMove == .red ? 1 : -1

        if let mate = result.mateIn {
            // mate>0 表示走子方能将杀
            let redMate = mate * sign
            let prob = redMate > 0 ? 1.0 : 0.0
            let txt = redMate > 0 ? "红 #\(abs(redMate))" : "黑 #\(abs(redMate))"
            return (txt, prob)
        }

        let cp = (result.scoreCp ?? 0) * sign  // 红方视角厘兵
        let prob = winProbability(cp: cp)
        let txt = String(format: "%+d", cp)
        return (txt, prob)
    }

    /// Stockfish 系常用的 cp→胜率 sigmoid 近似。
    /// p = 1 / (1 + 10^(-cp/400))
    static func winProbability(cp: Int) -> Double {
        let x = Double(cp) / 400.0
        return 1.0 / (1.0 + pow(10.0, -x))
    }
}
