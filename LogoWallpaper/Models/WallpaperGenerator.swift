import SwiftUI
import Combine
import AppKit

private struct PreviewInput {
    let image: NSImage
    let logoSize: Double
    let backgroundColor: Color
}

private struct PixelSizeKey: Hashable {
    let width: Int
    let height: Int
}

struct WallpaperPreviewVariant: Identifiable, Equatable {
    let id: String
    let image: NSImage
    let title: String
    let subtitle: String
}

class WallpaperGenerator: ObservableObject {
    @Published var logoSize: Double = 0.3
    @Published var backgroundColor: Color = .black
    @Published var selectedImage: NSImage?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var previewVariants: [WallpaperPreviewVariant] = []

    private struct PreviewTarget {
        let id: String
        let pixelSize: NSSize
        let title: String
        let subtitle: String
    }

    private static let defaultPreviewPixelSize = NSSize(width: 1600, height: 900)

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
                var cachedWallpapers: [PixelSizeKey: URL] = [:]

                for screen in screens {
                    let screenKey = self.screenIdentifier(for: screen)
                    let targetSize = self.pixelSize(for: screen)
                    let cacheKey = PixelSizeKey(
                        width: Int(round(targetSize.width)),
                        height: Int(round(targetSize.height))
                    )

                    let exportURL: URL

                    if let cachedURL = cachedWallpapers[cacheKey] {
                        exportURL = cachedURL
                    } else {
                        let wallpaper = ImageProcessor.createWallpaperWithLogo(
                            logo: image,
                            backgroundColor: nsColor,
                            screenSize: targetSize,
                            logoSizeRatio: logoSizeRatio
                        )

                        let persistedURL = try self.persistWallpaperImage(wallpaper, screenKey: screenKey)
                        cachedWallpapers[cacheKey] = persistedURL
                        exportURL = persistedURL
                    }

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
            .map { [weak self] input -> [WallpaperPreviewVariant] in
                guard
                    let self = self,
                    let input = input,
                    let nsColor = try? Self.makeNSColor(from: input.backgroundColor)
                else {
                    return []
                }

                let targets = self.previewTargets()

                return targets.map { target in
                    let canvasSize = self.previewCanvasSize(for: target.pixelSize)
                    let previewImage = ImageProcessor.createWallpaperWithLogo(
                        logo: input.image,
                        backgroundColor: nsColor,
                        screenSize: canvasSize,
                        logoSizeRatio: input.logoSize
                    )

                    return WallpaperPreviewVariant(
                        id: target.id,
                        image: previewImage,
                        title: target.title,
                        subtitle: target.subtitle
                    )
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] previews in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.previewVariants = previews
                    self.previewImage = previews.first?.image
                }
            }
            .store(in: &cancellables)
    }

    private func previewCanvasSize(for pixelSize: NSSize) -> NSSize {
        let maxDimension: CGFloat = 1600
        let largestSide = max(pixelSize.width, pixelSize.height)

        guard largestSide > maxDimension else {
            return pixelSize
        }

        let scale = maxDimension / largestSide
        return NSSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    private func previewTargets() -> [PreviewTarget] {
        let screens = targetScreens()
        var seenPixelSizes: Set<PixelSizeKey> = []
        var targets: [PreviewTarget] = []

        for (index, screen) in screens.enumerated() {
            let pixelSize = pixelSize(for: screen)
            let key = PixelSizeKey(
                width: Int(round(pixelSize.width)),
                height: Int(round(pixelSize.height))
            )

            guard !seenPixelSizes.contains(key) else { continue }
            seenPixelSizes.insert(key)

            let identifier = screenIdentifier(for: screen)
            let title = screenTitle(for: screen, defaultIndex: index)
            let subtitle = previewSubtitle(for: pixelSize)

            targets.append(
                PreviewTarget(
                    id: identifier,
                    pixelSize: pixelSize,
                    title: title,
                    subtitle: subtitle
                )
            )
        }

        if targets.isEmpty {
            let pixelSize = Self.defaultPreviewPixelSize
            targets.append(
                PreviewTarget(
                    id: "default-preview",
                    pixelSize: pixelSize,
                    title: String(
                        localized: "Default Preview",
                        comment: "Fallback name when no display information is available"
                    ),
                    subtitle: previewSubtitle(for: pixelSize)
                )
            )
        }

        return targets
    }

    private func screenTitle(for screen: NSScreen, defaultIndex: Int) -> String {
        if #available(macOS 11.0, *) {
            let trimmed = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let format = String(
            localized: "Display %d",
            comment: "Fallback display name when system name is unavailable"
        )
        return String(format: format, defaultIndex + 1)
    }

    private func previewSubtitle(for pixelSize: NSSize) -> String {
        let roundedWidth = Int(round(pixelSize.width))
        let roundedHeight = Int(round(pixelSize.height))
        let resolution = "\(roundedWidth)×\(roundedHeight)"

        guard let aspectRatioText = aspectRatioString(width: roundedWidth, height: roundedHeight) else {
            return resolution
        }

        return "\(resolution) · \(aspectRatioText)"
    }

    private func aspectRatioString(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return nil }
        let divisor = greatestCommonDivisor(width, height)
        guard divisor > 0 else { return nil }

        let simplifiedWidth = width / divisor
        let simplifiedHeight = height / divisor
        return "\(simplifiedWidth):\(simplifiedHeight)"
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = abs(a)
        var b = abs(b)

        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }

        return a
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
