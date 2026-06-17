//
//  XiangqiModel.swift
//  XiangqiApp
//
//  中国象棋核心数据模型：棋子定义、棋盘状态、坐标与 FEN/UCI 转换、走子规则校验。
//
//  坐标约定（与 UCI / FEN 对齐）：
//   - 棋盘 9 列(file: a..i) × 10 行(rank: 0..9)。
//   - 内部用 row(0..9) / col(0..8) 表示，row 0 在屏幕顶部 = FEN 第一段(黑方底线 rank9)。
//   - 即 UCI rank = 9 - row，UCI file = col（a..i）。
//

import Foundation

/// 棋子颜色（红先行）。
enum Side {
    case red, black
    var opposite: Side { self == .red ? .black : .red }
}

/// 棋子兵种。
enum PieceKind: Hashable {
    case rook    // 车 R/r
    case knight  // 马 N/n
    case cannon  // 炮 C/c
    case bishop  // 相/象 B/b
    case advisor // 仕/士 A/a
    case king    // 帅/将 K/k
    case pawn    // 兵/卒 P/p
}

/// 一枚棋子。
struct Piece: Equatable {
    let kind: PieceKind
    let side: Side

    /// FEN 字符：红方大写，黑方小写。
    var fenChar: Character {
        let base: Character
        switch kind {
        case .rook: base = "r"
        case .knight: base = "n"
        case .cannon: base = "c"
        case .bishop: base = "b"
        case .advisor: base = "a"
        case .king: base = "k"
        case .pawn: base = "p"
        }
        return side == .red ? Character(base.uppercased()) : base
    }

    /// 棋盘上显示的汉字。
    var displayName: String {
        switch (kind, side) {
        case (.rook, .red): return "车";    case (.rook, .black): return "車"
        case (.knight, .red): return "马";  case (.knight, .black): return "馬"
        case (.cannon, .red): return "炮";  case (.cannon, .black): return "砲"
        case (.bishop, .red): return "相";  case (.bishop, .black): return "象"
        case (.advisor, .red): return "仕"; case (.advisor, .black): return "士"
        case (.king, .red): return "帅";    case (.king, .black): return "将"
        case (.pawn, .red): return "兵";    case (.pawn, .black): return "卒"
        }
    }

    static func from(fenChar c: Character) -> Piece? {
        let side: Side = c.isUppercase ? .red : .black
        let kind: PieceKind
        switch Character(c.lowercased()) {
        case "r": kind = .rook
        case "n": kind = .knight
        case "c": kind = .cannon
        case "b": kind = .bishop
        case "a": kind = .advisor
        case "k": kind = .king
        case "p": kind = .pawn
        default: return nil
        }
        return Piece(kind: kind, side: side)
    }
}

/// 棋盘格子坐标。row 0 在顶部，col 0 在左侧。
struct Square: Equatable, Hashable {
    var row: Int  // 0..9
    var col: Int  // 0..8

    var isValid: Bool { row >= 0 && row <= 9 && col >= 0 && col <= 8 }
}

/// 棋局状态：棋盘、走子方，并提供合法着法生成与 FEN/UCI 转换。
struct GameState {
    /// board[row][col]，nil 表示空格。
    var board: [[Piece?]]
    var sideToMove: Side

    init() {
        board = Array(repeating: Array(repeating: nil, count: 9), count: 10)
        sideToMove = .red
        setupStartPosition()
    }

    mutating func setupStartPosition() {
        let start = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR"
        load(fenBoard: start)
        sideToMove = .red
    }

    /// 仅解析 FEN 棋盘段（不含走子方等）。
    mutating func load(fenBoard: String) {
        board = Array(repeating: Array(repeating: nil, count: 9), count: 10)
        let rows = fenBoard.split(separator: "/")
        for (r, rowStr) in rows.enumerated() where r < 10 {
            var c = 0
            for ch in rowStr {
                if let digit = ch.wholeNumberValue {
                    c += digit
                } else if let piece = Piece.from(fenChar: ch) {
                    if c < 9 { board[r][c] = piece }
                    c += 1
                }
            }
        }
    }

    /// 解析完整 FEN（含走子方）。失败返回 false 且不修改自身。
    /// 例： "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
    @discardableResult
    mutating func loadFullFEN(_ fen: String) -> Bool {
        let trimmed = fen.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard let boardPart = parts.first else { return false }
        let rowCount = boardPart.split(separator: "/").count
        guard rowCount == 10 else { return false }
        load(fenBoard: String(boardPart))
        if parts.count >= 2 {
            sideToMove = (parts[1] == "b") ? .black : .red
        } else {
            sideToMove = .red
        }
        return true
    }


    func piece(at sq: Square) -> Piece? {
        guard sq.isValid else { return nil }
        return board[sq.row][sq.col]
    }

    // MARK: - 棋盘朝向

    /// 返回把棋盘整体旋转 180° 后的棋盘（row/col 同时镜像）。
    /// 用于将「反向朝向」的局面归一化到标准朝向（红方底线在 row 9）。
    static func rotated180(_ b: [[Piece?]]) -> [[Piece?]] {
        var out = Array(repeating: Array<Piece?>(repeating: nil, count: 9), count: 10)
        for r in 0..<10 {
            for c in 0..<9 {
                out[9 - r][8 - c] = b[r][c]
            }
        }
        return out
    }

    /// 判断该棋盘是否为标准朝向（红帅在下三行九宫、黑将在上三行九宫）。
    /// 用于导入时判断是否需要旋转归一化。返回 nil 表示无法判定（缺将）。
    static func isStandardOrientation(_ b: [[Piece?]]) -> Bool? {
        var redKing: Square?
        var blackKing: Square?
        for r in 0..<10 {
            for c in 0..<9 {
                if let p = b[r][c], p.kind == .king {
                    if p.side == .red { redKing = Square(row: r, col: c) }
                    else { blackKing = Square(row: r, col: c) }
                }
            }
        }
        guard let rk = redKing, let bk = blackKing else { return nil }
        // 标准朝向：红帅在下方(row 7..9)，黑将在上方(row 0..2)
        let standard = rk.row >= 7 && bk.row <= 2
        let flipped = rk.row <= 2 && bk.row >= 7
        if standard { return true }
        if flipped { return false }
        return nil
    }

    // MARK: - 局面合法性校验

    /// 校验棋盘上棋子位置是否合理。返回 nil 表示合理，否则返回错误描述。
    /// 检查项：双方各且仅有一个将、将帅在九宫内、仕/相/兵在合理区域、子力数量上限、两将不照面。
    func validationError() -> String? {
        var counts: [Side: [PieceKind: Int]] = [.red: [:], .black: [:]]

        for r in 0..<10 {
            for c in 0..<9 {
                guard let p = board[r][c] else { continue }
                let sq = Square(row: r, col: c)
                counts[p.side]![p.kind, default: 0] += 1

                switch p.kind {
                case .king:
                    if !inPalaceCheck(sq, side: p.side) {
                        return "\(sideName(p.side))将帅不在九宫内"
                    }
                case .advisor:
                    if !inPalaceCheck(sq, side: p.side) {
                        return "\(sideName(p.side))士仕不在九宫内"
                    }
                case .bishop:
                    if !bishopValidRow(sq, side: p.side) {
                        return "\(sideName(p.side))相象位置不合理"
                    }
                case .pawn:
                    if !pawnValidRow(sq, side: p.side) {
                        return "\(sideName(p.side))兵卒位置不合理"
                    }
                default:
                    break
                }
            }
        }

        let limits: [PieceKind: Int] = [
            .king: 1, .advisor: 2, .bishop: 2,
            .knight: 2, .rook: 2, .cannon: 2, .pawn: 5
        ]
        for side in [Side.red, .black] {
            for (kind, maxN) in limits {
                let n = counts[side]![kind, default: 0]
                if kind == .king {
                    if n != 1 { return "\(sideName(side))必须且仅有一个将帅" }
                } else if n > maxN {
                    return "\(sideName(side))\(kindName(kind))数量过多（\(n) > \(maxN)）"
                }
            }
        }

        // 两将不可照面
        if let rk = kingSquare(side: .red), let bk = kingSquare(side: .black),
           rk.col == bk.col {
            let lo = min(rk.row, bk.row) + 1
            let hi = max(rk.row, bk.row)
            var blocked = false
            for r in lo..<hi where board[r][rk.col] != nil { blocked = true; break }
            if !blocked { return "红黑双将照面（白脸将）" }
        }

        return nil
    }

    private func inPalaceCheck(_ sq: Square, side: Side) -> Bool {
        guard sq.col >= 3, sq.col <= 5 else { return false }
        if side == .red { return sq.row >= 7 && sq.row <= 9 }
        return sq.row >= 0 && sq.row <= 2
    }

    private func bishopValidRow(_ sq: Square, side: Side) -> Bool {
        // 相/象不可过河，且只能停在固定的 7 个点位
        let redPoints: Set<[Int]> = [[9,2],[9,6],[7,0],[7,4],[7,8],[5,2],[5,6]]
        let blackPoints: Set<[Int]> = [[0,2],[0,6],[2,0],[2,4],[2,8],[4,2],[4,6]]
        let pt = [sq.row, sq.col]
        return side == .red ? redPoints.contains(pt) : blackPoints.contains(pt)
    }

    private func pawnValidRow(_ sq: Square, side: Side) -> Bool {
        // 红兵不可出现在 row 7..9（己方底三行），黑卒不可出现在 row 0..2
        if side == .red { return sq.row <= 6 }
        return sq.row >= 3
    }

    private func sideName(_ side: Side) -> String { side == .red ? "红方" : "黑方" }

    private func kindName(_ kind: PieceKind) -> String {
        switch kind {
        case .rook: return "车"
        case .knight: return "马"
        case .cannon: return "炮"
        case .bishop: return "相象"
        case .advisor: return "士仕"
        case .king: return "将帅"
        case .pawn: return "兵卒"
        }
    }

    // MARK: - FEN / UCI 转换

    /// 生成完整 FEN（含走子方），用于喂给引擎。
    func fen() -> String {
        var rowStrings: [String] = []
        for r in 0..<10 {
            var s = ""
            var empty = 0
            for c in 0..<9 {
                if let p = board[r][c] {
                    if empty > 0 { s += String(empty); empty = 0 }
                    s.append(p.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { s += String(empty) }
            rowStrings.append(s)
        }
        let boardPart = rowStrings.joined(separator: "/")
        let side = sideToMove == .red ? "w" : "b"
        return "\(boardPart) \(side) - - 0 1"
    }

    /// 把内部坐标转为 UCI 文件字符（a..i）+ 行号（0..9）。
    static func uciSquare(_ sq: Square) -> String {
        let file = Character(UnicodeScalar(UInt8(97 + sq.col)))   // 'a' + col
        let rank = 9 - sq.row
        return "\(file)\(rank)"
    }

    static func square(fromUCI s: Substring) -> Square? {
        let chars = Array(s)
        guard chars.count == 2,
              let fileVal = chars[0].asciiValue, fileVal >= 97, fileVal <= 105,
              let rank = chars[1].wholeNumberValue else { return nil }
        let col = Int(fileVal) - 97
        let row = 9 - rank
        return Square(row: row, col: col)
    }

    /// 把一步着法转为 UCI，例如 "h2e2"。
    static func uciMove(from: Square, to: Square) -> String {
        uciSquare(from) + uciSquare(to)
    }

    /// 解析引擎返回的 UCI 着法为起止坐标。
    static func parseUCIMove(_ move: String) -> (from: Square, to: Square)? {
        guard move.count == 4 else { return nil }
        let s = Array(move)
        guard let from = square(fromUCI: Substring(String(s[0...1]))),
              let to = square(fromUCI: Substring(String(s[2...3]))) else { return nil }
        return (from, to)
    }

    // MARK: - 落子

    /// 执行一步着法（不做合法性校验，调用方应先校验）。
    mutating func apply(from: Square, to: Square) {
        guard from.isValid, to.isValid else { return }
        board[to.row][to.col] = board[from.row][from.col]
        board[from.row][from.col] = nil
        sideToMove = sideToMove.opposite
    }
}
