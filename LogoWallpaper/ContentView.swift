import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var wallpaperGenerator = WallpaperGenerator()
    @State private var isGenerating = false
    @State private var isExporting = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var successMessage = String(
        localized: "Wallpaper updated successfully.",
        comment: "Default success message when wallpaper generation completes"
    )
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("LogoWallpaper")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 20)

            LogoDropView(
                previews: wallpaperGenerator.previewVariants,
                backgroundColor: wallpaperGenerator.backgroundColor,
                hasSelection: wallpaperGenerator.selectedImage != nil,
                onImageDropped: handleDroppedImage,
                onFailure: handleDropFailure
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Configuration")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $wallpaperGenerator.logoSize, in: 0.1...0.96)
                    Text("Logo Size: \(Int(wallpaperGenerator.logoSize * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ColorPicker("Background Color", selection: $wallpaperGenerator.backgroundColor)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button(action: exportWallpaper) {
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Save Wallpaper As")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isExporting || wallpaperGenerator.selectedImage == nil)

                Button(action: generateWallpaperFromSelected) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Generate and Set Wallpaper")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || wallpaperGenerator.selectedImage == nil)
            }
            .padding(.bottom, 20)
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func handleDroppedImage(_ image: NSImage) {
        wallpaperGenerator.selectedImage = image
    }

    private func handleDropFailure(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func generateWallpaper(from image: NSImage) {
        isGenerating = true
        wallpaperGenerator.generateWallpaper(from: image) { result in
            isGenerating = false

            switch result {
            case .success:
                successMessage = String(
                    localized: "Wallpaper updated successfully.",
                    comment: "Success message when wallpaper generation completes"
                )
                showSuccessAlert = true
            case .failure(let error):
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func generateWallpaperFromSelected() {
        guard let image = wallpaperGenerator.selectedImage else {
            errorMessage = String(
                localized: "Select an image before generating.",
                comment: "Prompt when attempting to generate a wallpaper without selecting an image"
            )
            showErrorAlert = true
            return
        }

        generateWallpaper(from: image)
    }

    private func exportWallpaper() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFilename()

        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png]
        } else {
            panel.allowedFileTypes = ["png"]
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            isExporting = true
            wallpaperGenerator.exportWallpaper(to: url) { result in
                isExporting = false

                switch result {
                case .success(let finalURL):
                    let template = String(
                        localized: "Saved wallpaper to %@.",
                        comment: "Success message when exporting wallpaper succeeds"
                    )
                    successMessage = String(format: template, finalURL.lastPathComponent)
                    showSuccessAlert = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return "LogoWallpaper-\(timestamp).png"
    }
}
