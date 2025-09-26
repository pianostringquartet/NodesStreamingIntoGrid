//
//  ContentView.swift
//  NodesStreamingIntoGrid
//
//  Created by Christian J Clampitt on 9/26/25.
//

import SwiftUI

struct ContentView: View {
    @State private var layoutManager = GraphLayoutManager()
    @State private var logger = GraphLogger.shared
    @State private var newNodeId = ""
    @State private var selectedNodeId = ""
    @State private var nodeCounter = 1
    @State private var showConsole = true

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                GraphCanvasView(
                    layoutManager: layoutManager,
                    selectedNodeId: selectedNodeId,
                    onNodeSelected: { nodeId in
                        selectedNodeId = nodeId
                        logger.log("Node '\(nodeId)' selected via tap", level: .info, category: "UI")
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ControlPanel(
                    layoutManager: $layoutManager,
                    newNodeId: $newNodeId,
                    selectedNodeId: $selectedNodeId,
                    nodeCounter: $nodeCounter,
                    logger: $logger
                )
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            }

            if showConsole {
                LogConsoleView()
                    .frame(minWidth: 400, maxWidth: 600)
                    .frame(maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle("Console", isOn: $showConsole)
            }
        }
        .onAppear {
            setupInitialGraph()
        }
    }

    func setupInitialGraph() {
        logger.log("Setting up initial graph", level: .info, category: "Setup")

        let nodeA = Node(id: "A", col: 1, row: 1)
        layoutManager.addNode(nodeA)

        let nodeB = Node(id: "B", col: 2, row: 1)
        layoutManager.addNode(nodeB)
        layoutManager.addEdge(from: "A", to: "B")

        let nodeC = Node(id: "C", col: 2, row: 2)
        layoutManager.addNode(nodeC)
        layoutManager.addEdge(from: "A", to: "C")

        logger.log("Initial graph setup complete", level: .success, category: "Setup")
    }
}

struct ControlPanel: View {
    @Binding var layoutManager: GraphLayoutManager
    @Binding var newNodeId: String
    @Binding var selectedNodeId: String
    @Binding var nodeCounter: Int
    @Binding var logger: GraphLogger

    var availableNodes: [String] {
        layoutManager.nodes.map { $0.id }.sorted()
    }

    var body: some View {
        VStack {
            HStack {
                Text("Graph Controls")
                    .font(.headline)
                Spacer()
                Text("Nodes: \(layoutManager.nodes.count)")
                Text("Edges: \(layoutManager.edges.count)")
            }
            .padding(.bottom)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("New Node ID:")
                    TextField("Enter ID or use auto", text: $newNodeId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                VStack(alignment: .leading) {
                    Text("Target Node:")
                    Picker("", selection: $selectedNodeId) {
                        Text("Select...").tag("")
                        ForEach(availableNodes, id: \.self) { nodeId in
                            Text(nodeId).tag(nodeId)
                        }
                    }
                    .frame(width: 150)
                }

                VStack(alignment: .leading) {
                    Text("Add Node:")
                    HStack {
                        Button("Upstream ←") {
                            addNodeUpstream()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedNodeId.isEmpty)

                        Button("Downstream →") {
                            addNodeDownstream()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedNodeId.isEmpty)

                        Button("Disconnected ○") {
                            addDisconnectedNode()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack {
                Button("Clear Graph") {
                    layoutManager.clear()
                    nodeCounter = 1
                    selectedNodeId = ""
                    newNodeId = ""
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(.white)
                .tint(.red)

                Button("Add Test Scenario") {
                    addTestScenario()
                }
                .buttonStyle(.bordered)

                Toggle("Verbose Logs", isOn: $logger.enableVerbose)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }

    func addNodeUpstream() {
        let nodeId = newNodeId.isEmpty ? "N\(nodeCounter)" : newNodeId
        logger.log("User action: Add '\(nodeId)' upstream of '\(selectedNodeId)'", level: .info, category: "UI")
        layoutManager.addNodeUpstream(newId: nodeId, of: selectedNodeId)
        nodeCounter += 1
        newNodeId = ""
    }

    func addNodeDownstream() {
        let nodeId = newNodeId.isEmpty ? "N\(nodeCounter)" : newNodeId
        logger.log("User action: Add '\(nodeId)' downstream of '\(selectedNodeId)'", level: .info, category: "UI")
        layoutManager.addNodeDownstream(newId: nodeId, of: selectedNodeId)
        nodeCounter += 1
        newNodeId = ""
    }

    func addDisconnectedNode() {
        let nodeId = newNodeId.isEmpty ? "N\(nodeCounter)" : newNodeId
        logger.log("User action: Add disconnected node '\(nodeId)'", level: .info, category: "UI")
        layoutManager.addDisconnectedNode(id: nodeId)
        nodeCounter += 1
        newNodeId = ""
    }

    func addTestScenario() {
        logger.log("Adding test scenario: Complex branch conflict", level: .info, category: "Test")

        layoutManager.addNodeDownstream(newId: "D", of: "B")
        layoutManager.addNodeDownstream(newId: "E", of: "B")
        layoutManager.addNodeUpstream(newId: "X", of: "B")
        layoutManager.addNodeUpstream(newId: "Y", of: "C")
    }
}

#Preview {
    ContentView()
}
