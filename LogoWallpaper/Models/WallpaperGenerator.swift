import SwiftUI
import Combine
import AppKit

private struct PreviewInput {
    let image: NSImage
    let logoSize: Double
    let backgroundColor: Color
}

class WallpaperGenerator: ObservableObject {
    @Published var logoSize: Double = 0.3
    @Published var backgroundColor: Color = .black
    @Published var selectedImage: NSImage?
    @Published private(set) var previewImage: NSImage?

    private let fileManager = FileManager.default
    private let fileQueue = DispatchQueue(label: "com.logowallpaper.generator.files")
    private let previewQueue = DispatchQueue(
        label: "com.logowallpaper.generator.preview",
        qos: .userInitiated
    )
    private var cancellables: Set<AnyCancellable> = []
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
        setupPreviewPipeline()
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

    private func setupPreviewPipeline() {
        Publishers.CombineLatest3($selectedImage, $logoSize, $backgroundColor)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .map { selectedImage, logoSize, backgroundColor -> PreviewInput? in
                guard let image = selectedImage else { return nil }
                return PreviewInput(
                    image: image,
                    logoSize: logoSize,
                    backgroundColor: backgroundColor
                )
            }
            .receive(on: previewQueue)
            .map { [weak self] input -> NSImage? in
                guard
                    let self = self,
                    let input = input,
                    let nsColor = try? Self.makeNSColor(from: input.backgroundColor)
                else {
                    return nil
                }

                let targetSize = self.previewCanvasSize()
                return ImageProcessor.createWallpaperWithLogo(
                    logo: input.image,
                    backgroundColor: nsColor,
                    screenSize: targetSize,
                    logoSizeRatio: input.logoSize
                )
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preview in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.previewImage = preview
                }
            }
            .store(in: &cancellables)
    }

    private func previewCanvasSize() -> NSSize {
        if let screen = NSScreen.main {
            let base = pixelSize(for: screen)
            let maxDimension: CGFloat = 1600
            let largestSide = max(base.width, base.height)

            guard largestSide > maxDimension else {
                return base
            }

            let scale = maxDimension / largestSide
            return NSSize(width: base.width * scale, height: base.height * scale)
        }

        return NSSize(width: 1600, height: 900)
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
