import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var wallpaperGenerator = WallpaperGenerator()
    @State private var isGenerating = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("LogoWallpaper")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 20)

            LogoDropView(
                onImageDropped: handleDroppedImage,
                onFailure: handleDropFailure
            )
            .frame(height: 200)
            .padding(.horizontal, 20)

            if let image = wallpaperGenerator.selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

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
            .padding(.bottom, 20)
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Wallpaper updated successfully.")
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
                showSuccessAlert = true
            case .failure(let error):
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func generateWallpaperFromSelected() {
        guard let image = wallpaperGenerator.selectedImage else {
            errorMessage = "Select an image before generating."
            showErrorAlert = true
            return
        }

        generateWallpaper(from: image)
    }
}
