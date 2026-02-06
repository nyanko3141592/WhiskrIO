import Foundation
import AppKit
import CoreGraphics

/// カーソル周辺のスクリーンショットを取得するマネージャー
class ScreenshotManager {
    static let shared = ScreenshotManager()

    private init() {}

    // MARK: - Permission Handling

    /// 画面収録の権限があるかチェック
    func hasScreenRecordingPermission() -> Bool {
        // CGWindowListCreateImage を使って実際にキャプチャを試みることで権限を確認
        // 権限がない場合、空の画像または nil が返される
        let testRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let image = CGWindowListCreateImage(
            testRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return false
        }

        // 画像が実際にピクセルを含んでいるか確認
        return image.width > 0 && image.height > 0
    }

    /// 画面収録の権限をリクエスト（システム設定を開く）
    func requestScreenRecordingPermission() {
        // macOS 10.15以降では、CGWindowListCreateImage を呼び出すと
        // システムが自動的に権限ダイアログを表示する
        // ここでは設定画面を開くオプションを提供
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Screen Capture

    /// カーソル周辺のスクリーンショットをJPEG形式で取得
    /// - Parameters:
    ///   - radius: カーソルからの半径（ピクセル）。キャプチャサイズは radius * 2 の正方形
    ///   - quality: JPEG圧縮品質（0.0〜1.0）
    /// - Returns: JPEG形式の画像データ、失敗時はnil
    func captureAroundCursorJPEG(radius: Int = 400, quality: CGFloat = 0.7) -> Data? {
        guard hasScreenRecordingPermission() else {
            print("[ScreenshotManager] No screen recording permission")
            return nil
        }

        // カーソル位置を取得（スクリーン座標系）
        let mouseLocation = NSEvent.mouseLocation

        // マウス位置があるスクリーンを特定
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
              ?? NSScreen.main else {
            print("[ScreenshotManager] Could not determine screen")
            return nil
        }

        // スクリーン座標系からCoreGraphics座標系（Y軸反転）に変換
        let screenFrame = screen.frame
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height

        // CoreGraphics座標系でのカーソル位置
        let cgMouseY = mainScreenHeight - mouseLocation.y
        let cgMouseX = mouseLocation.x

        // キャプチャ領域を計算
        let captureSize = CGFloat(radius * 2)
        var captureRect = CGRect(
            x: cgMouseX - CGFloat(radius),
            y: cgMouseY - CGFloat(radius),
            width: captureSize,
            height: captureSize
        )

        // 画面外にはみ出る場合は調整
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        captureRect = captureRect.intersection(displayBounds)

        // 有効な領域がない場合
        guard captureRect.width > 0 && captureRect.height > 0 else {
            print("[ScreenshotManager] Invalid capture rect")
            return nil
        }

        // スクリーンショットを取得
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            print("[ScreenshotManager] Failed to create image")
            return nil
        }

        // NSBitmapImageRepに変換してJPEG圧縮
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            print("[ScreenshotManager] Failed to compress to JPEG")
            return nil
        }

        print("[ScreenshotManager] Captured \(Int(captureRect.width))x\(Int(captureRect.height)) image, \(jpegData.count) bytes")

        return jpegData
    }

    /// カーソル周辺のスクリーンショットを取得（サイズ指定）
    /// - Parameters:
    ///   - size: キャプチャサイズ（CaptureSize enum）
    ///   - quality: JPEG圧縮品質（0.0〜1.0）
    /// - Returns: JPEG形式の画像データ、失敗時はnil
    func captureAroundCursor(size: CaptureSize = .medium, quality: CGFloat = 0.7) -> Data? {
        return captureAroundCursorJPEG(radius: size.radius, quality: quality)
    }
}

// MARK: - Capture Size

/// キャプチャサイズの設定
enum CaptureSize: Int, Codable, CaseIterable {
    case small = 200    // 400x400px
    case medium = 400   // 800x800px (default)
    case large = 600    // 1200x1200px
    case extraLarge = 800 // 1600x1600px

    var radius: Int { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小 (400×400)"
        case .medium: return "中 (800×800)"
        case .large: return "大 (1200×1200)"
        case .extraLarge: return "特大 (1600×1600)"
        }
    }

    var dimension: Int {
        return rawValue * 2
    }
}
