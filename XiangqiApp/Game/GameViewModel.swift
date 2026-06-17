//
//  GameViewModel.swift
//  XiangqiApp
//
//  对弈控制器：管理棋局状态、玩家交互、调用 Pikafish 走 AI 的应招。
//  支持：人机对弈、摆棋编辑、实时胜率评估、自动走一步、FEN 导入。
//

import Foundation
import Combine

@MainActor
final class GameViewModel: ObservableObject {

    @Published private(set) var state = GameState()
    /// 当前选中的格子。
    @Published var selected: Square?
    /// 选中棋子的合法落点。
    @Published private(set) var legalTargets: [Square] = []
    /// 最近一步着法（起止），用于高亮。
    @Published private(set) var lastMove: (from: Square, to: Square)?
    /// 引擎是否就绪。
    @Published private(set) var engineReady = false
    /// AI 是否思考中。
    @Published private(set) var aiThinking = false
    /// 对局结果提示（nil 表示进行中）。
    @Published var resultText: String?
    /// 状态行文案。
    @Published var statusText = "点击「启动引擎」开始"

    // MARK: - 胜率评估
    /// 红方胜率 0...1。
    @Published private(set) var redWinProb: Double = 0.5
    /// 红方视角分值文本（如 "+35" 或 "红 #3"）。
    @Published private(set) var scoreText: String = "--"
    /// 是否正在评估当前局面。
    @Published private(set) var evaluating = false

    // MARK: - 摆棋编辑
    /// 是否处于摆棋编辑模式。
    @Published var isEditing = false
    /// 当前从面板选中、待放置的棋子（nil 表示删除模式）。
    @Published var paletteSelection: Piece?

    /// 玩家执子方（可在摆棋后切换）。
    @Published var playerSide: Side = .red

    /// 电脑执方（取自设置）。off 时不自动应招。
    private var engineSide: EngineSide { settings.engineSide }

    /// 棋盘是否翻转显示（红上黑下）。可随时手动切换，与执方/电脑执方无关。
    /// 默认根据玩家执方初始化（执黑则翻转，使己方在底部），之后用户可自由翻转。
    @Published var boardFlipped: Bool = false

    /// 手动翻转棋盘（红上黑下 ↔ 红下黑上）。
    func toggleBoardFlip() {
        boardFlipped.toggle()
    }

    /// 自动走棋：开启后红黑双方都由引擎按最优着法走。
    @Published var autoPlay = false {
        didSet {
            guard autoPlay != oldValue else { return }
            if autoPlay { startAutoPlay() }
        }
    }

    private let engine = PikafishEngine()
    private let settings = AppSettings.shared
    /// 记录从开局以来的全部 UCI 着法，用于 position startpos moves。
    /// 摆棋/FEN 导入后清空，改用 setPosition(fen:)。
    private var moveHistory: [String] = []
    /// 当摆棋/导入产生自定义起始局面时记录其 FEN；nil 表示标准开局。
    private var customStartFEN: String?

    // MARK: - 悔棋历史

    /// 每走一步前的局面快照（含状态与最近一步高亮），用于逐步回退。
    private struct Snapshot {
        let state: GameState
        let lastMove: (from: Square, to: Square)?
        let moveCount: Int
    }
    /// 局面快照栈：栈底为初始局面（新局/摆棋/导入后的起点）。
    @Published private(set) var undoStack: [Snapshot] = []

    /// 是否可悔棋（已走至少一步）。
    var canUndo: Bool { !undoStack.isEmpty }

    /// 在「即将走子」前压入当前局面快照。
    private func pushSnapshot() {
        undoStack.append(Snapshot(state: state, lastMove: lastMove, moveCount: moveHistory.count))
    }

    /// 重置悔棋历史（新局/摆棋/导入时调用，确立新的回退底线）。
    private func resetHistory() {
        undoStack.removeAll()
    }

    /// 悔棋一步：回退到上一手之前的局面（无论红黑）。
    func undoMove() {
        guard !isEditing, !aiThinking, canUndo else { return }
        autoPlay = false
        let snap = undoStack.removeLast()
        restore(snap)
    }

    /// 悔棋到底：回退到初始局面（新局或摆棋/导入起点）。
    func undoAll() {
        guard !isEditing, !aiThinking, canUndo else { return }
        autoPlay = false
        let snap = undoStack.first!
        undoStack.removeAll()
        restore(snap)
    }

    private func restore(_ snap: Snapshot) {
        state = snap.state
        lastMove = snap.lastMove
        if moveHistory.count > snap.moveCount {
            moveHistory.removeLast(moveHistory.count - snap.moveCount)
        }
        resultText = nil
        clearSelection()
        statusText = engineReady ? turnPrompt() : "请启动引擎"
        Task { await evaluatePosition() }
    }

    // MARK: - 引擎

    func startEngine() {
        statusText = "启动引擎中…"
        let path = Bundle.main.path(forResource: "pikafish", ofType: "nnue")
        engine.start(networkPath: path)
        Task {
            for _ in 0..<100 {
                if engine.isReady { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            engineReady = engine.isReady
            statusText = engineReady ? turnPrompt() : "引擎未就绪"
            if engineReady {
                await evaluatePosition()
                maybeEngineMove()
            }
        }
    }

    // MARK: - 玩家交互

    /// 处理玩家点击某格。
    func tap(_ sq: Square) {
        if isEditing {
            editTap(sq)
            return
        }
        guard resultText == nil else { return }
        guard !aiThinking, !autoPlay, state.sideToMove == playerSide else { return }

        if let sel = selected {
            if legalTargets.contains(sq) {
                performPlayerMove(from: sel, to: sq)
                return
            }
            if let p = state.piece(at: sq), p.side == playerSide {
                select(sq)
            } else {
                clearSelection()
            }
        } else if let p = state.piece(at: sq), p.side == playerSide {
            select(sq)
        }
    }

    private func select(_ sq: Square) {
        selected = sq
        legalTargets = state.legalMoves(from: sq)
    }

    private func clearSelection() {
        selected = nil
        legalTargets = []
    }

    private func performPlayerMove(from: Square, to: Square) {
        pushSnapshot()
        let uci = GameState.uciMove(from: from, to: to)
        state.apply(from: from, to: to)
        moveHistory.append(uci)
        lastMove = (from, to)
        clearSelection()
        SoundManager.play(.move)

        if checkGameOver() { return }

        if engineSide != .off {
            statusText = "AI 思考中…"
            askAI()
        } else {
            statusText = turnPrompt()
            Task { await evaluatePosition() }
        }
    }

    // MARK: - AI

    /// 若当前走子方应由电脑执子，则自动应招一步。
    private func maybeEngineMove() {
        guard engineReady, resultText == nil, !aiThinking, !autoPlay, !isEditing else { return }
        switch engineSide {
        case .red where state.sideToMove == .red,
             .black where state.sideToMove == .black:
            askAI()
        default:
            break
        }
    }

    /// 根据电脑执方推导玩家执方：电脑执红则玩家执黑，反之亦然；关闭时用 fallback。
    private func preferredPlayerSide(default fallback: Side) -> Side {
        switch engineSide {
        case .red: return .black
        case .black: return .red
        case .off: return fallback
        }
    }

    /// 设置页修改「电脑执方」后调用：更新玩家执方与棋盘朝向，并在轮到电脑时自动应招。
    func applyEngineSideSetting() {
        guard !isEditing else { return }
        playerSide = preferredPlayerSide(default: playerSide)
        objectWillChange.send()
        maybeEngineMove()
    }

    private func askAI() {
        guard engineReady else {
            statusText = "引擎未就绪，无法走 AI"
            return
        }
        aiThinking = true
        applyPositionToEngine()
        Task {
            let result = await engine.search(moveTimeMs: settings.thinkTimeMs)
            applyAIMove(result.bestMove)
            await evaluatePosition()
        }
    }

    /// 让引擎替「当前走子方」走一步（即使是玩家这一侧）。
    func autoMoveOnce() {
        guard engineReady, resultText == nil, !aiThinking else { return }
        aiThinking = true
        statusText = "电脑思考中…"
        clearSelection()
        applyPositionToEngine()
        Task {
            let result = await engine.search(moveTimeMs: settings.thinkTimeMs)
            applyEngineMove(result.bestMove, continueAI: false)
            await evaluatePosition()
        }
    }

    /// 启动自动走棋循环：红黑双方均由引擎按最优着法走。
    private func startAutoPlay() {
        guard engineReady, resultText == nil, !aiThinking else { return }
        aiThinking = true
        statusText = "自动走棋中…"
        clearSelection()
        applyPositionToEngine()
        Task {
            let result = await engine.search(moveTimeMs: settings.thinkTimeMs)
            applyEngineMove(result.bestMove, continueAI: true)
            await evaluatePosition()
        }
    }

    private func applyAIMove(_ move: String) {
        applyEngineMove(move, continueAI: false)
        // 应招后若仍轮到电脑（如双方都设为电脑的极端情况一般不会发生），交给 maybeEngineMove 兜底。
    }

    private func applyEngineMove(_ move: String, continueAI: Bool) {
        aiThinking = false
        guard let (from, to) = GameState.parseUCIMove(move) else {
            statusText = "引擎返回无效着法：\(move)"
            return
        }
        pushSnapshot()
        state.apply(from: from, to: to)
        moveHistory.append(move)
        lastMove = (from, to)
        SoundManager.play(.move)

        if checkGameOver() { return }
        statusText = turnPrompt()

        if continueAI && autoPlay {
            startAutoPlay()
        }
    }

    // MARK: - 局面评估

    /// 评估当前局面更新胜率条（浅层搜索，独立于对弈搜索）。
    func evaluatePosition() async {
        guard engineReady, resultText == nil else { return }
        evaluating = true
        applyPositionToEngine()
        let result = await engine.search(depth: 12)
        let r = WinRate.redPerspective(result: result, sideToMove: state.sideToMove)
        scoreText = r.scoreText
        redWinProb = r.redWinProb
        evaluating = false
    }

    /// 根据是否有自定义起始局面，把当前局面同步给引擎。
    private func applyPositionToEngine() {
        if let fen = customStartFEN {
            engine.setPosition(fen: fen, moves: moveHistory)
        } else {
            engine.setStartPosition(moves: moveHistory)
        }
    }

    // MARK: - 摆棋编辑

    /// 进入摆棋模式。
    func enterEditing() {
        isEditing = true
        paletteSelection = nil
        clearSelection()
        resultText = nil
        statusText = "摆棋中：选子放置，点子删除"
    }

    /// 退出摆棋模式并应用局面。校验棋子位置，不合理返回错误描述（不退出摆棋）。
    @discardableResult
    func finishEditing(sideToMove: Side) -> String? {
        var probe = state
        probe.sideToMove = sideToMove
        if let err = probe.validationError() {
            statusText = "摆棋错误：\(err)"
            return err
        }
        state.sideToMove = sideToMove
        playerSide = sideToMove
        boardFlipped = (sideToMove == .black)
        isEditing = false
        paletteSelection = nil
        moveHistory = []
        resetHistory()
        lastMove = nil
        let fen = state.fen()
        customStartFEN = fen
        statusText = engineReady ? turnPrompt() : "请启动引擎"
        Task { await evaluatePosition(); maybeEngineMove() }
        return nil
    }

    /// 清空棋盘（仅保留双方将帅在原位，方便摆棋）。
    func clearBoard() {
        state.board = Array(repeating: Array(repeating: nil, count: 9), count: 10)
        state.board[0][4] = Piece(kind: .king, side: .black)
        state.board[9][4] = Piece(kind: .king, side: .red)
        lastMove = nil
    }

    private func editTap(_ sq: Square) {
        guard sq.isValid else { return }
        if let piece = paletteSelection {
            state.board[sq.row][sq.col] = piece
        } else {
            // 删除模式：清空该格
            state.board[sq.row][sq.col] = nil
        }
    }

    // MARK: - FEN 导入

    /// 导入完整 FEN。成功返回 nil，失败返回错误描述。
    /// - Parameter sideOverride: 若指定，则覆盖 FEN 中的走子方（支持选择红先/黑先）。
    ///
    /// 自动朝向归一化：若识别/粘贴的棋盘是反向朝向（红帅在上方），
    /// 先整体旋转 180° 回标准朝向，避免「棋子位置不合理」误报。
    @discardableResult
    func importFEN(_ fen: String, sideOverride: Side? = nil) -> String? {
        var newState = GameState()
        guard newState.loadFullFEN(fen) else { return "FEN 格式无效" }
        // 反向朝向则旋转归一化到标准朝向（红帅在下方）
        if GameState.isStandardOrientation(newState.board) == false {
            newState.board = GameState.rotated180(newState.board)
        }
        if let s = sideOverride { newState.sideToMove = s }
        if let err = newState.validationError() { return "棋子位置不合理：\(err)" }
        state = newState
        playerSide = preferredPlayerSide(default: state.sideToMove)
        boardFlipped = (playerSide == .black)
        moveHistory = []
        resetHistory()
        customStartFEN = state.fen()
        lastMove = nil
        resultText = nil
        isEditing = false
        clearSelection()
        statusText = engineReady ? turnPrompt() : "请启动引擎"
        Task { await evaluatePosition(); maybeEngineMove() }
        return nil
    }

    /// 将 FEN 局面载入摆棋模式（不校验，供识别结果不合理时人工修正）。
    /// 同样做朝向归一化，便于人工在标准朝向下修正。
    func loadFENForEditing(_ fen: String) {
        var newState = GameState()
        guard newState.loadFullFEN(fen) else { return }
        if GameState.isStandardOrientation(newState.board) == false {
            newState.board = GameState.rotated180(newState.board)
        }
        state = newState
        moveHistory = []
        resetHistory()
        customStartFEN = nil
        lastMove = nil
        resultText = nil
        autoPlay = false
        isEditing = true
        paletteSelection = nil
        clearSelection()
    }

    // MARK: - 胜负判断

    @discardableResult
    private func checkGameOver() -> Bool {
        let toMove = state.sideToMove
        if state.hasNoLegalMoves(side: toMove) {
            let winner: Side = toMove.opposite
            resultText = winner == .red ? "红方获胜" : "黑方获胜"
            statusText = resultText!
            clearSelection()
            SoundManager.play(.win)
            return true
        }
        if state.isKingInCheckOrFacing(side: toMove) {
            statusText = "将军！" + (toMove == .red ? "红方应将" : "黑方应将")
            SoundManager.play(.check)
        }
        return false
    }

    private func turnPrompt() -> String {
        state.sideToMove == .red ? "红方走棋" : "黑方走棋"
    }

    // MARK: - 新局

    func newGame() {
        state = GameState()
        moveHistory = []
        resetHistory()
        customStartFEN = nil
        playerSide = preferredPlayerSide(default: .red)
        boardFlipped = (playerSide == .black)
        lastMove = nil
        resultText = nil
        isEditing = false
        paletteSelection = nil
        autoPlay = false
        clearSelection()
        redWinProb = 0.5
        scoreText = "--"
        statusText = engineReady ? turnPrompt() : "点击「启动引擎」开始"
        if engineReady { Task { await evaluatePosition(); maybeEngineMove() } }
    }
}
