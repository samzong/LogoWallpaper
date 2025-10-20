import SwiftUI
import Combine
import AppKit

class WallpaperGenerator: ObservableObject {
    @Published var logoSize: Double = 0.3
    @Published var backgroundColor: Color = .black
    @Published var selectedImage: NSImage?

    private let fileManager = FileManager.default
    private let fileQueue = DispatchQueue(label: "com.logowallpaper.generator.files")
    private lazy var persistenceDirectory: URL = {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("LogoWallpaper", isDirectory: true)
    }()
    private var persistedWallpapers: [String: URL] = [:]

    init() {
        cleanupPersistenceDirectory()
    }

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
        let previousPersisted = fileQueue.sync { persistedWallpapers }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let nsColor = try Self.makeNSColor(from: desiredBackground)

                try self.ensurePersistenceDirectoryExists()

                var nextPersisted: [String: URL] = [:]

                try screens.forEach { screen in
                    let screenKey = self.screenIdentifier(for: screen)
                    let targetSize = self.pixelSize(for: screen)
                    let wallpaper = ImageProcessor.createWallpaperWithLogo(
                        logo: image,
                        backgroundColor: nsColor,
                        screenSize: targetSize,
                        logoSizeRatio: logoSizeRatio
                    )

                    let exportURL = try self.persistWallpaperImage(wallpaper, screenKey: screenKey)
                    nextPersisted[screenKey] = exportURL

                    do {
                        try NSWorkspace.shared.setDesktopImageURL(exportURL, for: screen, options: [:])
                    } catch {
                        throw WallpaperError.setWallpaperFailed(error.localizedDescription)
                    }
                }

                self.fileQueue.sync {
                    self.persistedWallpapers = nextPersisted
                }

                let keepSet = Set(nextPersisted.values)
                self.cleanupPersistenceDirectory(keeping: keepSet)

                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.fileQueue.sync {
                    self.persistedWallpapers = previousPersisted
                }

                let keepSet = Set(previousPersisted.values)
                self.cleanupPersistenceDirectory(keeping: keepSet)

                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        return NSScreen.screens
    }

    private func persistWallpaperImage(_ image: NSImage, screenKey: String) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw WallpaperError.imageConversionFailed
        }

        let filename = "wallpaper-\(screenKey)-\(UUID().uuidString).png"
        let destination = persistenceDirectory.appendingPathComponent(filename, isDirectory: false)

        try pngData.write(to: destination, options: .atomic)
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

    private func cleanupPersistenceDirectory(keeping keep: Set<URL> = []) {
        fileQueue.sync {
            guard fileManager.fileExists(atPath: persistenceDirectory.path) else {
                if keep.isEmpty {
                    persistedWallpapers.removeAll()
                } else {
                    persistedWallpapers = persistedWallpapers.filter { keep.contains($0.value) }
                }
                return
            }

            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: persistenceDirectory,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )

                contents.forEach { url in
                    guard !keep.contains(url) else { return }
                    do {
                        try fileManager.removeItem(at: url)
                    } catch {
                        NSLog("LogoWallpaper cleanup failed for %@: %@", url.path, error.localizedDescription)
                    }
                }
            } catch {
                NSLog("LogoWallpaper directory listing failed: %@", error.localizedDescription)
            }

            if keep.isEmpty {
                persistedWallpapers.removeAll()
            } else {
                persistedWallpapers = persistedWallpapers.filter { keep.contains($0.value) }
            }
        }
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
