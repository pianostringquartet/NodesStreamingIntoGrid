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

    // Position tracking dictionary - single source of truth for cell occupancy
    private var positionMap: [GridPosition: String] = [:]

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

        // Critical: Reserve position BEFORE adding to nodes array
        if !reservePosition(for: node.id, at: node.gridPosition) {
            logger.log("CRITICAL ERROR: Cannot add node '\(node.id)' - position \(node.gridPosition) is occupied!",
                      level: .error, category: "Position")
            assertionFailure("Attempted to add node to occupied position")
            return
        }

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

        if !isPositionOccupiedInMap(idealPosition) {
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

        if !isPositionOccupiedInMap(idealPosition) {
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

        // Recalculate ideal position based on target's new location for better proximity
        guard let targetNode = findNode(byId: targetId) else {
            logger.log("ERROR: Target node '\(targetId)' not found after branch shift", level: .error, category: "Conflict")
            return
        }

        let proximityIdealPosition = GridPosition(col: targetNode.col - 1, row: targetNode.row)
        logger.log("Recalculated proximity-focused ideal position: \(proximityIdealPosition) (target is now at \(targetNode.gridPosition))",
                  level: .info, category: "Proximity")

        // Try proximity-focused position first
        if !isPositionOccupiedInMap(proximityIdealPosition) {
            logger.log("Proximity ideal position \(proximityIdealPosition) is FREE", level: .success, category: "Proximity")
            let newNode = Node(id: newId, col: proximityIdealPosition.col, row: proximityIdealPosition.row)
            addNode(newNode)
            addEdge(from: newId, to: targetId)
            logger.log("Placed '\(newId)' at proximity ideal position for visual continuity", level: .success, category: "Placement")
            return
        }

        // If proximity position is occupied, search near it for better visual results
        logger.log("Proximity ideal position \(proximityIdealPosition) is OCCUPIED - searching nearby", level: .warning, category: "Proximity")
        let alternativePosition = findNearestFreePositionInMap(near: proximityIdealPosition, inColumn: proximityIdealPosition.col)
        logger.log("Using proximity-focused alternative position: \(alternativePosition)", level: .info, category: "Proximity")

        let newNode = Node(id: newId, col: alternativePosition.col, row: alternativePosition.row)
        addNode(newNode)
        addEdge(from: newId, to: targetId)
        logger.log("Placed '\(newId)' at proximity-focused alternative position", level: .success, category: "Placement")
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

    private func findNearestFreePositionInMap(near target: GridPosition, inColumn col: Int) -> GridPosition {
        logger.log("Searching for free position near \(target) in column \(col) using position map", level: .verbose, category: "Search")

        for offset in 0...10 {
            if offset == 0 && !isPositionOccupiedInMap(target) {
                logger.log("Target position \(target) is free", level: .success, category: "Search")
                return target
            }

            let above = GridPosition(col: col, row: target.row - offset)
            if offset > 0 && !isPositionOccupiedInMap(above) {
                logger.log("Found free position \(offset) row(s) above: \(above)", level: .success, category: "Search")
                return above
            }

            let below = GridPosition(col: col, row: target.row + offset)
            if offset > 0 && !isPositionOccupiedInMap(below) {
                logger.log("Found free position \(offset) row(s) below: \(below)", level: .success, category: "Search")
                return below
            }
        }

        let fallback = GridPosition(col: col, row: target.row + 11)
        logger.log("Using fallback position far below: \(fallback)", level: .warning, category: "Search")
        return fallback
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

        // Sort nodes by column position (rightmost first) to avoid internal conflicts
        let sortedNodesToShift = nodesToShift.sorted { nodeId1, nodeId2 in
            guard let node1 = nodes.first(where: { $0.id == nodeId1 }),
                  let node2 = nodes.first(where: { $0.id == nodeId2 }) else {
                return false
            }
            return node1.col > node2.col  // Rightmost nodes first
        }

        logger.log("Moving nodes in order (rightmost first): \(sortedNodesToShift.joined(separator: ", "))",
                  level: .info, category: "Shift")

        for nodeId in sortedNodesToShift {
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                let oldPos = nodes[index].gridPosition
                let newPos = GridPosition(col: oldPos.col + 1, row: oldPos.row)

                // CRITICAL: Update position map atomically
                if !moveNodeInPositionMap(nodeId: nodeId, from: oldPos, to: newPos) {
                    logger.log("CRITICAL: Failed to move '\(nodeId)' in position map from \(oldPos) to \(newPos)",
                              level: .error, category: "Shift")
                    assertionFailure("Position map update failed during branch shift")
                    continue
                }

                // Update the actual node position
                nodes[index].col += 1
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

                    // CRITICAL: Update position map when changing node positions
                    let oldPosition = nodes[index].gridPosition
                    let newPosition = GridPosition(col: layer, row: nodes[index].row)

                    if !moveNodeInPositionMap(nodeId: nodeId, from: oldPosition, to: newPosition) {
                        logger.log("CRITICAL: Failed to update position map for '\(nodeId)' during layer assignment",
                                  level: .error, category: "Layers")
                        logger.log("Skipping layer adjustment for '\(nodeId)' to maintain position map consistency",
                                  level: .warning, category: "Layers")
                        continue
                    }

                    // Update the actual node position only after position map update succeeds
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
        positionMap.removeAll() // Clear position tracking
        logger.log("Position map cleared", level: .verbose, category: "Position")
    }

    // MARK: - Position Management Methods

    private func reservePosition(for nodeId: String, at position: GridPosition) -> Bool {
        logger.log("Attempting to reserve position \(position) for node '\(nodeId)'",
                  level: .verbose, category: "Position")

        if let occupyingNodeId = positionMap[position] {
            logger.log("CONFLICT: Position \(position) already occupied by '\(occupyingNodeId)'",
                      level: .warning, category: "Position")
            return false
        }

        positionMap[position] = nodeId
        logger.log("Successfully reserved position \(position) for node '\(nodeId)'",
                  level: .verbose, category: "Position")
        dumpPositionMapIfVerbose()
        return true
    }

    private func releasePosition(at position: GridPosition) {
        if let nodeId = positionMap[position] {
            logger.log("Releasing position \(position) (was occupied by '\(nodeId)')",
                      level: .verbose, category: "Position")
            positionMap.removeValue(forKey: position)
        } else {
            logger.log("Warning: Attempted to release empty position \(position)",
                      level: .warning, category: "Position")
        }
        dumpPositionMapIfVerbose()
    }

    private func moveNodeInPositionMap(nodeId: String, from oldPosition: GridPosition, to newPosition: GridPosition) -> Bool {
        logger.log("Moving '\(nodeId)' in position map: \(oldPosition) → \(newPosition)",
                  level: .verbose, category: "Position")

        // Check if new position is available
        if let occupyingNodeId = positionMap[newPosition] {
            if occupyingNodeId != nodeId {
                logger.log("MOVE BLOCKED: Position \(newPosition) occupied by '\(occupyingNodeId)'",
                          level: .error, category: "Position")
                return false
            }
        }

        // Release old position
        if positionMap[oldPosition] == nodeId {
            positionMap.removeValue(forKey: oldPosition)
        }

        // Reserve new position
        positionMap[newPosition] = nodeId
        logger.log("Successfully moved '\(nodeId)' to \(newPosition)",
                  level: .verbose, category: "Position")
        dumpPositionMapIfVerbose()
        return true
    }

    private func isPositionOccupiedInMap(_ position: GridPosition) -> Bool {
        let occupied = positionMap[position] != nil
        logger.log("Position \(position): \(occupied ? "OCCUPIED" : "FREE")",
                  level: .verbose, category: "Position")
        return occupied
    }

    private func dumpPositionMapIfVerbose() {
        if logger.enableVerbose {
            dumpPositionMap()
        }
    }

    private func dumpPositionMap() {
        logger.log("=== POSITION MAP DUMP ===", level: .info, category: "Position")
        if positionMap.isEmpty {
            logger.log("Position map is empty", level: .info, category: "Position")
        } else {
            let sortedPositions = positionMap.keys.sorted {
                if $0.col != $1.col { return $0.col < $1.col }
                return $0.row < $1.row
            }
            for position in sortedPositions {
                logger.log("\(position): '\(positionMap[position]!)'",
                          level: .info, category: "Position")
            }
        }
        logger.log("=== END POSITION MAP ===", level: .info, category: "Position")
    }

    // MARK: - Validation Methods

    func validateNoOverlaps() -> Bool {
        // Check nodes array for overlaps
        let positions = nodes.map { $0.gridPosition }
        let uniquePositions = Set(positions)
        let hasNodeOverlaps = positions.count != uniquePositions.count

        if hasNodeOverlaps {
            logger.log("VALIDATION FAILED: Node position overlaps detected!", level: .error, category: "Validation")
            let duplicates = Dictionary(grouping: nodes, by: { $0.gridPosition })
                .filter { $1.count > 1 }
            for (position, nodes) in duplicates {
                logger.log("Overlap at \(position): \(nodes.map { $0.id }.joined(separator: ", "))",
                          level: .error, category: "Validation")
            }
        }

        // Validate position map consistency
        let mapConsistencyValid = validatePositionMapConsistency()

        let overallValid = !hasNodeOverlaps && mapConsistencyValid

        if overallValid {
            logger.log("Validation passed: No overlaps", level: .verbose, category: "Validation")
        }

        return overallValid
    }

    private func validatePositionMapConsistency() -> Bool {
        var isValid = true

        // Check that every node is in the position map
        for node in nodes {
            if let mappedNodeId = positionMap[node.gridPosition] {
                if mappedNodeId != node.id {
                    logger.log("POSITION MAP ERROR: Position \(node.gridPosition) maps to '\(mappedNodeId)' but node '\(node.id)' claims it",
                              level: .error, category: "Validation")
                    isValid = false
                }
            } else {
                logger.log("POSITION MAP ERROR: Node '\(node.id)' at \(node.gridPosition) not found in position map",
                          level: .error, category: "Validation")
                isValid = false
            }
        }

        // Check that every position map entry corresponds to an actual node
        for (position, nodeId) in positionMap {
            if let node = nodes.first(where: { $0.id == nodeId }) {
                if node.gridPosition != position {
                    logger.log("POSITION MAP ERROR: Position map shows '\(nodeId)' at \(position) but node is actually at \(node.gridPosition)",
                              level: .error, category: "Validation")
                    isValid = false
                }
            } else {
                logger.log("POSITION MAP ERROR: Position map shows '\(nodeId)' at \(position) but no such node exists",
                          level: .error, category: "Validation")
                isValid = false
            }
        }

        if isValid {
            logger.log("Position map consistency validated", level: .verbose, category: "Validation")
        } else {
            logger.log("POSITION MAP VALIDATION FAILED", level: .error, category: "Validation")
            dumpPositionMap()
        }

        return isValid
    }

    private func repairPositionMap() {
        logger.log("Attempting to repair position map", level: .warning, category: "Validation")
        positionMap.removeAll()

        for node in nodes {
            if positionMap[node.gridPosition] != nil {
                logger.log("REPAIR ERROR: Multiple nodes at \(node.gridPosition) - cannot auto-repair",
                          level: .error, category: "Validation")
                continue
            }
            positionMap[node.gridPosition] = node.id
        }

        logger.log("Position map repair attempted", level: .warning, category: "Validation")
        dumpPositionMap()
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