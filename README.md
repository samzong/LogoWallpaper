# LogoWallpaper

<div align="center">
  <img src="./LogoWallpaper/Assets.xcassets/AppIcon.appiconset/logo-256.png" alt="LogoWallpaper" width="128" />
  <br />
  <div id="download-section" style="margin: 20px 0;">
    <a href="#" onclick="downloadLatest(); return false;" style="text-decoration: none;">
      <img src="https://img.shields.io/badge/⬇%20Download%20for%20Your%20System-28a745?style=for-the-badge&labelColor=28a745" alt="Download" />
    </a>
  </div>
  <p>A macOS app for quickly generating clean brand wallpapers.</p>
  <p>
    <a href="https://github.com/samzong/LogoWallpaper/releases"><img src="https://img.shields.io/github/v/release/samzong/LogoWallpaper" alt="Release" /></a>
    <a href="https://github.com/samzong/LogoWallpaper/blob/main/LICENSE"><img src="https://img.shields.io/github/license/samzong/LogoWallpaper" alt="License" /></a>
  </p>
</div>

LogoWallpaper is a SwiftUI macOS app for quickly generating clean brand wallpapers. Drag your logo into the window and the generator creates polished, watermark-free backgrounds that are ready for presentations or daily use.

## Installation

- **Homebrew (recommended)**  
  ```sh
  brew install samzong/tap/logo-wallpaper
  ```
  Homebrew will place LogoWallpaper in `/Applications`. Launch it from Spotlight or the Applications folder.
- **Manual download**  
  Download the latest `.dmg` from the [releases page](https://github.com/samzong/LogoWallpaper/releases), open it, and drag LogoWallpaper into `/Applications`.

## Usage

- Prepare a **watermark-free PNG** as the source logo and drop it into the app window to start generating wallpapers.
- If your artwork is in SVG format, convert it to PNG with the free tool at <https://www.svgviewer.dev/svg-to-png>.

Tweak colors, layout, and export settings to create wallpapers tailored to any display.

## Demo

![LogoWallpaper](https://raw.githubusercontent.com/samzong/LogoWallpaper/refs/heads/main/demo.gif)

## Contributing

1. Fork the repository and clone your fork locally.
2. Open the project in Xcode with `xed .` or run headless builds via `xcodebuild -scheme LogoWallpaper -destination 'platform=macOS' build`.
3. Run the full test suite before submitting changes:  
   ```sh
   xcodebuild -scheme LogoWallpaper -destination 'platform=macOS' test
   ```
4. Follow the project coding style, add focused unit tests under `LogoWallpaperTests/`, and reference any related issues in your pull request body.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.