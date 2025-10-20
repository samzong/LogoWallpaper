import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct LogoDropView: View {
    var previews: [WallpaperPreviewVariant]
    var backgroundColor: Color
    var hasSelection: Bool
    var onImageDropped: (NSImage) -> Void
    var onFailure: ((String) -> Void)?

    @State private var isTargeted = false
    @State private var selectedPreviewID: WallpaperPreviewVariant.ID?

    private let cornerRadius: CGFloat = 20

    private var selectedPreview: WallpaperPreviewVariant? {
        if let id = selectedPreviewID,
           let preview = previews.first(where: { $0.id == id }) {
            return preview
        }
        return previews.first
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: {
                if let current = selectedPreview?.id {
                    return current
                }
                if let fallback = previews.first?.id {
                    selectedPreviewID = fallback
                    return fallback
                }
                return ""
            },
            set: { newValue in
                selectedPreviewID = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(previewBackgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 2, dash: [10]))
                    }

                if let image = selectedPreview?.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(32)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 6, style: .continuous))
                        .accessibilityLabel(
                            Text(
                                String(
                                    localized: "Wallpaper preview",
                                    comment: "Accessibility label describing the wallpaper preview image"
                                )
                            )
                        )
                }

                overlayContent
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .contentShape(Rectangle())
            .onDrop(of: acceptedTypeIdentifiers, isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .onTapGesture {
                presentFilePicker()
            }
            .animation(.easeInOut(duration: 0.18), value: isTargeted)
            .animation(.easeInOut(duration: 0.18), value: selectedPreview == nil)
            .overlay(alignment: .topTrailing) {
                previewSelectionOverlay
            }

            if let preview = selectedPreview {
                previewDetails(for: preview)
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            selectedPreviewID = selectedPreviewID ?? previews.first?.id
        }
        .onChange(of: previews) { newValue in
            let availableIDs = Set(newValue.map(\.id))
            if let current = selectedPreviewID, availableIDs.contains(current) {
                return
            }
            selectedPreviewID = newValue.first?.id
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        }

        if selectedPreview == nil {
            VStack(spacing: 12) {
                Image(systemName: hasSelection ? "hourglass.circle" : "square.and.arrow.up.on.square")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                if hasSelection {
                    Text(
                        String(
                            localized: "Rendering preview…",
                            comment: "Loading message shown while the preview is rendering"
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        Text(
                            String(
                                localized: "Rendering preview",
                                comment: "Accessibility label when the preview is still rendering"
                            )
                        )
                    )
                } else {
                    Text(
                        String(
                            localized: "Click or drop a transparent PNG logo",
                            comment: "Instructions inside drop zone"
                        )
                    )
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func previewDetails(for preview: WallpaperPreviewVariant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewBackgroundColor: Color {
        if selectedPreview != nil {
            return backgroundColor
        }
        return Color.secondary.opacity(0.08)
    }

    private var borderColor: Color {
        isTargeted ? Color.accentColor : Color.primary.opacity(0.25)
    }

    @ViewBuilder
    private var previewSelectionOverlay: some View {
        if let preview = selectedPreview {
            HStack(spacing: 10) {
                Label {
                    Text(
                        String(
                            localized: "Displays",
                            comment: "Label describing the display picker overlay"
                        )
                    )
                    .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "display")
                        .font(.caption)
                }

                if previews.count > 1 {
                    if previews.count <= 3 {
                        Picker("", selection: pickerSelection) {
                            ForEach(previews) { variant in
                                Text(variant.title).tag(variant.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    } else {
                        Picker("", selection: pickerSelection) {
                            ForEach(previews) { variant in
                                Text(variant.title).tag(variant.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                    }
                } else {
                    Text(preview.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if #available(macOS 12.0, *) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.regularMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
            .padding(12)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else {
                    notifyFailure(message: String(
                        localized: "Could not read file URL.",
                        comment: "Error shown when the dropped item lacks a readable file URL"
                    ))
                    return
                }

                processFileURL(url)
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    notifyFailure(message: String(
                        localized: "Could not load the image.",
                        comment: "Error shown when an image provider fails to load"
                    ))
                    return
                }

                processLoadedImage(image)
            }
            return true
        }

        notifyFailure(message: String(
            localized: "Only transparent PNG images are supported.",
            comment: "Error shown when the dropped item is not a transparent PNG"
        ))
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
            notifyFailure(message: String(
                localized: "SVG files are not supported. Please choose a transparent PNG image.",
                comment: "Error shown when the user selects an SVG file"
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = ImageProcessor.loadImage(from: url) else {
                notifyFailure(message: String(
                    localized: "Could not process the image. Ensure it is a transparent PNG.",
                    comment: "Error shown when the image data cannot be processed"
                ))
                return
            }

            processLoadedImage(image)
        }
    }

    private func processLoadedImage(_ image: NSImage) {
        guard ImageProcessor.imageHasAlpha(image) else {
            notifyFailure(message: String(
                localized: "The image is missing transparency. Export a transparent PNG first.",
                comment: "Error shown when the selected image lacks transparency"
            ))
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
