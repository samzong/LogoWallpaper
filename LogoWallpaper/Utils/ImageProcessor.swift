import SwiftUI
import AppKit

class ImageProcessor {
    static func loadImage(from url: URL) -> NSImage? {
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStop {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = url.pathExtension.lowercased()

        guard fileExtension != "svg" else {
            return nil
        }

        switch fileExtension {
        case "png", "jpg", "jpeg", "tiff", "bmp", "gif", "heic":
            return NSImage(contentsOf: url)
        default:
            return NSImage(contentsOf: url)
        }
    }

    static func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))
        
        newImage.unlockFocus()
        return newImage
    }
    
    static func createWallpaperWithLogo(
        logo: NSImage,
        backgroundColor: NSColor,
        screenSize: NSSize,
        logoSizeRatio: Double
    ) -> NSImage {
        let wallpaperImage = NSImage(size: screenSize)
        wallpaperImage.lockFocus()

        backgroundColor.set()
        CGRect(origin: .zero, size: screenSize).fill()

        let logoRect = logoRect(for: logo.size, in: screenSize, ratio: logoSizeRatio)

        logo.draw(in: logoRect)

        wallpaperImage.unlockFocus()
        return wallpaperImage
    }

    static func logoRect(for logoSize: NSSize, in screenSize: NSSize, ratio: Double) -> CGRect {
        guard logoSize.width > 0, logoSize.height > 0 else {
            return CGRect(origin: CGPoint(x: screenSize.width / 2, y: screenSize.height / 2), size: .zero)
        }

        let maxLogoWidth = screenSize.width * CGFloat(ratio)
        let maxLogoHeight = screenSize.height * CGFloat(ratio)

        var logoWidth = maxLogoWidth
        var logoHeight = logoWidth * (logoSize.height / logoSize.width)

        if logoHeight > maxLogoHeight {
            logoHeight = maxLogoHeight
            logoWidth = logoHeight * (logoSize.width / logoSize.height)
        }

        let origin = CGPoint(
            x: (screenSize.width - logoWidth) / 2,
            y: (screenSize.height - logoHeight) / 2
        )

        return CGRect(origin: origin, size: CGSize(width: logoWidth, height: logoHeight))
    }

    static func imageHasAlpha(_ image: NSImage) -> Bool {
        if image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .contains(where: { $0.hasAlpha }) {
            return true
        }

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            return bitmap.hasAlpha
        }

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            switch cgImage.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast:
                return false
            default:
                return true
            }
        }

        return false
    }
}
