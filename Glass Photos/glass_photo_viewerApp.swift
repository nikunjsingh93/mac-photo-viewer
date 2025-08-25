//
//  glass_photo_viewerApp.swift
//  glass photo viewer
//
//  Created by Nikunj Singh on 8/22/25.
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

@main
struct PhotoViewerApp: App {
    @StateObject private var vm = ViewerModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Glass Photos") {
            ContentView()
                .onOpenURL { url in vm.handleOpen(urls: [url]) }
                .environmentObject(vm)
                .preferredColorScheme(.dark)
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
    @Published var showInfoSidebar = false
    @Published var isLoadingExif = false
    
    private var keyMonitor: Any?
    private let allowed = Set(["jpg","jpeg","png","webp","heic","heif","tiff","gif","bmp","dng","nef","cr2","arw","raf"])
    private let cache = NSCache<NSURL, NSImage>()
    
    // EXIF data for current image
    @Published var currentExifData: [(String, Any)] = []
    
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
        
        // Direct folder access without sandboxing
        DispatchQueue.global(qos: .utility).async {
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
        preloadExifData()
    }
    
    func toggleInfoSidebar() {
        showInfoSidebar.toggle()
        if showInfoSidebar {
            // Load EXIF data when opening the sidebar
            loadExifData()
        }
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
    
    // EXIF Data handling
    func loadExifData() {
        guard !files.isEmpty, let currentURL = files[safe: index] else {
            currentExifData = []
            isLoadingExif = false
            return
        }
        
        isLoadingExif = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let exifData = self.extractExifData(from: currentURL)
            DispatchQueue.main.async {
                self.currentExifData = exifData
                self.isLoadingExif = false
            }
        }
    }
    
    private func extractExifData(from url: URL) -> [(String, Any)] {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return []
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return []
        }
        
        var exifData: [(String, Any)] = []
        var creationDateString: String?
        var modificationDateString: String?
        
        // Date Taken (first)
        if let exif = properties["{Exif}"] as? [String: Any],
           let dateTimeOriginal = exif["DateTimeOriginal"] as? String {
            exifData.append(("Date Taken", formatExifDate(dateTimeOriginal)))
        }
        
        // Basic file info
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            exifData.append(("File Size", formatFileSize(fileSize)))
        }
        
        if let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            creationDateString = formatDate(creationDate)
        }
        
        if let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            modificationDateString = formatDate(modificationDate)
        }
        
        // Image dimensions
        if let width = properties["PixelWidth"] as? Int,
           let height = properties["PixelHeight"] as? Int {
            exifData.append(("Dimensions", "\(width) × \(height)"))
        }
        
        // Color space
        if let colorSpace = properties["ColorSpace"] as? String {
            exifData.append(("Color Space", colorSpace))
        }
        
        // EXIF data
        if let exif = properties["{Exif}"] as? [String: Any] {
            if let exposureTime = exif["ExposureTime"] as? Double {
                exifData.append(("Exposure Time", formatExposureTime(exposureTime)))
            }
            
            if let fNumber = exif["FNumber"] as? Double {
                exifData.append(("F-Number", "f/\(String(format: "%.1f", fNumber))"))
            }
            
            if let iso = exif["ISOSpeedRatings"] as? [Int] {
                exifData.append(("ISO", "\(iso.first ?? 0)"))
            }
            
            if let focalLength = exif["FocalLength"] as? Double {
                exifData.append(("Focal Length", "\(Int(focalLength))mm"))
            }
            
            if let lensModel = exif["LensModel"] as? String {
                exifData.append(("Lens", lensModel))
            }
            
            if let cameraMake = exif["Make"] as? String {
                exifData.append(("Camera Make", cameraMake))
            }
            
            if let cameraModel = exif["Model"] as? String {
                exifData.append(("Camera Model", cameraModel))
            }
        }
        
        // GPS data
        if let gps = properties["{GPS}"] as? [String: Any] {
            if let latitude = gps["Latitude"] as? Double,
               let longitude = gps["Longitude"] as? Double {
                exifData.append(("GPS Coordinates", "\(latitude), \(longitude)"))
            }
        }
        
        // TIFF data
        if let tiff = properties["{TIFF}"] as? [String: Any] {
            if let make = tiff["Make"] as? String {
                exifData.append(("Make", make))
            }
            
            if let model = tiff["Model"] as? String {
                exifData.append(("Model", model))
            }
        }
        
        // Add Modified and Created at the end
        if let modificationDate = modificationDateString {
            exifData.append(("Modified", modificationDate))
        }
        
        if let creationDate = creationDateString {
            exifData.append(("Created", creationDate))
        }
        
        return exifData
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatExifDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = formatter.date(from: dateString) {
            return formatDate(date)
        }
        return dateString
    }
    
    private func formatExposureTime(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        } else {
            return "1/\(Int(1/seconds))s"
        }
    }
    
    // Share functionality
    func shareCurrentImage() {
        guard !files.isEmpty, let currentURL = files[safe: index] else { return }
        
        let sharingPicker = NSSharingServicePicker(items: [currentURL])
        
        if let window = NSApp.keyWindow {
            // Calculate center position of the window
            let windowFrame = window.frame
            let centerRect = CGRect(
                x: windowFrame.width / 2 - 100,
                y: windowFrame.height / 2 - 100,
                width: 200,
                height: 200
            )
            
            sharingPicker.show(relativeTo: centerRect, of: window.contentView!, preferredEdge: NSRectEdge.minY)
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
    
    // Preload EXIF data for current image
    private func preloadExifData() {
        guard !files.isEmpty, let currentURL = files[safe: index] else { return }
        
        DispatchQueue.global(qos: .utility).async {
            let exifData = self.extractExifData(from: currentURL)
            DispatchQueue.main.async {
                // Only update if we're still on the same image
                if self.files[safe: self.index] == currentURL {
                    self.currentExifData = exifData
                }
            }
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
}

struct ContentView: View {
    @EnvironmentObject var vm: ViewerModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if vm.files.isEmpty {
                VStack(spacing: 20) {
                    // Use app icon instead of blue logo
                    Group {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .cornerRadius(16)
                        } else {
                            // Fallback to system icon if AppIcon not found
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text("Glass Photos")
                        .font(.largeTitle)
                        .fontWeight(.light)
                        .foregroundStyle(.white)
                    
                    VStack(spacing: 12) {
                        Button("Open Folder…") { vm.pickFolder() }
                            .keyboardShortcut("o", modifiers: .command)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .frame(maxWidth: 400)
                .padding(40)
            } else if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .foregroundStyle(.white)
                    Text("Loading photos...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Viewer()
            }
        }
        .onAppear {
            print("ContentView appeared")
            print("Files count: \(vm.files.count)")
            print("Is loading: \(vm.isLoading)")
            vm.startKeyMonitor()
            
            // Listen for files opened with the app
            NotificationCenter.default.addObserver(
                forName: .filesOpened,
                object: nil,
                queue: .main
            ) { notification in
                if let urls = notification.object as? [URL] {
                    print("Received files opened notification: \(urls.count) files")
                    vm.handleOpenedFiles(urls)
                }
            }
        }
        .onChange(of: vm.files.count) { count in
            print("Files count changed to: \(count)")
        }
        .onChange(of: vm.isLoading) { loading in
            print("Loading state changed to: \(loading)")
        }
        .onDisappear { vm.stopKeyMonitor() }
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
        HStack(spacing: 0) {
            // Main content area
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
                        },
                        onInfoToggle: { vm.toggleInfoSidebar() },
                        onShare: { vm.shareCurrentImage() }
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
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
            
            // Info sidebar
            if vm.showInfoSidebar {
                InfoSidebar(
                    exifData: vm.currentExifData,
                    isLoading: vm.isLoadingExif,
                    onClose: { vm.showInfoSidebar = false }
                )
                .frame(width: 300)
                .transition(.move(edge: .trailing))
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
    let onInfoToggle: () -> Void
    let onShare: () -> Void
    
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
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                }
            }
            
            Spacer()
            
            // Action buttons on the right
            HStack(spacing: 8) {
                // Info button
                Button(action: onInfoToggle) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Show Image Info")
                
                // Share button
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Share Image")
                
                // Fullscreen button
                Button(action: onFullScreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Enter Full Screen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
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
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
            Spacer()
            Text("← / → navigate • Space fit • F full screen")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
    }
}

// Helpers
extension Collection { subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil } }

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

struct InfoSidebar: View {
    let exifData: [(String, Any)]
    let isLoading: Bool
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Image Info")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.separator),
                alignment: .bottom
            )
            
            // Content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .foregroundStyle(.white)
                            
                            Text("Loading metadata...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if exifData.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            
                            Text("No metadata available")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Text("This image doesn't contain EXIF data or metadata information.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(Array(exifData.enumerated()), id: \.offset) { index, item in
                            InfoRow(title: item.0, value: "\(item.1)")
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(.separator),
            alignment: .leading
        )
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



