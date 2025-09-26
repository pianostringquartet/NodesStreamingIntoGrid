//
//  GraphLayoutManager.swift
//  NodesStreamingIntoGrid
//
//  Main graph layout management with extensive logging
//

import SwiftUI

@Observable
class GraphLayoutManager {
    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []

    private var adjacencyList: [String: Set<String>] = [:]
    private var reverseAdjacencyList: [String: Set<String>] = [:]
    private let logger = GraphLogger.shared

    private var occupiedPositions: Set<GridPosition> {
        Set(nodes.map { $0.gridPosition })
    }

    init() {
        logger.log("GraphLayoutManager initialized", level: .info, category: "System")
    }

    func findNode(byId id: String) -> Node? {
        let node = nodes.first { $0.id == id }
        logger.log("Finding node '\(id)': \(node != nil ? "Found" : "Not found")",
                  level: .verbose, category: "Lookup")
        return node
    }

    func isPositionOccupied(_ position: GridPosition) -> Bool {
        let occupied = nodes.contains { $0.gridPosition == position }
        logger.logPositionSearch(position, occupied: occupied)
        return occupied
    }

    func addNode(_ node: Node) {
        logger.logNodeOperation("Adding", node: node.id, details: "at \(node.gridPosition)")
        nodes.append(node)
        adjacencyList[node.id] = Set()
        reverseAdjacencyList[node.id] = Set()
    }

    func addEdge(from: String, to: String) {
        logger.logEdge(from, to, created: true)
        let edge = Edge(from: from, to: to)
        edges.append(edge)
        adjacencyList[from, default: Set()].insert(to)
        reverseAdjacencyList[to, default: Set()].insert(from)
    }

    func addNodeUpstream(newId: String, of targetId: String) {
        logger.log("=== UPSTREAM INSERTION START ===", level: .info, category: "Operation")
        logger.log("Adding '\(newId)' upstream of '\(targetId)'", level: .info, category: "Operation")

        guard let targetNode = findNode(byId: targetId) else {
            logger.log("Target node '\(targetId)' not found", level: .error, category: "Operation")
            return
        }

        let idealPosition = GridPosition(col: targetNode.col - 1, row: targetNode.row)
        logger.log("Ideal position for '\(newId)': \(idealPosition)", level: .info, category: "Placement")

        if !isPositionOccupied(idealPosition) {
            logger.log("Ideal position is FREE - placing directly", level: .success, category: "Placement")
            let newNode = Node(id: newId, col: idealPosition.col, row: idealPosition.row)
            addNode(newNode)
            addEdge(from: newId, to: targetId)
        } else {
            logger.log("Ideal position is OCCUPIED - need to resolve conflict", level: .warning, category: "Placement")
            handleUpstreamConflict(newId: newId, targetId: targetId, idealPosition: idealPosition)
        }

        updateTopologicalOrder()

        // Validate the result
        _ = validateNoOverlaps()
        _ = validateTopologicalOrder()

        logger.log("=== UPSTREAM INSERTION COMPLETE ===", level: .info, category: "Operation")
    }

    func addNodeDownstream(newId: String, of sourceId: String) {
        logger.log("=== DOWNSTREAM INSERTION START ===", level: .info, category: "Operation")
        logger.log("Adding '\(newId)' downstream of '\(sourceId)'", level: .info, category: "Operation")

        guard let sourceNode = findNode(byId: sourceId) else {
            logger.log("Source node '\(sourceId)' not found", level: .error, category: "Operation")
            return
        }

        let idealPosition = GridPosition(col: sourceNode.col + 1, row: sourceNode.row)
        logger.log("Ideal position for '\(newId)': \(idealPosition)", level: .info, category: "Placement")

        if !isPositionOccupied(idealPosition) {
            logger.log("Ideal position is FREE - placing directly", level: .success, category: "Placement")
            let newNode = Node(id: newId, col: idealPosition.col, row: idealPosition.row)
            addNode(newNode)
            addEdge(from: sourceId, to: newId)
        } else {
            logger.log("Ideal position is OCCUPIED - need to resolve conflict", level: .warning, category: "Placement")
            handleDownstreamConflict(newId: newId, sourceId: sourceId, idealPosition: idealPosition)
        }

        updateTopologicalOrder()

        // Validate the result
        _ = validateNoOverlaps()
        _ = validateTopologicalOrder()

        logger.log("=== DOWNSTREAM INSERTION COMPLETE ===", level: .info, category: "Operation")
    }

    private func handleUpstreamConflict(newId: String, targetId: String, idealPosition: GridPosition) {
        logger.log("Handling upstream conflict for '\(newId)'", level: .info, category: "Conflict")

        logger.log("Strategy: Shift target branch right to make space", level: .info, category: "Strategy")
        shiftBranchRight(startingFrom: targetId)

        // Re-check if the ideal position is now free after shifting
        if !isPositionOccupied(idealPosition) {
            logger.log("Ideal position \(idealPosition) is now FREE after branch shift", level: .success, category: "Conflict")
            let newNode = Node(id: newId, col: idealPosition.col, row: idealPosition.row)
            addNode(newNode)
            addEdge(from: newId, to: targetId)
            logger.log("Placed '\(newId)' at ideal position after branch shift", level: .success, category: "Placement")
        } else {
            logger.log("Ideal position \(idealPosition) is still OCCUPIED after branch shift", level: .warning, category: "Conflict")
            let alternativePosition = findNearestFreePosition(near: idealPosition, inColumn: idealPosition.col)
            logger.log("Using alternative position: \(alternativePosition)", level: .info, category: "Conflict")

            let newNode = Node(id: newId, col: alternativePosition.col, row: alternativePosition.row)
            addNode(newNode)
            addEdge(from: newId, to: targetId)
            logger.log("Placed '\(newId)' at alternative position after conflict", level: .success, category: "Placement")
        }
    }

    private func handleDownstreamConflict(newId: String, sourceId: String, idealPosition: GridPosition) {
        logger.log("Handling downstream conflict for '\(newId)'", level: .info, category: "Conflict")

        let alternativePosition = findNearestFreePosition(near: idealPosition, inColumn: idealPosition.col)
        logger.log("Found alternative position: \(alternativePosition)", level: .info, category: "Placement")

        let newNode = Node(id: newId, col: alternativePosition.col, row: alternativePosition.row)
        addNode(newNode)
        addEdge(from: sourceId, to: newId)
        logger.log("Placed '\(newId)' at alternative position", level: .success, category: "Placement")
    }

    private func findNearestFreePosition(near target: GridPosition, inColumn col: Int) -> GridPosition {
        logger.log("Searching for free position near \(target) in column \(col)", level: .verbose, category: "Search")

        for offset in 0...10 {
            if offset == 0 && !isPositionOccupied(target) {
                return target
            }

            let above = GridPosition(col: col, row: target.row - offset)
            if offset > 0 && !isPositionOccupied(above) {
                logger.log("Found free position \(offset) row(s) above", level: .success, category: "Search")
                return above
            }

            let below = GridPosition(col: col, row: target.row + offset)
            if offset > 0 && !isPositionOccupied(below) {
                logger.log("Found free position \(offset) row(s) below", level: .success, category: "Search")
                return below
            }
        }

        let fallback = GridPosition(col: col, row: target.row + 11)
        logger.log("Using fallback position far below: \(fallback)", level: .warning, category: "Search")
        return fallback
    }

    private func shiftBranchRight(startingFrom nodeId: String) {
        logger.log("Starting branch shift from '\(nodeId)'", level: .info, category: "Shift")

        var toVisit: Set<String> = [nodeId]
        var visited: Set<String> = []
        var nodesToShift: [String] = []

        while !toVisit.isEmpty {
            let current = toVisit.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            nodesToShift.append(current)

            if let children = adjacencyList[current] {
                toVisit.formUnion(children)
            }
        }

        logger.log("Branch contains \(nodesToShift.count) node(s): \(nodesToShift.joined(separator: ", "))",
                  level: .info, category: "Shift")

        for nodeId in nodesToShift {
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                let oldPos = nodes[index].gridPosition
                nodes[index].col += 1
                let newPos = nodes[index].gridPosition
                logger.logShift(nodeId, from: oldPos, to: newPos)
            }
        }

        logger.log("Branch shift complete", level: .success, category: "Shift")
    }

    private func updateTopologicalOrder() {
        logger.log("Updating topological order", level: .verbose, category: "Topology")

        var inDegree: [String: Int] = [:]
        for node in nodes {
            inDegree[node.id] = reverseAdjacencyList[node.id]?.count ?? 0
        }

        var queue: [String] = nodes.compactMap { inDegree[$0.id] == 0 ? $0.id : nil }
        var order: [String] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            order.append(current)

            for next in adjacencyList[current] ?? [] {
                inDegree[next]! -= 1
                if inDegree[next] == 0 {
                    queue.append(next)
                }
            }
        }

        if order.count == nodes.count {
            logger.logTopology(order)
            assignLayers(basedOn: order)
        } else {
            logger.log("Cycle detected in graph!", level: .error, category: "Topology")
        }
    }

    private func assignLayers(basedOn order: [String]) {
        logger.log("Assigning layers based on topological order", level: .verbose, category: "Layers")

        var layerMap: [String: Int] = [:]

        for nodeId in order {
            let predecessors = reverseAdjacencyList[nodeId] ?? []
            if predecessors.isEmpty {
                layerMap[nodeId] = 0
            } else {
                let maxPredLayer = predecessors.compactMap { layerMap[$0] }.max() ?? -1
                layerMap[nodeId] = maxPredLayer + 1
            }
        }

        for (nodeId, layer) in layerMap {
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                let oldCol = nodes[index].col
                if oldCol != layer {
                    logger.log("Adjusting '\(nodeId)' column from \(oldCol) to \(layer)",
                             level: .verbose, category: "Layers")
                    nodes[index].col = layer
                }
            }
        }
    }

    func addDisconnectedNode(id: String) {
        logger.log("Adding disconnected node '\(id)'", level: .info, category: "Operation")

        let position = findPositionForDisconnectedNode()
        let node = Node(id: id, col: position.col, row: position.row)
        addNode(node)

        logger.log("Placed disconnected node '\(id)' at \(position)", level: .success, category: "Placement")
    }

    private func findPositionForDisconnectedNode() -> GridPosition {
        let maxRow = nodes.map { $0.row }.max() ?? -1
        return GridPosition(col: 0, row: maxRow + 2)
    }

    func clear() {
        logger.log("Clearing graph", level: .info, category: "System")
        nodes.removeAll()
        edges.removeAll()
        adjacencyList.removeAll()
        reverseAdjacencyList.removeAll()
    }

    // MARK: - Validation Methods

    func validateNoOverlaps() -> Bool {
        let positions = nodes.map { $0.gridPosition }
        let uniquePositions = Set(positions)
        let hasOverlaps = positions.count != uniquePositions.count

        if hasOverlaps {
            logger.log("VALIDATION FAILED: Node position overlaps detected!", level: .error, category: "Validation")
            let duplicates = Dictionary(grouping: nodes, by: { $0.gridPosition })
                .filter { $1.count > 1 }
            for (position, nodes) in duplicates {
                logger.log("Overlap at \(position): \(nodes.map { $0.id }.joined(separator: ", "))",
                          level: .error, category: "Validation")
            }
        } else {
            logger.log("Validation passed: No node overlaps", level: .verbose, category: "Validation")
        }

        return !hasOverlaps
    }

    func validateTopologicalOrder() -> Bool {
        for edge in edges {
            guard let fromNode = findNode(byId: edge.from),
                  let toNode = findNode(byId: edge.to) else {
                logger.log("VALIDATION FAILED: Edge references non-existent node: \(edge)",
                          level: .error, category: "Validation")
                return false
            }

            if fromNode.col >= toNode.col {
                logger.log("VALIDATION FAILED: Edge violates topological order: \(edge.from)@\(fromNode.col) → \(edge.to)@\(toNode.col)",
                          level: .error, category: "Validation")
                return false
            }
        }

        logger.log("Validation passed: Topological order maintained", level: .verbose, category: "Validation")
        return true
    }
}