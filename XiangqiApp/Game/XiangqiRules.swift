//
//  XiangqiRules.swift
//  XiangqiApp
//
//  走子规则校验与合法着法生成。规则采用经典中国象棋规则：
//  车/马/炮/相(象)/仕(士)/帅(将)/兵(卒)，含蹩马腿、塞象眼、九宫、过河、飞将。
//

import Foundation

extension GameState {

    /// 生成某格棋子的全部「伪合法」着法（不考虑走子后是否被将军）。
    func pseudoLegalMoves(from sq: Square) -> [Square] {
        guard let p = piece(at: sq) else { return [] }
        switch p.kind {
        case .rook:    return rookMoves(from: sq, side: p.side)
        case .cannon:  return cannonMoves(from: sq, side: p.side)
        case .knight:  return knightMoves(from: sq, side: p.side)
        case .bishop:  return bishopMoves(from: sq, side: p.side)
        case .advisor: return advisorMoves(from: sq, side: p.side)
        case .king:    return kingMoves(from: sq, side: p.side)
        case .pawn:    return pawnMoves(from: sq, side: p.side)
        }
    }

    /// 生成某格棋子的全部「合法」着法（走子后己方不被将军 / 不照面）。
    func legalMoves(from sq: Square) -> [Square] {
        guard let p = piece(at: sq) else { return [] }
        return pseudoLegalMoves(from: sq).filter { dest in
            var next = self
            next.board[dest.row][dest.col] = next.board[sq.row][sq.col]
            next.board[sq.row][sq.col] = nil
            return !next.isKingInCheckOrFacing(side: p.side)
        }
    }

    /// 判断一步着法是否合法。
    func isLegalMove(from: Square, to: Square) -> Bool {
        legalMoves(from: from).contains(to)
    }

    // MARK: - 各兵种

    private func canLand(_ sq: Square, side: Side) -> Bool {
        guard sq.isValid else { return false }
        if let target = piece(at: sq) { return target.side != side }
        return true
    }

    private func rookMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        for (dr, dc) in dirs {
            var r = sq.row + dr, c = sq.col + dc
            while r >= 0, r <= 9, c >= 0, c <= 8 {
                if let target = board[r][c] {
                    if target.side != side { result.append(Square(row: r, col: c)) }
                    break
                }
                result.append(Square(row: r, col: c))
                r += dr; c += dc
            }
        }
        return result
    }

    private func cannonMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        for (dr, dc) in dirs {
            var r = sq.row + dr, c = sq.col + dc
            // 第一阶段：未越过炮架前，可走空格
            while r >= 0, r <= 9, c >= 0, c <= 8, board[r][c] == nil {
                result.append(Square(row: r, col: c))
                r += dr; c += dc
            }
            // 越过炮架后，寻找第一个棋子作为可吃目标
            r += dr; c += dc
            while r >= 0, r <= 9, c >= 0, c <= 8 {
                if let target = board[r][c] {
                    if target.side != side { result.append(Square(row: r, col: c)) }
                    break
                }
                r += dr; c += dc
            }
        }
        return result
    }

    private func knightMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        // (目标偏移, 蹩腿位置偏移)
        let moves: [((Int, Int), (Int, Int))] = [
            ((-2, -1), (-1, 0)), ((-2, 1), (-1, 0)),
            ((2, -1), (1, 0)),   ((2, 1), (1, 0)),
            ((-1, -2), (0, -1)), ((1, -2), (0, -1)),
            ((-1, 2), (0, 1)),   ((1, 2), (0, 1)),
        ]
        for (off, leg) in moves {
            let legSq = Square(row: sq.row + leg.0, col: sq.col + leg.1)
            guard legSq.isValid, board[legSq.row][legSq.col] == nil else { continue } // 蹩马腿
            let dest = Square(row: sq.row + off.0, col: sq.col + off.1)
            if canLand(dest, side: side) { result.append(dest) }
        }
        return result
    }

    private func bishopMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        let offs: [(Int, Int)] = [(-2, -2), (-2, 2), (2, -2), (2, 2)]
        for (dr, dc) in offs {
            let dest = Square(row: sq.row + dr, col: sq.col + dc)
            let eye = Square(row: sq.row + dr / 2, col: sq.col + dc / 2)
            guard dest.isValid, eye.isValid, board[eye.row][eye.col] == nil else { continue } // 塞象眼
            // 相/象不可过河
            if side == .red && dest.row < 5 { continue }
            if side == .black && dest.row > 4 { continue }
            if canLand(dest, side: side) { result.append(dest) }
        }
        return result
    }

    private func advisorMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        let offs: [(Int, Int)] = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dr, dc) in offs {
            let dest = Square(row: sq.row + dr, col: sq.col + dc)
            guard dest.isValid, inPalace(dest, side: side) else { continue }
            if canLand(dest, side: side) { result.append(dest) }
        }
        return result
    }

    private func kingMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        let offs: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in offs {
            let dest = Square(row: sq.row + dr, col: sq.col + dc)
            guard dest.isValid, inPalace(dest, side: side) else { continue }
            if canLand(dest, side: side) { result.append(dest) }
        }
        return result
    }

    private func pawnMoves(from sq: Square, side: Side) -> [Square] {
        var result: [Square] = []
        // 红方向上(row 减小)，黑方向下(row 增大)
        let forward = side == .red ? -1 : 1
        let crossedRiver = side == .red ? sq.row <= 4 : sq.row >= 5
        let fwd = Square(row: sq.row + forward, col: sq.col)
        if canLand(fwd, side: side) { result.append(fwd) }
        if crossedRiver {
            for dc in [-1, 1] {
                let side2 = Square(row: sq.row, col: sq.col + dc)
                if canLand(side2, side: side) { result.append(side2) }
            }
        }
        return result
    }

    private func inPalace(_ sq: Square, side: Side) -> Bool {
        guard sq.col >= 3, sq.col <= 5 else { return false }
        if side == .red { return sq.row >= 7 && sq.row <= 9 }
        return sq.row >= 0 && sq.row <= 2
    }

    // MARK: - 将军 / 照面判断

    func kingSquare(side: Side) -> Square? {
        for r in 0..<10 {
            for c in 0..<9 {
                if let p = board[r][c], p.kind == .king, p.side == side {
                    return Square(row: r, col: c)
                }
            }
        }
        return nil
    }

    /// 该方将帅是否被对方将军，或两将照面。
    func isKingInCheckOrFacing(side: Side) -> Bool {
        guard let myKing = kingSquare(side: side) else { return true }
        // 飞将：两将同列且中间无子
        if let oppKing = kingSquare(side: side.opposite), oppKing.col == myKing.col {
            let lo = min(oppKing.row, myKing.row) + 1
            let hi = max(oppKing.row, myKing.row)
            var blocked = false
            for r in lo..<hi where board[r][myKing.col] != nil { blocked = true; break }
            if !blocked { return true }
        }
        // 被任意对方子的伪合法着法攻击
        for r in 0..<10 {
            for c in 0..<9 {
                if let p = board[r][c], p.side == side.opposite {
                    if pseudoLegalAttacks(from: Square(row: r, col: c), piece: p).contains(myKing) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// 仅用于将军检测的攻击格（与伪合法着法等价，但避免递归调用 king 照面逻辑）。
    private func pseudoLegalAttacks(from sq: Square, piece p: Piece) -> [Square] {
        switch p.kind {
        case .rook:    return rookMoves(from: sq, side: p.side)
        case .cannon:  return cannonMoves(from: sq, side: p.side)
        case .knight:  return knightMoves(from: sq, side: p.side)
        case .bishop:  return bishopMoves(from: sq, side: p.side)
        case .advisor: return advisorMoves(from: sq, side: p.side)
        case .king:    return kingMoves(from: sq, side: p.side)
        case .pawn:    return pawnMoves(from: sq, side: p.side)
        }
    }

    /// 该方是否已无合法着法（将死或困毙）。
    func hasNoLegalMoves(side: Side) -> Bool {
        for r in 0..<10 {
            for c in 0..<9 {
                if let p = board[r][c], p.side == side {
                    if !legalMoves(from: Square(row: r, col: c)).isEmpty { return false }
                }
            }
        }
        return true
    }
}
