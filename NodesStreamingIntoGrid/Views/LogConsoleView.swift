//
//  LogConsoleView.swift
//  NodesStreamingIntoGrid
//
//  Console view for displaying graph operation logs
//

import SwiftUI

struct LogConsoleView: View {
    var logger = GraphLogger.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console Log")
                    .font(.headline)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                Button("Clear") {
                    logger.clear()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logger.logs) { entry in
                            LogEntryView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: logger.logs.count) { _ in
                    if autoScroll, let lastLog = logger.logs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.9))
        .foregroundColor(.white)
    }
}

struct LogEntryView: View {
    let entry: GraphLogger.LogEntry

    var textColor: Color {
        switch entry.level {
        case .verbose: return .gray
        case .info: return .white
        case .warning: return .yellow
        case .error: return .red
        case .success: return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue)
                .font(.system(size: 12))

            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)

            Text("[\(entry.category)]")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.cyan)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)

            Spacer()
        }
        .padding(.vertical, 1)
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.timestamp)
    }
}