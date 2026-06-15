//
//  SoundManager.swift
//  XiangqiApp
//
//  对弈音效：走棋、将军、胜利。使用系统音效，无需打包音频资源。
//

import AudioToolbox

enum GameSound {
    /// 走棋 / 落子。
    case move
    /// 将军。
    case check
    /// 胜利 / 对局结束。
    case win

    /// 对应的系统音效 ID（SystemSoundID）。
    fileprivate var systemSoundID: SystemSoundID {
        switch self {
        case .move: return 1104   // 键盘点击声，短促清脆，适合落子
        case .check: return 1005  // 提示音，用于将军
        case .win: return 1025    // 完成音，用于胜利
        }
    }
}

enum SoundManager {
    /// 是否启用音效（由设置控制）。
    @MainActor static var enabled: Bool { AppSettings.shared.soundEnabled }

    @MainActor static func play(_ sound: GameSound) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(sound.systemSoundID)
    }
}
