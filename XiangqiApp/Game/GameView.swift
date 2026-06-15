//
//  GameView.swift
//  XiangqiApp
//
//  主对弈界面：标题、胜率条、棋盘、操作按钮、摆棋面板、FEN/图片导入、设置。
//

import SwiftUI

struct GameView: View {
    @StateObject private var vm = GameViewModel()
    @StateObject private var settings = AppSettings.shared

    @State private var showSettings = false
    @State private var showFENImport = false
    @State private var fenInput = ""
    @State private var fenError: String?
    @State private var showImagePicker = false
    @State private var recognizing = false
    @State private var visionError: String?
    /// 图片识别结果，待用户选择先走方后导入。
    @State private var recognizedFEN: String?
    @State private var showRecognizedSide = false

    var body: some View {
        VStack(spacing: 10) {
            Text("中国象棋")
                .font(.title2).bold()

            WinRateBar(redProb: vm.redWinProb, scoreText: vm.scoreText, evaluating: vm.evaluating)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                if vm.aiThinking || recognizing {
                    ProgressView().scaleEffect(0.8)
                }
                Text(recognizing ? "识别图片中…" : vm.statusText)
                    .font(.subheadline)
                    .foregroundColor(vm.resultText == nil ? .primary : .red)
            }

            BoardView(vm: vm)
                .padding(.horizontal, 4)

            if vm.isEditing {
                EditPalette(vm: vm)
            } else {
                controlButtons
            }

            if let err = visionError {
                Text(err).font(.caption).foregroundColor(.red)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in
                showImagePicker = false
                recognizeImage(image)
            }
        }
        .alert("导入 FEN", isPresented: $showFENImport) {
            TextField("粘贴 FEN", text: $fenInput)
            Button("红方先走") { doImportFEN(side: .red) }
            Button("黑方先走") { doImportFEN(side: .black) }
            Button("按 FEN 走子方") { doImportFEN(side: nil) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(fenError ?? "例：rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w")
        }
        .alert("识别成功，谁先走？", isPresented: $showRecognizedSide) {
            Button("红方先走") { applyRecognized(side: .red) }
            Button("黑方先走") { applyRecognized(side: .black) }
            Button("按识别走子方") { applyRecognized(side: nil) }
            Button("取消", role: .cancel) { recognizedFEN = nil }
        } message: {
            Text(recognizedFEN.map { "FEN：\($0)" } ?? "")
        }
    }

    private var controlButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if !vm.engineReady {
                    Button("启动引擎") { vm.startEngine() }
                        .buttonStyle(.borderedProminent)
                }
                Button("新局") { vm.newGame() }
                    .buttonStyle(.bordered)
                Button("电脑走一步") { vm.autoMoveOnce() }
                    .buttonStyle(.bordered)
                    .disabled(!vm.engineReady || vm.aiThinking || vm.resultText != nil || vm.autoPlay)
                Toggle("自动走棋", isOn: $vm.autoPlay)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .disabled(!vm.engineReady || vm.resultText != nil || vm.isEditing)
            }
            HStack(spacing: 12) {
                Button("摆棋") { vm.enterEditing() }
                    .buttonStyle(.bordered)
                Button("导入FEN") { fenInput = ""; fenError = nil; showFENImport = true }
                    .buttonStyle(.bordered)
                Button("图片识别") {
                    visionError = settings.visionConfigured ? nil : "请先在设置中填写接口"
                    if settings.visionConfigured { showImagePicker = true } else { showSettings = true }
                }
                .buttonStyle(.bordered)
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.top, 2)
    }

    private func doImportFEN(side: Side?) {
        if let err = vm.importFEN(fenInput, sideOverride: side) {
            fenError = err
            showFENImport = true
        } else {
            fenError = nil
        }
    }

    private func recognizeImage(_ image: UIImage) {
        recognizing = true
        visionError = nil
        Task {
            do {
                let fen = try await VisionService.recognizeFEN(from: image, settings: settings)
                recognizing = false
                recognizedFEN = fen
                showRecognizedSide = true
            } catch {
                recognizing = false
                visionError = "识别失败：\(error.localizedDescription)"
            }
        }
    }

    private func applyRecognized(side: Side?) {
        guard let fen = recognizedFEN else { return }
        if let err = vm.importFEN(fen, sideOverride: side) {
            vm.loadFENForEditing(fen)
            vm.statusText = "识别结果不合理：\(err)，已进入摆棋模式，请手动修正"
            visionError = nil
        } else {
            visionError = nil
        }
        recognizedFEN = nil
    }
}

// MARK: - 胜率条

private struct WinRateBar: View {
    let redProb: Double
    let scoreText: String
    let evaluating: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("红 \(Int((redProb * 100).rounded()))%")
                    .font(.caption).foregroundColor(.red)
                Spacer()
                Text(scoreText)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Spacer()
                Text("黑 \(Int(((1 - redProb) * 100).rounded()))%")
                    .font(.caption).foregroundColor(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.75))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.85))
                        .frame(width: geo.size.width * redProb)
                }
            }
            .frame(height: 10)
            .opacity(evaluating ? 0.5 : 1)
        }
    }
}

// MARK: - 摆棋面板

private struct EditPalette: View {
    @ObservedObject var vm: GameViewModel

    private let kinds: [PieceKind] = [.king, .advisor, .bishop, .knight, .rook, .cannon, .pawn]

    var body: some View {
        VStack(spacing: 8) {
            paletteRow(side: .red)
            paletteRow(side: .black)
            HStack(spacing: 8) {
                Button {
                    vm.paletteSelection = nil
                } label: {
                    Label("橡皮", systemImage: "eraser")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .tint(vm.paletteSelection == nil ? .accentColor : .gray)

                Button("清空") { vm.clearBoard() }
                    .buttonStyle(.bordered)

                Button("红先") { vm.finishEditing(sideToMove: .red) }
                    .buttonStyle(.borderedProminent).tint(.red)
                Button("黑先") { vm.finishEditing(sideToMove: .black) }
                    .buttonStyle(.borderedProminent).tint(.black)
            }
            .font(.footnote)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
    }

    private func paletteRow(side: Side) -> some View {
        HStack(spacing: 6) {
            ForEach(kinds, id: \.self) { kind in
                let piece = Piece(kind: kind, side: side)
                Button {
                    vm.paletteSelection = piece
                } label: {
                    PieceView(piece: piece, diameter: 34)
                        .overlay(
                            Circle().stroke(Color.accentColor,
                                            lineWidth: vm.paletteSelection == piece ? 3 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    GameView()
}
