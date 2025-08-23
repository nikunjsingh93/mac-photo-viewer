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
        WindowGroup("Glass Photo Viewer") {
            ContentView()
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
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { vm.pickFolder() }
                    .keyboardShortcut("o", modifiers: .command)
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
            // If individual files were opened, load their containing folder
            let folderURLs = Set(imageFiles.map { $0.deletingLastPathComponent() })
            if let firstFolder = folderURLs.first {
                loadFolder(firstFolder)
                // Find the index of the first opened file
                if let firstFile = imageFiles.first {
                    if let fileIndex = files.firstIndex(of: firstFile) {
                        index = fileIndex
                    }
                }
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
            guard let e = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { 
                print("Failed to enumerate directory")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return 
            }

            var imgs: [URL] = []
            for case let u as URL in e {
                let ext = u.pathExtension.lowercased()
                if self.allowed.contains(ext) { imgs.append(u) }
            }
            imgs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            print("Found \(imgs.count) images in folder")
            
            DispatchQueue.main.async {
                self.files = imgs
                self.index = 0
                self.isLoading = false
                self.preloadNeighbors()
                print("Folder loaded successfully, files count: \(self.files.count)")
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
    func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }

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

struct ContentView: View {
    @EnvironmentObject var vm: ViewerModel
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            
            if vm.files.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Glass Photo Viewer").font(.largeTitle).fontWeight(.light)
                    Text("Welcome to your photo viewer!").font(.title3).foregroundStyle(.secondary)
                    
                    Button("Open Folder…") { vm.pickFolder() }
                        .keyboardShortcut("o", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: 400)
                .padding(40)
            } else if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
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
            vm.startKeyMonitor()
            
            // Listen for files opened with the app
            NotificationCenter.default.addObserver(
                forName: .filesOpened,
                object: nil,
                queue: .main
            ) { notification in
                if let urls = notification.object as? [URL] {
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
    var body: some View {
        GeometryReader { geo in
            if let url = vm.files[safe: vm.index], let nsimg = vm.image(for: url) {
                let imageView = Image(nsImage: nsimg).interpolation(.high).antialiased(true)
                Group {
                    if vm.fitToWindow {
                        imageView.resizable().scaledToFit()
                            .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            imageView.resizable().aspectRatio(contentMode: .fit).fixedSize()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { vm.toggleFullScreen() } // double-click full screen
                .overlay(alignment: .bottom) {
                    HUD(url: url, index: vm.index + 1, total: vm.files.count)
                }
                .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.width < 0 { vm.next() }
                    if value.translation.width > 0 { vm.prev() }
                })
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
}

// ---- Previews (inject env object!) ----
#Preview {
    ContentView().environmentObject(ViewerModel())
}
