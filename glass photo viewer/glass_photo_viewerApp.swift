//
//  glass_photo_viewerApp.swift
//  glass photo viewer
//
//  Created by Nikunj Singh on 8/22/25.
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PhotoViewerApp: App {
    @StateObject private var vm = ViewerModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Glass Photos") {
            ContentView()
                .onOpenURL { url in vm.handleOpen(urls: [url]) }
                .environmentObject(vm)
                .onAppear {
                    print("App window appeared")
                    // Handle files opened with the app on launch
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let urls = NSApplication.shared.openFileURLs, !urls.isEmpty {
                            vm.handleOpenedFiles(urls)
                        }
                    }
                }
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: Set(arrayLiteral: "file"))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { vm.pickFolder() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandGroup(after: .windowSize) {
                Button("Toggle Full Screen") { vm.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [])
            }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "file"))
    }
}

final class ViewerModel: ObservableObject {
    
    @Published var files: [URL] = []
    @Published var index = 0
    @Published var fitToWindow = true
    @Published var isLoading = false
    
    private var keyMonitor: Any?
    private let allowed = Set(["jpg","jpeg","png","webp","heic","heif","tiff","gif","bmp","dng","nef","cr2","arw","raf"])
    private let cache = NSCache<NSURL, NSImage>()
    
    // Handle files opened with the app
    func handleOpenedFiles(_ urls: [URL]) {
        var imageFiles: [URL] = []
        var folders: [URL] = []
        
        for url in urls {
            if url.hasDirectoryPath {
                folders.append(url)
            } else if isImageFile(url) {
                imageFiles.append(url)
            }
        }
        
        if !imageFiles.isEmpty {
            // If individual files were opened, show them immediately
            DispatchQueue.main.async {
                self.files = imageFiles
                self.index = 0
                self.isLoading = false
                print("Loaded \(imageFiles.count) individual image files")
            }
            
            // Also load the containing folder in the background for navigation
            let folderURLs = Set(imageFiles.map { $0.deletingLastPathComponent() })
            if let firstFolder = folderURLs.first {
                loadFolderInBackground(firstFolder, selectedFile: imageFiles.first)
            }
        } else if !folders.isEmpty {
            // If folders were opened, load the first one
            loadFolder(folders[0])
        }
    }
    
    // Check if a file is an image
    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return allowed.contains(ext)
    }
    


    // Folder picking
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { 
            print("Selected folder: \(url.path)")
            loadFolder(url)
        } else {
            print("No folder selected or cancelled")
        }
    }

    func loadFolder(_ dir: URL) {
        print("Loading folder: \(dir.path)")
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                
                var imgs: [URL] = []
                for url in contents {
                    // Check if it's a regular file (not a directory)
                    let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
                    if resourceValues.isRegularFile == true {
                        let ext = url.pathExtension.lowercased()
                        if self.allowed.contains(ext) { imgs.append(url) }
                    }
                }
                imgs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

                print("Found \(imgs.count) images in folder (excluding subdirectories)")
                
                DispatchQueue.main.async {
                    self.files = imgs
                    self.index = 0
                    self.isLoading = false
                    self.preloadNeighbors()
                    print("Folder loaded successfully, files count: \(self.files.count)")
                }
            } catch {
                print("Failed to enumerate directory: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadFolderInBackground(_ dir: URL, selectedFile: URL? = nil) {
        print("Loading folder in background: \(dir.path)")
        
        // Try to request folder access using NSOpenPanel
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = dir
            panel.message = "Glass Photos needs access to the folder containing your image to enable navigation between photos."
            panel.prompt = "Grant Access"
            
            if panel.runModal() == .OK, let folderURL = panel.url {
                print("Folder access granted: \(folderURL.path)")
                self.loadFolderWithAccess(folderURL, selectedFile: selectedFile)
            } else {
                print("Folder access denied - keeping single file view")
            }
        }
    }
    
    func loadFolderWithAccess(_ dir: URL, selectedFile: URL? = nil) {
        print("Loading folder with access: \(dir.path)")
        
        DispatchQueue.global(qos: .utility).async {
            // Use contentsOfDirectory instead of enumerator to only get immediate folder contents
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                
                var imgs: [URL] = []
                for url in contents {
                    // Check if it's a regular file (not a directory)
                    let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
                    if resourceValues.isRegularFile == true {
                        let ext = url.pathExtension.lowercased()
                        if self.allowed.contains(ext) { imgs.append(url) }
                    }
                }
                imgs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

                print("Found \(imgs.count) images in folder (excluding subdirectories)")
                
                DispatchQueue.main.async {
                    if !imgs.isEmpty, let selectedFile = selectedFile, let fileIndex = imgs.firstIndex(of: selectedFile) {
                        self.files = imgs
                        self.index = fileIndex
                        self.preloadNeighbors()
                        print("Folder loaded successfully, files count: \(self.files.count), current index: \(self.index)")
                    } else {
                        print("Selected file not found in folder or no images found")
                    }
                }
            } catch {
                print("Failed to enumerate directory: \(error)")
            }
        }
    }

    // Navigation
    func show(_ i: Int) {
        guard !files.isEmpty else { return }
        index = (i % files.count + files.count) % files.count
        preloadNeighbors()
    }
    func next() { show(index + 1) }
    func prev() { show(index - 1) }
    func toggleFit() { fitToWindow.toggle() }
    func toggleFullScreen() { 
        NSApp.keyWindow?.toggleFullScreen(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .fullScreenChanged, object: nil)
        }
    }

    // Image cache
    func image(for url: URL) -> NSImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let img = NSImage(contentsOf: url) {
            cache.setObject(img, forKey: url as NSURL)
            return img
        }
        return nil
    }
    private func preloadNeighbors() {
        guard !files.isEmpty else { return }
        for delta in [-1, 1] {
            let j = (index + delta + files.count) % files.count
            _ = image(for: files[j])
        }
    }

    // Keyboard handling
    func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            switch e.keyCode {
            case 123: self.prev(); return nil          // ←
            case 124: self.next(); return nil          // →
            case 49:  self.toggleFit(); return nil     // Space
            case 53:                                  // Esc
                if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true {
                    self.toggleFullScreen()
                    return nil
                }
                return e
            default:
                if e.charactersIgnoringModifiers?.lowercased() == "f" {
                    self.toggleFullScreen()
                    return nil
                }
                return e
            }
        }
    }
    func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}



    
func handleOpen(urls: [URL]) {
    guard let first = urls.first else { return }

    // Show the selected file immediately (even if folder enumeration fails)
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
    if !isDir.boolValue && FileManager.default.isReadableFile(atPath: first.path) {
        DispatchQueue.main.async {
            self.files = [first]
            self.index = 0
            self.isLoading = false
            print("Opened single file: \(first.lastPathComponent)")
        }
    }

    // Try to load folder and focus the file
    let folder = isDir.boolValue ? first : first.deletingLastPathComponent()

    // Security-scoped access for sandboxed builds (no-op if not sandboxed)
    var didStart = false
    #if canImport(AppKit)
    didStart = folder.startAccessingSecurityScopedResource()
    #endif
    defer {
        if didStart {
            folder.stopAccessingSecurityScopedResource()
        }
    }

    if isDir.boolValue {
        loadFolder(folder)
    } else {
        loadFolderInBackground(folder, selectedFile: first)
    }
}


struct Viewer: View {
    @EnvironmentObject var vm: ViewerModel
    @State private var isFullScreen = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Top header (only visible when not in fullscreen)
            if !isFullScreen {
                TopHeader(
                    imageName: vm.files[safe: vm.index]?.lastPathComponent ?? "",
                    currentIndex: vm.index,
                    totalCount: vm.files.count,
                    onFullScreen: {
                        isFullScreen = true
                        vm.toggleFullScreen()
                    }
                )
            }
            
            // Main image view
            GeometryReader { geo in
                if let url = vm.files[safe: vm.index], let nsimg = vm.image(for: url) {
                    let imageView = Image(nsImage: nsimg).interpolation(.high).antialiased(true)
                    Group {
                        if vm.fitToWindow {
                            imageView.resizable().scaledToFit()
                                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                                .scaleEffect(scale)
                                .offset(offset)
                                .clipped() // Prevent image from extending beyond bounds
                                .gesture(
                                    SimultaneousGesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                let delta = value / lastScale
                                                lastScale = value
                                                scale = min(max(scale * delta, 0.5), 5.0)
                                            }
                                            .onEnded { _ in
                                                lastScale = 1.0
                                                // Snap to bounds if zoomed out too much
                                                if scale < 1.0 {
                                                    withAnimation(.easeOut(duration: 0.3)) {
                                                        scale = 1.0
                                                        offset = .zero
                                                    }
                                                }
                                            },
                                        DragGesture()
                                            .onChanged { value in
                                                if scale > 1.0 {
                                                    offset = CGSize(
                                                        width: lastOffset.width + value.translation.width,
                                                        height: lastOffset.height + value.translation.height
                                                    )
                                                }
                                            }
                                            .onEnded { _ in
                                                lastOffset = offset
                                                // Constrain panning to image bounds
                                                constrainOffsetToBounds(imageSize: nsimg.size, viewSize: geo.size)
                                            }
                                    )
                                )
                                .onTapGesture(count: 2) { 
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if scale > 1.0 {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        } else {
                                            scale = 2.0
                                        }
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    // Single tap to reset zoom when zoomed in
                                    if scale > 1.0 {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        } else {
                            ScrollView([.horizontal, .vertical]) {
                                imageView.resizable().aspectRatio(contentMode: .fit).fixedSize()
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .clipped() // Prevent image from extending beyond bounds
                                    .gesture(
                                        SimultaneousGesture(
                                            MagnificationGesture()
                                                .onChanged { value in
                                                    let delta = value / lastScale
                                                    lastScale = value
                                                    scale = min(max(scale * delta, 0.5), 5.0)
                                                }
                                                .onEnded { _ in
                                                    lastScale = 1.0
                                                },
                                            DragGesture()
                                                .onChanged { value in
                                                    if scale > 1.0 {
                                                        offset = CGSize(
                                                            width: lastOffset.width + value.translation.width,
                                                            height: lastOffset.height + value.translation.height
                                                        )
                                                    }
                                                }
                                                .onEnded { _ in
                                                    lastOffset = offset
                                                }
                                        )
                                    )
                                    .onTapGesture(count: 2) { 
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            if scale > 1.0 {
                                                scale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            } else {
                                                scale = 2.0
                                            }
                                        }
                                    }
                                    .onTapGesture(count: 1) {
                                        // Single tap to reset zoom when zoomed in
                                        if scale > 1.0 {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                scale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                        // Only handle navigation gestures when not zoomed in
                        if scale <= 1.0 {
                            if value.translation.width < 0 { vm.next() }
                            if value.translation.width > 0 { vm.prev() }
                        }
                    })
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // Zoom indicator (only show when zoomed in)
            if scale > 1.0 {
                HStack {
                    Spacer()
                    Text("\(Int(scale * 100))%")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fullScreenChanged)) { _ in
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        }
        .onChange(of: vm.index) { _ in
            // Reset zoom when changing images
            withAnimation(.easeOut(duration: 0.2)) {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
                lastScale = 1.0
            }
        }
    }
    
    private func constrainOffsetToBounds(imageSize: NSSize, viewSize: CGSize) {
        let scaledImageSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        
        let maxOffsetX = max(0, (scaledImageSize.width - viewSize.width) / 2)
        let maxOffsetY = max(0, (scaledImageSize.height - viewSize.height) / 2)
        
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(
                width: offset.width.clamped(to: -maxOffsetX...maxOffsetX),
                height: offset.height.clamped(to: -maxOffsetY...maxOffsetY)
            )
            lastOffset = offset
        }
    }
}

struct TopHeader: View {
    let imageName: String
    let currentIndex: Int
    let totalCount: Int
    let onFullScreen: () -> Void
    
    var body: some View {
        HStack {
            // Image name and counter on the left
            HStack(spacing: 8) {
                Text(imageName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
                
                if totalCount > 1 {
                    Text("(\(currentIndex + 1)/\(totalCount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Fullscreen button on the right
            Button(action: onFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Enter Full Screen")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
    }
}

struct HUD: View {
    let url: URL; let index: Int; let total: Int
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)/\(total)")
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("← / → navigate • Space fit • F full screen")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}

// Helpers
extension Collection { subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil } }
x
extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// Extension to handle file opening
extension NSApplication {
    var openFileURLs: [URL]? {
        guard let delegate = delegate as? AppDelegate else { return nil }
        return delegate.openedFileURLs
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var openedFileURLs: [URL]?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App delegate finished launching")
        // Ensure the main window is visible
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                // Set window size
                window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: 1000, height: 700), display: true)
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                print("Window made key and ordered front")
            } else {
                print("No windows found")
            }
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        openedFileURLs = urls
        NotificationCenter.default.post(name: .filesOpened, object: urls)
    }
    
    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        openedFileURLs = [url]
        NotificationCenter.default.post(name: .filesOpened, object: [url])
        return true
    }
}

extension Notification.Name {
    static let filesOpened = Notification.Name("filesOpened")
    static let fullScreenChanged = Notification.Name("fullScreenChanged")
}

// ---- Previews (inject env object!) ----
#Preview {
    ContentView().environmentObject(ViewerModel())
}
