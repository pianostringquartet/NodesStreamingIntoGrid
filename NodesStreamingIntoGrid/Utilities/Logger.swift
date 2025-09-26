//
//  Logger.swift
//  NodesStreamingIntoGrid
//
//  Centralized logging utilities
//

import SwiftUI

enum LogLevel: String {
    case verbose = "🔍"
    case info = "ℹ️"
    case warning = "⚠️"
    case error = "❌"
    case success = "✅"
}

@Observable
class GraphLogger {
    static let shared = GraphLogger()

    var logs: [LogEntry] = []
    var enableVerbose = true

    // Unified text output for TextEditor
    var allLogsAsText: String {
        logs.map { entry in
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = timeFormatter.string(from: entry.timestamp)
            return "\(entry.level.rawValue) [\(timestamp)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let level: LogLevel
        let message: String
        let category: String

        var formatted: String {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss.SSS"
            return "\(level.rawValue) [\(category)] \(message)"
        }
    }

    func log(_ message: String, level: LogLevel = .info, category: String = "General") {
        if level == .verbose && !enableVerbose { return }

        let entry = LogEntry(level: level, message: message, category: category)
        DispatchQueue.main.async {
            self.logs.append(entry)
            // Keep a reasonable limit to prevent memory issues
            if self.logs.count > 500 {
                self.logs.removeFirst(100) // Remove oldest 100 entries
            }
        }
        print(entry.formatted)
    }

    func logNodeOperation(_ operation: String, node: String, details: String = "") {
        let message = "Node '\(node)': \(operation)" + (details.isEmpty ? "" : " - \(details)")
        log(message, level: .info, category: "Node")
    }

    func logPositionSearch(_ position: GridPosition, occupied: Bool, reason: String = "") {
        let message = "Position \(position): \(occupied ? "OCCUPIED" : "FREE")" + (reason.isEmpty ? "" : " - \(reason)")
        log(message, level: .verbose, category: "Position")
    }

    func logShift(_ nodeId: String, from: GridPosition, to: GridPosition) {
        log("Shifting '\(nodeId)' from \(from) to \(to)", level: .info, category: "Shift")
    }

    func logEdge(_ from: String, _ to: String, created: Bool = true) {
        log("\(created ? "Created" : "Removed") edge: \(from) → \(to)", level: .info, category: "Edge")
    }

    func logTopology(_ order: [String]) {
        log("Topological order: \(order.joined(separator: " → "))", level: .verbose, category: "Topology")
    }

    func clear() {
        logs.removeAll()
    }
}

func logInView(_ message: String) -> EmptyView {
    print("🎨 [View] \(message)")
    return EmptyView()
}