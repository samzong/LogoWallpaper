import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct LogoDropView: View {
    var onImageDropped: (NSImage) -> Void
    var onFailure: ((String) -> Void)?
    
    @State private var isTargeted = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isTargeted ? Color.blue : Color.gray, style: StrokeStyle(lineWidth: 2, dash: [8]))
                )
            
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(isTargeted ? .blue : .gray)

                Text("Click or drop a transparent PNG logo")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: acceptedTypeIdentifiers, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onTapGesture {
            presentFilePicker()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else {
                    notifyFailure(message: "Could not read file URL.")
                    return
                }

                processFileURL(url)
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    notifyFailure(message: "Could not load the image.")
                    return
                }

                processLoadedImage(image)
            }
            return true
        }

        notifyFailure(message: "Only transparent PNG images are supported.")
        return false
    }

    private var acceptedTypeIdentifiers: [UTType] {
        var types: [UTType] = [.fileURL, .png]
        types.append(.image)
        return types
    }

    private func presentFilePicker() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            if #available(macOS 11.0, *) {
                panel.allowedContentTypes = [.png]
            } else {
                panel.allowedFileTypes = ["png"]
            }

            if panel.runModal() == .OK, let url = panel.url {
                processFileURL(url)
            }
        }
    }

    private func processFileURL(_ url: URL) {
        if url.pathExtension.lowercased() == "svg" {
            notifyFailure(message: "SVG files are not supported. Please choose a transparent PNG image.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = ImageProcessor.loadImage(from: url) else {
                notifyFailure(message: "Could not process the image. Ensure it is a transparent PNG.")
                return
            }

            processLoadedImage(image)
        }
    }

    private func processLoadedImage(_ image: NSImage) {
        guard ImageProcessor.imageHasAlpha(image) else {
            notifyFailure(message: "The image is missing transparency. Export a transparent PNG first.")
            return
        }

        DispatchQueue.main.async {
            onImageDropped(image)
        }
    }

    private func notifyFailure(message: String) {
        DispatchQueue.main.async {
            onFailure?(message)
        }
    }
}
