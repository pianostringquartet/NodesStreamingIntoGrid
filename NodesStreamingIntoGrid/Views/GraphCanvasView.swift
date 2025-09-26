//
//  GraphCanvasView.swift
//  NodesStreamingIntoGrid
//
//  Main graph visualization with debug overlays
//

import SwiftUI

struct GraphCanvasView: View {
    var layoutManager: GraphLayoutManager
    let selectedNodeId: String
    let onNodeSelected: (String) -> Void
    @State private var showGrid = true
    @State private var showCoordinates = true
    @State private var animateChanges = true
    @State private var hoveredNodeId: String? = nil

    let gridSize: CGFloat = 75
    let nodeSize: CGFloat = 50

    var body: some View {
        ZStack {
            Color.gray.opacity(0.05)
                .edgesIgnoringSafeArea(.all)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if showGrid {
                        GridOverlay(gridSize: gridSize)
                    }

                    EdgeLayer(edges: layoutManager.edges, nodes: layoutManager.nodes)

                    NodeLayer(
                        nodes: layoutManager.nodes,
                        nodeSize: nodeSize,
                        showCoordinates: showCoordinates,
                        hoveredNodeId: $hoveredNodeId,
                        selectedNodeId: selectedNodeId,
                        animateChanges: animateChanges,
                        onNodeSelected: onNodeSelected
                    )
                }
                .frame(width: 2000, height: 1000)
//                .frame(width: 2000)
            }
            

//            VStack {
//                HStack {
////                    Toggle("Grid", isOn: $showGrid)
////                    Toggle("Coordinates", isOn: $showCoordinates)
////                    Toggle("Animate", isOn: $animateChanges)
//                    Spacer()
//                }
//                .padding()
//                .background(Color.white.opacity(0.9))
//                Spacer()
//            }
        }
    }
}

struct GridOverlay: View {
    let gridSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / gridSize)
            let rows = Int(size.height / gridSize)

            for col in 0...columns {
                let x = CGFloat(col) * gridSize
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.gray.opacity(0.2)),
                    lineWidth: 0.5
                )
            }

            for row in 0...rows {
                let y = CGFloat(row) * gridSize
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(.gray.opacity(0.2)),
                    lineWidth: 0.5
                )
            }

            for col in 0...columns {
                for row in 0...rows {
                    let point = CGPoint(x: CGFloat(col) * gridSize, y: CGFloat(row) * gridSize)
                    context.fill(
                        Path { path in
                            path.addEllipse(in: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                        },
                        with: .color(.gray.opacity(0.3))
                    )
                }
            }
        }
    }
}

struct EdgeLayer: View {
    let edges: [Edge]
    let nodes: [Node]

    var body: some View {
        ForEach(edges) { edge in
            if let fromNode = nodes.first(where: { $0.id == edge.from }),
               let toNode = nodes.first(where: { $0.id == edge.to }) {
                EdgeView(from: fromNode.gridPosition, to: toNode.gridPosition)
                    .onAppear {
                        _ = logInView("Drawing edge \(edge.from) → \(edge.to)")
                    }
            }
        }
    }
}

struct EdgeView: View {
    let from: GridPosition
    let to: GridPosition

    var body: some View {
        Path { path in
            let start = from.pixelPosition
            let end = to.pixelPosition
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(Color.blue.opacity(0.6), lineWidth: 2)

        Path { path in
            let end = to.pixelPosition
            let start = from.pixelPosition
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 10
            let arrowAngle: CGFloat = .pi / 6

            let arrowPoint1 = CGPoint(
                x: end.x - arrowLength * cos(angle - arrowAngle),
                y: end.y - arrowLength * sin(angle - arrowAngle)
            )
            let arrowPoint2 = CGPoint(
                x: end.x - arrowLength * cos(angle + arrowAngle),
                y: end.y - arrowLength * sin(angle + arrowAngle)
            )

            path.move(to: end)
            path.addLine(to: arrowPoint1)
            path.move(to: end)
            path.addLine(to: arrowPoint2)
        }
        .stroke(Color.blue.opacity(0.6), lineWidth: 2)
    }
}

struct NodeLayer: View {
    let nodes: [Node]
    let nodeSize: CGFloat
    let showCoordinates: Bool
    @Binding var hoveredNodeId: String?
    let selectedNodeId: String
    let animateChanges: Bool
    let onNodeSelected: (String) -> Void

    var body: some View {
        ForEach(nodes) { node in
            NodeView(
                node: node,
                size: nodeSize,
                showCoordinates: showCoordinates,
                isHovered: hoveredNodeId == node.id,
                isSelected: selectedNodeId == node.id,
                animateChanges: animateChanges,
                onTap: { onNodeSelected(node.id) }
            )
            .onHover { isHovered in
                let previousId = hoveredNodeId
                hoveredNodeId = isHovered ? node.id : nil
                _ = logInView("Hover change: \(previousId ?? "nil") → \(hoveredNodeId ?? "nil") for node \(node.id)")
            }
        }
    }
}

struct NodeView: View {
    let node: Node
    let size: CGFloat
    let showCoordinates: Bool
    let isHovered: Bool
    let isSelected: Bool
    let animateChanges: Bool
    let onTap: () -> Void

    // Cache the pixel position to prevent recalculation during hover
    private var cachedPixelPosition: CGPoint {
        CGPoint(x: CGFloat(Double(node.col * 75) + 37.5), y: CGFloat(Double(node.row * 75) + 37.5))
    }

    // Visual state computed properties
    private var nodeColor: Color {
        if isSelected {
            return Color.green
        } else if isHovered {
            return Color.orange
        } else {
            return Color.blue
        }
    }

    private var strokeColor: Color {
        isSelected ? Color.white : Color.white
    }

    private var strokeWidth: CGFloat {
        isSelected ? 3 : 2
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(nodeColor)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )

            VStack(spacing: 2) {
                Text(node.id)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                if showCoordinates || isHovered {
                    Text("(\(node.col),\(node.row))")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .position(cachedPixelPosition)
        .onTapGesture {
            onTap()
            _ = logInView("Node \(node.id) tapped for selection")
        }
        .animation(
            animateChanges ? .spring(response: 0.5, dampingFraction: 0.8) : nil,
            value: "\(node.col),\(node.row)"
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onAppear {
            _ = logInView("Node \(node.id) appeared at \(node.gridPosition)")
        }
        .onChange(of: node.gridPosition) { oldPos, newPos in
            _ = logInView("Node \(node.id) position changed: \(oldPos) → \(newPos)")
        }
        .onChange(of: isHovered) { wasHovered, nowHovered in
            _ = logInView("Node \(node.id) hover state: \(wasHovered) → \(nowHovered)")
        }
    }
}
