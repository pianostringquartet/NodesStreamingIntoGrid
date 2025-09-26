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
    @State private var logText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Console Log")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(SwitchToggleStyle())
                Button("Clear") {
                    logger.clear()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.gray.opacity(0.3))

            // Console Text Display
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logger.allLogsAsText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .textSelection(.enabled) // Enable text selection
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("consoleText")
                }
                .background(Color.clear)
                .onChange(of: logger.logs.count) { _ in
                    if autoScroll {
                        // Scroll to bottom when new logs arrive
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("consoleText", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

