//
//  PieceView.swift
//  XiangqiApp
//
//  单枚棋子视图：圆形底 + 汉字，红黑双色。
//

import SwiftUI

struct PieceView: View {
    let piece: Piece
    let diameter: CGFloat

    private var color: Color {
        piece.side == .red ? Color(red: 0.78, green: 0.12, blue: 0.12)
                           : Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.98, green: 0.95, blue: 0.86))
                .overlay(Circle().stroke(color, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0.5, y: 1)
            Circle()
                .stroke(color.opacity(0.6), lineWidth: 1)
                .padding(diameter * 0.12)
            Text(piece.displayName)
                .font(.system(size: diameter * 0.5, weight: .bold))
                .foregroundColor(color)
        }
        .frame(width: diameter, height: diameter)
    }
}
