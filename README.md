# Glass Photo Viewer

A beautiful, modern photo viewer for macOS with a focus on simplicity and performance.

## Features

### 🖼️ **Open with Photos by Default**
- **Auto-opens Pictures folder** when the app launches
- **File type associations** - double-click any image file to open it in the app
- **Drag and drop support** - drop images or folders directly onto the app
- **Recent folders** - quickly access previously opened folders

### 🎯 **Easy Navigation**
- **Keyboard shortcuts**:
  - `←` / `→` - Navigate between photos
  - `Space` - Toggle fit to window
  - `F` - Toggle fullscreen
  - `Esc` - Exit fullscreen
  - `Cmd+O` - Open folder
  - `Cmd+Shift+P` - Open Pictures folder
  - `Cmd+Shift+R` - Open recent folders

- **Mouse/Trackpad**:
  - **Swipe left/right** - Navigate between photos
  - **Double-click** - Toggle fullscreen
  - **Scroll** - Zoom in/out when not in fit mode

### 🚀 **Performance**
- **Smart caching** - Images are cached for smooth navigation
- **Background loading** - Photos load in the background for better performance
- **Preloading** - Adjacent images are preloaded for instant navigation

### 📁 **Supported Formats**
- **Common formats**: JPG, JPEG, PNG, WebP, HEIC, HEIF, TIFF, GIF, BMP
- **RAW formats**: DNG, NEF, CR2, ARW, RAF

## How to Use

### Opening Photos
1. **Launch the app** - It will automatically open your Pictures folder
2. **Double-click any image file** - The app will open with that image
3. **Drag and drop** - Drop images or folders onto the app window
4. **Use the menu** - File → Open Folder to browse for photos

### Navigation
- Use arrow keys or swipe gestures to navigate between photos
- Press Space to toggle between fit-to-window and actual size
- Press F or double-click to enter/exit fullscreen mode

### Recent Folders
- The app remembers your recently opened folders
- Use `Cmd+Shift+R` to quickly access recent folders
- Up to 10 recent folders are saved

## Installation

1. Build the project in Xcode
2. The app will be associated with image files automatically
3. You can also drag the app to your Applications folder

## System Requirements

- macOS 13.0 or later
- SwiftUI 4.0+
- 4GB RAM recommended for large photo collections

## Tips

- **Large folders**: The app handles large photo collections efficiently with background loading
- **RAW files**: RAW format support for professional photographers
- **Fullscreen mode**: Perfect for photo presentations or immersive viewing
- **Keyboard shortcuts**: Learn the shortcuts for the fastest workflow

Enjoy viewing your photos with Glass Photo Viewer! 📸
