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

    // Spatial constraint tracking - ensures downstream nodes stay east of upstream nodes
    private var spatialConstraints: [String: SpatialConstraint] = [:]

    // Feature flag for new intent-based placement system
    private let useIntentBasedPlacement = true

    private struct SpatialConstraint {
        let minLayer: Int?      // Minimum layer this node can be assigned to
        let maxLayer: Int?      // Maximum layer this node can be assigned to
        let preferredLayer: Int? // Ideal layer for proximity (prefer this when valid)
        let reason: String      // Why this constraint exists (for logging)

        init(minLayer: Int? = nil, maxLayer: Int? = nil, preferredLayer: Int? = nil, reason: String) {
            self.minLayer = minLayer
            self.maxLayer = maxLayer
            self.preferredLayer = preferredLayer
            self.reason = reason
        }
    }

    // MARK: - New Intent-Based Placement System

    enum PlacementType {
        case adjacentDownstream
        case adjacentUpstream
        case disconnected
    }

    enum PlacementPriority {
        case userIntent     // High - preserve user's spatial expectations
        case topological    // Medium - satisfy dependency requirements
        case optimization   // Low - nice-to-have layout improvements
    }

    struct PlacementIntent {
        let type: PlacementType
        let anchor: String?         // Reference node that should stay stable
        let newNode: String         // Node being placed
        let priority: PlacementPriority
        let reason: String          // For logging and debugging

        static func downstreamOf(_ anchor: String, placing newNode: String) -> PlacementIntent {
            PlacementIntent(
                type: .adjacentDownstream,
                anchor: anchor,
                newNode: newNode,
                priority: .userIntent,
                reason: "User requested '\(newNode)' downstream of '\(anchor)'"
            )
        }

        static func upstreamOf(_ anchor: String, placing newNode: String) -> PlacementIntent {
            PlacementIntent(
                type: .adjacentUpstream,
                anchor: anchor,
                newNode: newNode,
                priority: .userIntent,
                reason: "User requested '\(newNode)' upstream of '\(anchor)'"
            )
        }

        static func disconnected(_ newNode: String) -> PlacementIntent {
            PlacementIntent(
                type: .disconnected,
                anchor: nil,
                newNode: newNode,
                priority: .userIntent,
                reason: "User requested disconnected node '\(newNode)'"
            )
        }
    }

    struct TopologicalConstraint {
        let before: String      // Node that must come before
        let after: String       // Node that must come after
        let reason: String      // Why this constraint exists
    }

    struct ProximityConstraint {
        let node: String        // Node being constrained
        let preferredPosition: GridPosition  // Ideal position
        let tolerance: Int      // How far away is acceptable
        let reason: String      // Why this constraint exists
    }

    struct NodeLock {
        let nodeId: String      // Node that shouldn't move
        let reason: String      // Why it's locked
    }

    struct PlacementConstraints {
        let hard: [TopologicalConstraint]    // Must be satisfied
        let soft: [ProximityConstraint]      // Should be satisfied when possible
        let locks: [NodeLock]                // Nodes that shouldn't move
    }

    private var occupiedPositions: Set<GridPosition> {
        Set(nodes.map { $0.gridPosition })
    }

    // MARK: - Constraint Generation

    private func generateConstraints(for intent: PlacementIntent) -> PlacementConstraints {
        logger.log("Generating constraints for intent: \(intent.reason)", level: .info, category: "Intent")

        var hardConstraints: [TopologicalConstraint] = []
        var softConstraints: [ProximityConstraint] = []
        var locks: [NodeLock] = []

        // Lock the anchor node to prevent unexpected movement
        if let anchor = intent.anchor {
            locks.append(NodeLock(
                nodeId: anchor,
                reason: "Anchor node for \(intent.type) placement"
            ))
        }

        switch intent.type {
        case .adjacentDownstream:
            guard let anchor = intent.anchor,
                  let anchorNode = findNode(byId: anchor) else {
                logger.log("ERROR: Cannot find anchor node for downstream placement", level: .error, category: "Intent")
                break
            }

            // Hard constraint: new node must be east of anchor
            hardConstraints.append(TopologicalConstraint(
                before: anchor,
                after: intent.newNode,
                reason: "Downstream topology requirement"
            ))

            // Soft constraint: prefer immediate adjacency
            let preferredPos = GridPosition(col: anchorNode.col + 1, row: anchorNode.row)
            softConstraints.append(ProximityConstraint(
                node: intent.newNode,
                preferredPosition: preferredPos,
                tolerance: 1,
                reason: "User expects adjacent downstream placement"
            ))

        case .adjacentUpstream:
            guard let anchor = intent.anchor,
                  let anchorNode = findNode(byId: anchor) else {
                logger.log("ERROR: Cannot find anchor node for upstream placement", level: .error, category: "Intent")
                break
            }

            // Hard constraint: new node must be west of anchor
            hardConstraints.append(TopologicalConstraint(
                before: intent.newNode,
                after: anchor,
                reason: "Upstream topology requirement"
            ))

            // Soft constraint: prefer immediate adjacency
            let preferredPos = GridPosition(col: anchorNode.col - 1, row: anchorNode.row)
            softConstraints.append(ProximityConstraint(
                node: intent.newNode,
                preferredPosition: preferredPos,
                tolerance: 1,
                reason: "User expects adjacent upstream placement"
            ))

        case .disconnected:
            // No hard topological constraints for disconnected nodes
            // Just find a good empty position
            break
        }

        logger.log("Generated \(hardConstraints.count) hard, \(softConstraints.count) soft constraints, \(locks.count) locks",
                  level: .info, category: "Intent")

        return PlacementConstraints(
            hard: hardConstraints,
            soft: softConstraints,
            locks: locks
        )
    }

    // MARK: - Multi-Strategy Placement Solver

    enum PlacementStrategy {
        case exactPosition          // Try the exact preferred position
        case adjacentAlternatives   // Try nearby positions in same row
        case rowAlternatives        // Try same column, different rows
        case minimalDisplacement    // Move one conflicting node slightly
        case strategicAnchorShift   // Shift anchor node and branch when beneficial
        case fallbackSearch         // Search in expanding radius
    }

    struct PlacementResult {
        let position: GridPosition
        let strategy: PlacementStrategy
        let displacements: [NodeDisplacement]  // Other nodes that need to move
        let success: Bool
        let reason: String

        struct NodeDisplacement {
            let nodeId: String
            let from: GridPosition
            let to: GridPosition
            let reason: String
        }
    }

    private func solvePlacement(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        logger.log("Solving placement with multiple strategies", level: .info, category: "Solver")

        // Try strategies in order of preference
        let strategies: [PlacementStrategy] = [
            .exactPosition,
            .adjacentAlternatives,
            .rowAlternatives,
            .minimalDisplacement,
            .strategicAnchorShift,
            .fallbackSearch
        ]

        for strategy in strategies {
            logger.log("Trying placement strategy: \(strategy)", level: .verbose, category: "Solver")

            let result = tryPlacementStrategy(strategy, for: intent, with: constraints)
            if result.success {
                logger.log("SUCCESS: Strategy \(strategy) found solution at \(result.position)",
                          level: .success, category: "Solver")
                return result
            } else {
                logger.log("FAILED: Strategy \(strategy) - \(result.reason)",
                          level: .verbose, category: "Solver")
            }
        }

        // If all strategies fail, return a fallback distant position
        logger.log("All strategies failed, using distant fallback position", level: .warning, category: "Solver")
        return PlacementResult(
            position: findDistantFallbackPosition(),
            strategy: .fallbackSearch,
            displacements: [],
            success: true,
            reason: "All proximity strategies failed, using distant position"
        )
    }

    private func tryPlacementStrategy(_ strategy: PlacementStrategy, for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        switch strategy {
        case .exactPosition:
            return tryExactPosition(for: intent, with: constraints)
        case .adjacentAlternatives:
            return tryAdjacentAlternatives(for: intent, with: constraints)
        case .rowAlternatives:
            return tryRowAlternatives(for: intent, with: constraints)
        case .minimalDisplacement:
            return tryMinimalDisplacement(for: intent, with: constraints)
        case .strategicAnchorShift:
            return tryStrategicAnchorShift(for: intent, with: constraints)
        case .fallbackSearch:
            return tryFallbackSearch(for: intent, with: constraints)
        }
    }

    private func tryExactPosition(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        guard let preferredConstraint = constraints.soft.first(where: { $0.node == intent.newNode }) else {
            return PlacementResult(position: GridPosition(col: 0, row: 0), strategy: .exactPosition, displacements: [], success: false, reason: "No preferred position constraint")
        }

        let preferredPos = preferredConstraint.preferredPosition

        if !isPositionOccupiedInMap(preferredPos) {
            return PlacementResult(
                position: preferredPos,
                strategy: .exactPosition,
                displacements: [],
                success: true,
                reason: "Preferred position is free"
            )
        } else {
            return PlacementResult(
                position: preferredPos,
                strategy: .exactPosition,
                displacements: [],
                success: false,
                reason: "Preferred position \(preferredPos) is occupied"
            )
        }
    }

    private func tryAdjacentAlternatives(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        guard let preferredConstraint = constraints.soft.first(where: { $0.node == intent.newNode }) else {
            return PlacementResult(position: GridPosition(col: 0, row: 0), strategy: .adjacentAlternatives, displacements: [], success: false, reason: "No preferred position constraint")
        }

        let preferredPos = preferredConstraint.preferredPosition

        // Try positions in the same row, nearby columns
        for colOffset in 1...3 {
            for direction in [-1, 1] {  // Try both directions
                let testPos = GridPosition(col: preferredPos.col + (colOffset * direction), row: preferredPos.row)

                if !isPositionOccupiedInMap(testPos) && satisfiesHardConstraints(testPos, for: intent, with: constraints) {
                    return PlacementResult(
                        position: testPos,
                        strategy: .adjacentAlternatives,
                        displacements: [],
                        success: true,
                        reason: "Found adjacent alternative at \(testPos)"
                    )
                }
            }
        }

        return PlacementResult(
            position: preferredPos,
            strategy: .adjacentAlternatives,
            displacements: [],
            success: false,
            reason: "No adjacent alternatives found"
        )
    }

    private func tryRowAlternatives(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        guard let preferredConstraint = constraints.soft.first(where: { $0.node == intent.newNode }) else {
            return PlacementResult(position: GridPosition(col: 0, row: 0), strategy: .rowAlternatives, displacements: [], success: false, reason: "No preferred position constraint")
        }

        let preferredPos = preferredConstraint.preferredPosition

        // Try different rows in the same column
        for rowOffset in 1...3 {
            for direction in [-1, 1] {  // Try above and below
                let testPos = GridPosition(col: preferredPos.col, row: preferredPos.row + (rowOffset * direction))

                if !isPositionOccupiedInMap(testPos) && satisfiesHardConstraints(testPos, for: intent, with: constraints) {
                    return PlacementResult(
                        position: testPos,
                        strategy: .rowAlternatives,
                        displacements: [],
                        success: true,
                        reason: "Found row alternative at \(testPos)"
                    )
                }
            }
        }

        return PlacementResult(
            position: preferredPos,
            strategy: .rowAlternatives,
            displacements: [],
            success: false,
            reason: "No row alternatives found"
        )
    }

    private func tryMinimalDisplacement(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        // For now, skip minimal displacement - it's complex and we can implement later
        return PlacementResult(
            position: GridPosition(col: 0, row: 0),
            strategy: .minimalDisplacement,
            displacements: [],
            success: false,
            reason: "Minimal displacement not yet implemented"
        )
    }

    private func tryStrategicAnchorShift(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        logger.log("Attempting strategic anchor shift", level: .info, category: "Strategy")

        // Only apply to upstream placements where we want to shift the target branch
        guard intent.type == .adjacentUpstream,
              let anchor = intent.anchor,
              let anchorNode = findNode(byId: anchor) else {
            return PlacementResult(
                position: GridPosition(col: 0, row: 0),
                strategy: .strategicAnchorShift,
                displacements: [],
                success: false,
                reason: "Strategic anchor shift only applies to upstream placement"
            )
        }

        // Calculate how much we need to shift the anchor branch
        guard let preferredConstraint = constraints.soft.first(where: { $0.node == intent.newNode }) else {
            return PlacementResult(
                position: GridPosition(col: 0, row: 0),
                strategy: .strategicAnchorShift,
                displacements: [],
                success: false,
                reason: "No preferred position constraint for strategic shift"
            )
        }

        let preferredPos = preferredConstraint.preferredPosition

        // Check if the preferred position is occupied
        guard isPositionOccupiedInMap(preferredPos) else {
            return PlacementResult(
                position: GridPosition(col: 0, row: 0),
                strategy: .strategicAnchorShift,
                displacements: [],
                success: false,
                reason: "Preferred position is not occupied, no shift needed"
            )
        }

        // Try shifting the anchor branch 1-2 positions to the right
        for shiftAmount in 1...2 {
            logger.log("Trying anchor shift of \(shiftAmount) positions", level: .verbose, category: "Strategy")

            let shiftResult = evaluateAnchorShift(
                anchor: anchor,
                shiftAmount: shiftAmount,
                newNodePosition: preferredPos,
                intent: intent
            )

            if shiftResult.success {
                logger.log("Strategic anchor shift successful: shift by \(shiftAmount)", level: .success, category: "Strategy")
                return PlacementResult(
                    position: preferredPos,
                    strategy: .strategicAnchorShift,
                    displacements: shiftResult.displacements,
                    success: true,
                    reason: "Shifted anchor branch by \(shiftAmount) to create space"
                )
            }
        }

        return PlacementResult(
            position: GridPosition(col: 0, row: 0),
            strategy: .strategicAnchorShift,
            displacements: [],
            success: false,
            reason: "No beneficial anchor shift found"
        )
    }

    private func evaluateAnchorShift(
        anchor: String,
        shiftAmount: Int,
        newNodePosition: GridPosition,
        intent: PlacementIntent
    ) -> (success: Bool, displacements: [PlacementResult.NodeDisplacement]) {
        logger.log("Evaluating anchor shift: '\(anchor)' by \(shiftAmount) positions", level: .verbose, category: "Strategy")

        // Find all nodes in the anchor's downstream branch
        let branchNodes = findDownstreamBranch(from: anchor)
        var displacements: [PlacementResult.NodeDisplacement] = []

        // Check if we can shift all branch nodes
        for nodeId in branchNodes {
            guard let node = findNode(byId: nodeId) else { continue }

            let newPosition = GridPosition(col: node.col + shiftAmount, row: node.row)

            // Check if the new position would be occupied (excluding nodes we're planning to move)
            if isPositionOccupiedInMap(newPosition) {
                // Check if it's occupied by another node in our branch (which is OK)
                if let occupyingNodeId = positionMap[newPosition],
                   !branchNodes.contains(occupyingNodeId) {
                    logger.log("Shift blocked: \(newPosition) occupied by '\(occupyingNodeId)' (not in branch)",
                              level: .verbose, category: "Strategy")
                    return (false, [])
                }
            }

            displacements.append(PlacementResult.NodeDisplacement(
                nodeId: nodeId,
                from: node.gridPosition,
                to: newPosition,
                reason: "Strategic shift to make space for '\(intent.newNode)'"
            ))
        }

        // Check if the shift creates a valid solution
        let wouldCreateValidPlacement = !isPositionOccupiedAfterDisplacements(
            newNodePosition,
            displacements: displacements
        )

        if wouldCreateValidPlacement {
            logger.log("Anchor shift evaluation: SUCCESS - creates valid placement", level: .success, category: "Strategy")
            return (true, displacements)
        } else {
            logger.log("Anchor shift evaluation: FAILED - would not create valid placement", level: .verbose, category: "Strategy")
            return (false, [])
        }
    }

    private func findDownstreamBranch(from nodeId: String) -> [String] {
        var visited: Set<String> = []
        var toVisit: Set<String> = [nodeId]
        var branch: [String] = []

        while !toVisit.isEmpty {
            let current = toVisit.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            branch.append(current)

            // Add all downstream nodes
            if let children = adjacencyList[current] {
                toVisit.formUnion(children)
            }
        }

        logger.log("Found downstream branch from '\(nodeId)': \(branch.joined(separator: ", "))",
                  level: .verbose, category: "Strategy")
        return branch
    }

    private func isPositionOccupiedAfterDisplacements(
        _ position: GridPosition,
        displacements: [PlacementResult.NodeDisplacement]
    ) -> Bool {
        // Create a temporary map of positions after displacements
        var tempPositionMap = positionMap

        // Remove nodes from their old positions
        for displacement in displacements {
            tempPositionMap.removeValue(forKey: displacement.from)
        }

        // Add nodes to their new positions
        for displacement in displacements {
            tempPositionMap[displacement.to] = displacement.nodeId
        }

        // Check if the target position would be occupied
        return tempPositionMap[position] != nil
    }

    private func tryFallbackSearch(for intent: PlacementIntent, with constraints: PlacementConstraints) -> PlacementResult {
        guard let preferredConstraint = constraints.soft.first(where: { $0.node == intent.newNode }) else {
            return PlacementResult(position: findDistantFallbackPosition(), strategy: .fallbackSearch, displacements: [], success: true, reason: "Using distant fallback")
        }

        let preferredPos = preferredConstraint.preferredPosition

        // Search in expanding radius from preferred position
        for radius in 1...10 {
            for colOffset in -radius...radius {
                for rowOffset in -radius...radius {
                    let testPos = GridPosition(col: preferredPos.col + colOffset, row: preferredPos.row + rowOffset)

                    if !isPositionOccupiedInMap(testPos) && satisfiesHardConstraints(testPos, for: intent, with: constraints) {
                        return PlacementResult(
                            position: testPos,
                            strategy: .fallbackSearch,
                            displacements: [],
                            success: true,
                            reason: "Found position in radius \(radius) search"
                        )
                    }
                }
            }
        }

        return PlacementResult(
            position: findDistantFallbackPosition(),
            strategy: .fallbackSearch,
            displacements: [],
            success: true,
            reason: "Used distant fallback after radius search failed"
        )
    }

    private func satisfiesHardConstraints(_ position: GridPosition, for intent: PlacementIntent, with constraints: PlacementConstraints) -> Bool {
        // Check topological constraints
        for constraint in constraints.hard {
            if constraint.after == intent.newNode {
                // This node must come after the 'before' node
                guard let beforeNode = findNode(byId: constraint.before) else { continue }
                if position.col <= beforeNode.col {
                    return false  // Would violate topological order
                }
            }
            if constraint.before == intent.newNode {
                // This node must come before the 'after' node
                guard let afterNode = findNode(byId: constraint.after) else { continue }
                if position.col >= afterNode.col {
                    return false  // Would violate topological order
                }
            }
        }
        return true
    }

    private func findDistantFallbackPosition() -> GridPosition {
        // Find a position far from existing nodes as last resort
        let maxCol = nodes.map { $0.col }.max() ?? -1
        let maxRow = nodes.map { $0.row }.max() ?? -1
        return GridPosition(col: maxCol + 2, row: maxRow + 1)
    }

    // MARK: - New Intent-Based Placement Methods

    private func placeNodeWithIntent(_ intent: PlacementIntent) -> Bool {
        logger.log("=== INTENT-BASED PLACEMENT START ===", level: .info, category: "Intent")
        logger.log("Intent: \(intent.reason)", level: .info, category: "Intent")

        // Generate constraints based on user intent
        let constraints = generateConstraints(for: intent)

        // Solve for optimal placement
        let solution = solvePlacement(for: intent, with: constraints)

        // Apply the solution
        let newNode = Node(id: intent.newNode, col: solution.position.col, row: solution.position.row)

        // Reserve position in map
        if !reservePosition(for: newNode.id, at: newNode.gridPosition) {
            logger.log("CRITICAL ERROR: Failed to reserve position \(newNode.gridPosition) for intent-based placement",
                      level: .error, category: "Intent")
            return false
        }

        // Add node to graph
        nodes.append(newNode)
        adjacencyList[newNode.id] = Set()
        reverseAdjacencyList[newNode.id] = Set()

        // Add edge if this is a relational placement
        if let anchor = intent.anchor {
            switch intent.type {
            case .adjacentDownstream:
                addEdge(from: anchor, to: intent.newNode)
            case .adjacentUpstream:
                addEdge(from: intent.newNode, to: anchor)
            case .disconnected:
                break  // No edge for disconnected nodes
            }
        }

        // Apply any displacements if needed (for minimal displacement strategy)
        for displacement in solution.displacements {
            logger.log("Applying displacement: \(displacement.nodeId) \(displacement.from) → \(displacement.to)",
                      level: .info, category: "Intent")
            // Move the displaced node
            if let index = nodes.firstIndex(where: { $0.id == displacement.nodeId }) {
                if !moveNodeInPositionMap(nodeId: displacement.nodeId, from: displacement.from, to: displacement.to) {
                    logger.log("Failed to move displaced node \(displacement.nodeId)", level: .error, category: "Intent")
                }
                nodes[index].col = displacement.to.col
                nodes[index].row = displacement.to.row
            }
        }

        logger.log("SUCCESS: Placed '\(intent.newNode)' at \(solution.position) using \(solution.strategy)",
                  level: .success, category: "Intent")
        logger.log("=== INTENT-BASED PLACEMENT COMPLETE ===", level: .info, category: "Intent")

        return true
    }

    // New public methods that use intent-based placement
    func addNodeDownstreamWithIntent(newId: String, of sourceId: String) {
        let intent = PlacementIntent.downstreamOf(sourceId, placing: newId)
        let success = placeNodeWithIntent(intent)

        if success {
            // Validate result
            _ = validateNoOverlaps()
            _ = validateTopologicalOrder()
        }
    }

    func addNodeUpstreamWithIntent(newId: String, of targetId: String) {
        let intent = PlacementIntent.upstreamOf(targetId, placing: newId)
        let success = placeNodeWithIntent(intent)

        if success {
            // Validate result
            _ = validateNoOverlaps()
            _ = validateTopologicalOrder()
        }
    }

    init() {
        logger.log("GraphLayoutManager initialized", level: .info, category: "System")
        if useIntentBasedPlacement {
            logger.log("Using new intent-based placement system", level: .info, category: "System")
        } else {
            logger.log("Using legacy placement system", level: .info, category: "System")
        }
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
        // Feature flag: use new intent-based system or legacy system
        if useIntentBasedPlacement {
            addNodeUpstreamWithIntent(newId: newId, of: targetId)
            return
        }

        // Legacy implementation below
        logger.log("=== UPSTREAM INSERTION START (LEGACY) ===", level: .info, category: "Operation")
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

        // Record spatial constraint AFTER topological ordering when positions are stable
        guard let targetNode = findNode(byId: targetId) else {
            logger.log("ERROR: Target node '\(targetId)' not found for constraint recording", level: .error, category: "Constraint")
            return
        }

        let maxLayer = targetNode.col - 1
        let preferredLayer = targetNode.col - 1  // Prefer immediate adjacency for proximity
        spatialConstraints[newId] = SpatialConstraint(
            maxLayer: maxLayer,
            preferredLayer: preferredLayer,
            reason: "upstream of '\(targetId)' at final layer \(targetNode.col)"
        )
        logger.log("Recorded spatial constraint: '\(newId)' must be at layer <= \(maxLayer) (upstream of '\(targetId)' at final position)",
                  level: .info, category: "Constraint")

        // Re-run topological ordering to apply the new constraint
        updateTopologicalOrder()

        // Validate the result
        _ = validateNoOverlaps()
        _ = validateTopologicalOrder()

        logger.log("=== UPSTREAM INSERTION COMPLETE ===", level: .info, category: "Operation")
    }

    func addNodeDownstream(newId: String, of sourceId: String) {
        // Feature flag: use new intent-based system or legacy system
        if useIntentBasedPlacement {
            addNodeDownstreamWithIntent(newId: newId, of: sourceId)
            return
        }

        // Legacy implementation below
        logger.log("=== DOWNSTREAM INSERTION START (LEGACY) ===", level: .info, category: "Operation")
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

        // Record spatial constraint AFTER topological ordering when positions are stable
        guard let sourceNode = findNode(byId: sourceId) else {
            logger.log("ERROR: Source node '\(sourceId)' not found for constraint recording", level: .error, category: "Constraint")
            return
        }

        let minLayer = sourceNode.col + 1
        let preferredLayer = sourceNode.col + 1  // Prefer immediate adjacency for proximity
        spatialConstraints[newId] = SpatialConstraint(
            minLayer: minLayer,
            preferredLayer: preferredLayer,
            reason: "downstream of '\(sourceId)' at final layer \(sourceNode.col)"
        )
        logger.log("Recorded spatial constraint: '\(newId)' must be at layer >= \(minLayer) (downstream of '\(sourceId)' at final position)",
                  level: .info, category: "Constraint")

        // Re-run topological ordering to apply the new constraint
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
            let topologicalLayer: Int
            if predecessors.isEmpty {
                topologicalLayer = 0
            } else {
                let maxPredLayer = predecessors.compactMap { layerMap[$0] }.max() ?? -1
                topologicalLayer = maxPredLayer + 1
            }

            // Apply spatial constraints with proximity preference
            var finalLayer = topologicalLayer
            if let constraint = spatialConstraints[nodeId] {
                logger.log("Applying spatial constraint to '\(nodeId)': \(constraint.reason)",
                          level: .info, category: "Constraint")

                // First, try to use preferred layer if it's valid
                if let preferredLayer = constraint.preferredLayer {
                    var canUsePreferred = true

                    // Check if preferred layer violates minimum constraint
                    if let minLayer = constraint.minLayer, preferredLayer < minLayer {
                        canUsePreferred = false
                    }

                    // Check if preferred layer violates maximum constraint
                    if let maxLayer = constraint.maxLayer, preferredLayer > maxLayer {
                        canUsePreferred = false
                    }

                    // Check if preferred layer satisfies topological dependencies
                    if preferredLayer < topologicalLayer {
                        logger.log("Preferred layer \(preferredLayer) would violate topological order (needs >= \(topologicalLayer))",
                                  level: .warning, category: "Constraint")
                        canUsePreferred = false
                    }

                    if canUsePreferred {
                        logger.log("Using preferred layer \(preferredLayer) for proximity to adjacent node",
                                  level: .success, category: "Proximity")
                        finalLayer = preferredLayer
                    } else {
                        logger.log("Cannot use preferred layer \(preferredLayer), falling back to constraint enforcement",
                                  level: .warning, category: "Proximity")
                    }
                }

                // If preferred layer couldn't be used, enforce hard constraints
                if finalLayer == topologicalLayer {
                    // Enforce minimum layer (for downstream nodes)
                    if let minLayer = constraint.minLayer {
                        if finalLayer < minLayer {
                            logger.log("Enforcing min layer: '\(nodeId)' moved from \(finalLayer) to \(minLayer)",
                                      level: .info, category: "Constraint")
                            finalLayer = minLayer
                        }
                    }

                    // Enforce maximum layer (for upstream nodes)
                    if let maxLayer = constraint.maxLayer {
                        if finalLayer > maxLayer {
                            logger.log("Enforcing max layer: '\(nodeId)' moved from \(finalLayer) to \(maxLayer)",
                                      level: .info, category: "Constraint")
                            finalLayer = maxLayer
                        }
                    }
                }
            }

            layerMap[nodeId] = finalLayer
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
        spatialConstraints.removeAll() // Clear spatial constraints
        logger.log("Position map and spatial constraints cleared", level: .verbose, category: "Position")
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