//
//  BoardView.swift
//  XiangqiApp
//
//  9×10 中国象棋棋盘视图：网格线、河界、九宫斜线、棋子与点击交互。
//

import SwiftUI

struct BoardView: View {
    @ObservedObject var vm: GameViewModel

    // 棋盘内边距（留出半个格子放最外圈棋子）。
    private let margin: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let cols = 8  // 列间隔数（9 条竖线）
            let rows = 9  // 行间隔数（10 条横线）
            let usableW = geo.size.width - margin * 2
            let usableH = geo.size.height - margin * 2
            let cell = min(usableW / CGFloat(cols), usableH / CGFloat(rows))
            let boardW = cell * CGFloat(cols)
            let boardH = cell * CGFloat(rows)
            let originX = (geo.size.width - boardW) / 2
            let originY = (geo.size.height - boardH) / 2

            ZStack(alignment: .topLeading) {
                // 木色背景
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.94, green: 0.85, blue: 0.66))

                BoardGrid(cell: cell, originX: originX, originY: originY)
                    .stroke(Color(red: 0.35, green: 0.22, blue: 0.1), lineWidth: 1)

                // 高亮：最近一步着法
                if let last = vm.lastMove {
                    marker(at: last.from, cell: cell, ox: originX, oy: originY, color: .orange.opacity(0.25))
                    marker(at: last.to, cell: cell, ox: originX, oy: originY, color: .orange.opacity(0.35))
                }
                // 高亮：选中格
                if let sel = vm.selected {
                    marker(at: sel, cell: cell, ox: originX, oy: originY, color: .green.opacity(0.35))
                }
                // 摆棋模式边框提示
                if vm.isEditing {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                // 合法落点提示
                ForEach(Array(vm.legalTargets.enumerated()), id: \.offset) { _, t in
                    let center = point(t, cell: cell, ox: originX, oy: originY)
                    Circle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: cell * 0.28, height: cell * 0.28)
                        .position(center)
                }

                // 棋子
                ForEach(0..<10, id: \.self) { r in
                    ForEach(0..<9, id: \.self) { c in
                        if let p = vm.state.board[r][c] {
                            let center = point(Square(row: r, col: c), cell: cell, ox: originX, oy: originY)
                            PieceView(piece: p, diameter: cell * 0.82)
                                .position(center)
                        }
                    }
                }

                // 点击层
                ForEach(0..<10, id: \.self) { r in
                    ForEach(0..<9, id: \.self) { c in
                        let center = point(Square(row: r, col: c), cell: cell, ox: originX, oy: originY)
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: cell, height: cell)
                            .position(center)
                            .onTapGesture { vm.tap(Square(row: r, col: c)) }
                    }
                }
            }
        }
        .aspectRatio(9.0 / 10.0, contentMode: .fit)
    }

    private func point(_ sq: Square, cell: CGFloat, ox: CGFloat, oy: CGFloat) -> CGPoint {
        CGPoint(x: ox + CGFloat(sq.col) * cell, y: oy + CGFloat(sq.row) * cell)
    }

    private func marker(at sq: Square, cell: CGFloat, ox: CGFloat, oy: CGFloat, color: Color) -> some View {
        let center = point(sq, cell: cell, ox: ox, oy: oy)
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: cell * 0.9, height: cell * 0.9)
            .position(center)
    }
}

/// 绘制棋盘网格、河界缺口与九宫斜线。
private struct BoardGrid: Shape {
    let cell: CGFloat
    let originX: CGFloat
    let originY: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let ox = originX, oy = originY
        func pt(_ col: Int, _ row: Int) -> CGPoint {
            CGPoint(x: ox + CGFloat(col) * cell, y: oy + CGFloat(row) * cell)
        }

        // 10 条横线
        for r in 0...9 {
            path.move(to: pt(0, r))
            path.addLine(to: pt(8, r))
        }
        // 竖线：最左、最右贯通；中间在河界(row4-row5)断开
        for c in 0...8 {
            if c == 0 || c == 8 {
                path.move(to: pt(c, 0))
                path.addLine(to: pt(c, 9))
            } else {
                path.move(to: pt(c, 0))
                path.addLine(to: pt(c, 4))
                path.move(to: pt(c, 5))
                path.addLine(to: pt(c, 9))
            }
        }
        // 九宫斜线（上、下）
        path.move(to: pt(3, 0)); path.addLine(to: pt(5, 2))
        path.move(to: pt(5, 0)); path.addLine(to: pt(3, 2))
        path.move(to: pt(3, 7)); path.addLine(to: pt(5, 9))
        path.move(to: pt(5, 7)); path.addLine(to: pt(3, 9))

        return path
    }
}
