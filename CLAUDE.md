# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Type
SwiftUI macOS/iOS Application built with Xcode

## Build and Development Commands

### Building the Project
```bash
# Open in Xcode
open NodesStreamingIntoGrid.xcodeproj

# Build from command line (requires Xcode Command Line Tools)
xcodebuild -project NodesStreamingIntoGrid.xcodeproj -scheme NodesStreamingIntoGrid build

# Clean build
xcodebuild -project NodesStreamingIntoGrid.xcodeproj -scheme NodesStreamingIntoGrid clean
```

### Running the Application
```bash
# Run in simulator
xcodebuild -project NodesStreamingIntoGrid.xcodeproj -scheme NodesStreamingIntoGrid -destination 'platform=iOS Simulator,name=iPhone 16' run

# Run on macOS
xcodebuild -project NodesStreamingIntoGrid.xcodeproj -scheme NodesStreamingIntoGrid -destination 'platform=macOS' run
```

### Testing
```bash
# Run all tests
xcodebuild test -project NodesStreamingIntoGrid.xcodeproj -scheme NodesStreamingIntoGrid -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project Structure

The project follows standard SwiftUI application architecture:

- **NodesStreamingIntoGrid/** - Main application source code directory
  - `NodesStreamingIntoGridApp.swift` - App entry point with @main annotation
  - `ContentView.swift` - Main view containing the primary UI
  - `Assets.xcassets/` - Asset catalog for app icons and colors

- **NodesStreamingIntoGrid.xcodeproj/** - Xcode project configuration

## Architecture Overview

This is a SwiftUI application that appears to be designed for displaying or managing nodes in a grid layout. The current implementation is minimal with:

- Standard SwiftUI app structure using `App` protocol
- Single `ContentView` as the main UI component
- WindowGroup scene for multi-platform support

The app name "NodesStreamingIntoGrid" suggests it will involve:
- Node-based visualization or interaction
- Grid layout system
- Potentially streaming or animated content

## Development Notes

- Uses SwiftUI's declarative syntax for UI
- Targets Xcode 26.0.1 or later
- No external package dependencies currently configured
- Standard preview support included in ContentView