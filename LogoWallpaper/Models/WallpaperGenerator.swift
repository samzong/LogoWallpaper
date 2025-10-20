import SwiftUI
import Combine
import AppKit

class WallpaperGenerator: ObservableObject {
    @Published var logoSize: Double = 0.3
    @Published var backgroundColor: Color = .black
    @Published var selectedImage: NSImage?

    private let fileManager = FileManager.default
    private lazy var persistenceDirectory: URL = {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("LogoWallpaper", isDirectory: true)
    }()
    private var persistedWallpapers: [String: URL] = [:]

    func generateWallpaper(from image: NSImage, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async {
            self.selectedImage = image
        }

        let screens = targetScreens()
        guard !screens.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(WallpaperError.noScreenAvailable))
            }
            return
        }

        let logoSizeRatio = logoSize
        let desiredBackground = backgroundColor

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let nsColor = try Self.makeNSColor(from: desiredBackground)

                try self.ensurePersistenceDirectoryExists()

                try screens.forEach { screen in
                    let targetSize = self.pixelSize(for: screen)
                    let wallpaper = ImageProcessor.createWallpaperWithLogo(
                        logo: image,
                        backgroundColor: nsColor,
                        screenSize: targetSize,
                        logoSizeRatio: logoSizeRatio
                    )

                    let exportURL = try self.persistWallpaperImage(wallpaper, for: screen)

                    do {
                        try NSWorkspace.shared.setDesktopImageURL(exportURL, for: screen, options: [:])
                    } catch {
                        throw WallpaperError.setWallpaperFailed(error.localizedDescription)
                    }
                }

                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        return NSScreen.screens
    }

    private func persistWallpaperImage(_ image: NSImage, for screen: NSScreen) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw WallpaperError.imageConversionFailed
        }

        let screenKey = screenIdentifier(for: screen)
        let filename = "wallpaper-\(screenKey)-\(UUID().uuidString).png"
        let destination = persistenceDirectory.appendingPathComponent(filename, isDirectory: false)

        try pngData.write(to: destination, options: .atomic)

        if let previousURL = persistedWallpapers[screenKey], previousURL != destination {
            try? fileManager.removeItem(at: previousURL)
        }

        persistedWallpapers[screenKey] = destination
        return destination
    }

    private static func makeNSColor(from color: Color) throws -> NSColor {
        #if canImport(AppKit)
        if let cgColor = color.cgColor, let nsColor = NSColor(cgColor: cgColor) {
            return nsColor
        }

        if #available(macOS 12.0, *) {
            return NSColor(color)
        }
        #endif

        throw WallpaperError.backgroundColorUnavailable
    }

    private func ensurePersistenceDirectoryExists() throws {
        if !fileManager.fileExists(atPath: persistenceDirectory.path) {
            try fileManager.createDirectory(at: persistenceDirectory, withIntermediateDirectories: true)
        }
    }

    private func screenIdentifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }

        if #available(macOS 11.0, *) {
            return screen.localizedName.replacingOccurrences(of: " ", with: "-")
        }

        return UUID().uuidString
    }

    private func pixelSize(for screen: NSScreen) -> NSSize {
        let size = screen.frame.size
        let scale = max(screen.backingScaleFactor, 1)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }
}

enum WallpaperError: LocalizedError {
    case imageConversionFailed
    case setWallpaperFailed(String)
    case noScreenAvailable
    case backgroundColorUnavailable

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return String(
                localized: "Image conversion failed.",
                comment: "Error when the generated wallpaper could not be converted to PNG"
            )
        case .setWallpaperFailed(let message):
            let template = String(
                localized: "Failed to set wallpaper: %@",
                comment: "Error when macOS fails to apply the generated wallpaper with a specific reason"
            )
            return String(format: template, message)
        case .noScreenAvailable:
            return String(
                localized: "No available display detected.",
                comment: "Error when no monitors are detected while generating wallpaper"
            )
        case .backgroundColorUnavailable:
            return String(
                localized: "Background color is unavailable.",
                comment: "Error when the selected background color cannot be used"
            )
        }
    }
}
