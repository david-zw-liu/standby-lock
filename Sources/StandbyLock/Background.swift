import AppKit
import CoreImage
import ImageIO

/// 遮罩程度（0–100%）：同時決定背景圖的模糊半徑與黑色陰影濃度。
enum Mask {
    static let maxDimAlpha: CGFloat = 0.75
    /// 100% 時的高斯模糊 sigma，以長邊 `Background.maxPixelSize` 像素為基準。
    static let maxBlurSigma: Double = 80

    static func dimAlpha(percent: Int) -> CGFloat {
        maxDimAlpha * CGFloat(clamp(percent)) / 100
    }

    static func blurSigma(percent: Int) -> Double {
        maxBlurSigma * Double(clamp(percent)) / 100
    }

    static func clamp(_ percent: Int) -> Int { min(max(percent, 0), 100) }
}

enum Background {
    static let maxPixelSize = 2560

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StandbyLock", isDirectory: true)
    }

    static var imageURL: URL? {
        guard let name = Settings.backgroundImageFileName else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var hasImage: Bool { imageURL != nil }

    /// 把使用者選的圖片複製進 Application Support，原檔之後被移動或刪除也不受影響。
    static func setImage(from source: URL) throws {
        guard decode(source) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "img" : source.pathExtension.lowercased()
        // 檔名帶時間戳，避免新舊檔同名時複製失敗。
        let name = "background-\(Int(Date().timeIntervalSince1970)).\(ext)"
        try fm.copyItem(at: source, to: directory.appendingPathComponent(name))
        let old = Settings.backgroundImageFileName
        Settings.backgroundImageFileName = name
        if let old, old != name {
            try? fm.removeItem(at: directory.appendingPathComponent(old))
        }
    }

    static func clearImage() {
        if let name = Settings.backgroundImageFileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        Settings.backgroundImageFileName = nil
    }

    /// 讀取背景圖並套用模糊。沒有設定圖片或讀取失敗時回傳 nil（改用預設漸層）。
    static func render(maskPercent: Int) -> CGImage? {
        guard let url = imageURL, let image = decode(url) else { return nil }
        let sigma = Mask.blurSigma(percent: maskPercent)
        guard sigma > 0 else { return image }

        let scale = Double(max(image.width, image.height)) / Double(maxPixelSize)
        let input = CIImage(cgImage: image)
        let blurred = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma * scale)
            .cropped(to: input.extent)
        return CIContext().createCGImage(blurred, from: input.extent) ?? image
    }

    /// 解碼並縮到長邊不超過 `maxPixelSize`，同時套用 EXIF 方向。
    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
