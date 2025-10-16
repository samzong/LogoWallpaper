//
//  LogoWallpaperTests.swift
//  LogoWallpaperTests
//
//  Created by samzong on 10/16/25.
//

import AppKit
import Testing
@testable import LogoWallpaper

struct LogoWallpaperTests {

    @Test func wallpaperMatchesScreenSize() throws {
        let logo = Self.makeSampleLogo(size: NSSize(width: 200, height: 120))
        let targetSize = NSSize(width: 1280, height: 720)

        let wallpaper = ImageProcessor.createWallpaperWithLogo(
            logo: logo,
            backgroundColor: NSColor.red,
            screenSize: targetSize,
            logoSizeRatio: 0.4
        )

        #expect(wallpaper.size == targetSize)
    }

    @Test func logoScalesToFitHeightConstraint() throws {
        let tallLogo = Self.makeSampleLogo(size: NSSize(width: 100, height: 400))
        let targetSize = NSSize(width: 1080, height: 1920)

        let rect = ImageProcessor.logoRect(for: tallLogo.size, in: targetSize, ratio: 0.5)
        let maxAllowedHeight = targetSize.height * 0.5
        #expect(rect.height <= maxAllowedHeight + 0.5)
        #expect(rect.width <= targetSize.width * 0.5 + 0.5)
    }

    @Test func loadImageSupportsPngFiles() throws {
        let url = try Self.makeTemporaryPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        let image = ImageProcessor.loadImage(from: url)
        #expect(image != nil)
    }

    private static func makeSampleLogo(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        NSColor.black.setStroke()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).stroke()

        image.unlockFocus()
        return image
    }

    private static func makeTemporaryPNG() throws -> URL {
        let logo = makeSampleLogo(size: NSSize(width: 300, height: 300))

        guard let tiff = logo.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw WallpaperError.imageConversionFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        try pngData.write(to: url)
        return url
    }
}
