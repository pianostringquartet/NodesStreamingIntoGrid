//
//  NodesStreamingIntoGridTests.swift
//  NodesStreamingIntoGridTests
//
//  Tests for graph node placement algorithms
//

import XCTest
@testable import NodesStreamingIntoGrid

final class NodesStreamingIntoGridTests: XCTestCase {

    var layoutManager: GraphLayoutManager!

    override func setUpWithError() throws {
        super.setUp()
        layoutManager = GraphLayoutManager()
    }

    override func tearDownWithError() throws {
        layoutManager = nil
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testBasicNodeAddition() throws {
        // Test adding a single node
        let node = Node(id: "A", col: 1, row: 1)
        layoutManager.addNode(node)

        XCTAssertEqual(layoutManager.nodes.count, 1)
        XCTAssertEqual(layoutManager.nodes.first?.id, "A")
        XCTAssertTrue(layoutManager.validateNoOverlaps())
    }

    // MARK: - Upstream Insertion Tests

    func testBasicUpstreamInsertion() throws {
        // Start with node A at (1,1)
        let nodeA = Node(id: "A", col: 1, row: 1)
        layoutManager.addNode(nodeA)

        // Add N1 upstream of A - should place at (0,1)
        layoutManager.addNodeUpstream(newId: "N1", of: "A")

        XCTAssertEqual(layoutManager.nodes.count, 2)

        let n1 = layoutManager.findNode(byId: "N1")
        let aNode = layoutManager.findNode(byId: "A")

        XCTAssertNotNil(n1)
        XCTAssertNotNil(aNode)

        // N1 should be to the left of A
        XCTAssertLessThan(n1!.col, aNode!.col)

        // Should have an edge from N1 to A
        XCTAssertTrue(layoutManager.edges.contains { $0.from == "N1" && $0.to == "A" })

        // Validate no overlaps and proper topology
        XCTAssertTrue(layoutManager.validateNoOverlaps())
        XCTAssertTrue(layoutManager.validateTopologicalOrder())
    }

    func testMultipleUpstreamInsertions() throws {
        // This tests the specific bug case: A, then N2 upstream, then N3 upstream
        let nodeA = Node(id: "A", col: 1, row: 1)
        layoutManager.addNode(nodeA)

        // Add N2 upstream of A
        layoutManager.addNodeUpstream(newId: "N2", of: "A")

        XCTAssertTrue(layoutManager.validateNoOverlaps(), "After N2 insertion")
        XCTAssertTrue(layoutManager.validateTopologicalOrder(), "After N2 insertion")

        // Add N3 upstream of A - this was the failing case
        layoutManager.addNodeUpstream(newId: "N3", of: "A")

        XCTAssertEqual(layoutManager.nodes.count, 3)
        XCTAssertTrue(layoutManager.validateNoOverlaps(), "After N3 insertion - this was the bug!")
        XCTAssertTrue(layoutManager.validateTopologicalOrder(), "After N3 insertion")

        // Verify the topology is correct: N3 -> A, N2 -> A (or some valid order)
        let n2 = layoutManager.findNode(byId: "N2")!
        let n3 = layoutManager.findNode(byId: "N3")!
        let aNode = layoutManager.findNode(byId: "A")!

        XCTAssertLessThan(n2.col, aNode.col, "N2 should be upstream of A")
        XCTAssertLessThan(n3.col, aNode.col, "N3 should be upstream of A")
    }

    // MARK: - Downstream Insertion Tests

    func testBasicDownstreamInsertion() throws {
        let nodeA = Node(id: "A", col: 1, row: 1)
        layoutManager.addNode(nodeA)

        layoutManager.addNodeDownstream(newId: "B", of: "A")

        XCTAssertEqual(layoutManager.nodes.count, 2)

        let aNode = layoutManager.findNode(byId: "A")!
        let bNode = layoutManager.findNode(byId: "B")!

        XCTAssertLessThan(aNode.col, bNode.col, "B should be downstream of A")
        XCTAssertTrue(layoutManager.edges.contains { $0.from == "A" && $0.to == "B" })

        XCTAssertTrue(layoutManager.validateNoOverlaps())
        XCTAssertTrue(layoutManager.validateTopologicalOrder())
    }

    func testDownstreamProximityPreservation() throws {
        // This tests the specific case: C at (1,2) → N1 should be placed at (2,2) for maximum proximity
        // Previously, N1 was being placed at (3,2) due to topological optimization, creating unnecessary distance

        let nodeC = Node(id: "C", col: 1, row: 2)
        layoutManager.addNode(nodeC)

        // Add N1 downstream of C
        layoutManager.addNodeDownstream(newId: "N1", of: "C")

        XCTAssertEqual(layoutManager.nodes.count, 2)

        let cNode = layoutManager.findNode(byId: "C")!
        let n1Node = layoutManager.findNode(byId: "N1")!

        // Critical test: N1 should be immediately adjacent to C for best proximity
        XCTAssertEqual(n1Node.col, cNode.col + 1, "N1 should be in the column immediately east of C")
        XCTAssertEqual(n1Node.row, cNode.row, "N1 should be in the same row as C")
        XCTAssertEqual(n1Node.gridPosition, GridPosition(col: 2, row: 2), "N1 should be at exactly (2,2)")

        // Verify the spatial relationship is correct
        XCTAssertLessThan(cNode.col, n1Node.col, "C should be west of N1 (upstream/downstream relationship)")

        // Verify edge exists
        XCTAssertTrue(layoutManager.edges.contains { $0.from == "C" && $0.to == "N1" }, "Edge C → N1 should exist")

        // Verify system integrity
        XCTAssertTrue(layoutManager.validateNoOverlaps(), "No position overlaps should exist")
        XCTAssertTrue(layoutManager.validateTopologicalOrder(), "Topological order should be maintained")

        print("Proximity test result - C: \(cNode.gridPosition), N1: \(n1Node.gridPosition)")
    }

    func testDownstreamProximityWithExistingNodes() throws {
        // Test proximity preservation when other nodes exist in the graph
        // This ensures the proximity system works in complex scenarios

        // Set up initial graph: A → B, A → C
        let nodeA = Node(id: "A", col: 0, row: 1)
        let nodeB = Node(id: "B", col: 1, row: 1)
        let nodeC = Node(id: "C", col: 1, row: 2)

        layoutManager.addNode(nodeA)
        layoutManager.addNode(nodeB)
        layoutManager.addNode(nodeC)
        layoutManager.addEdge(from: "A", to: "B")
        layoutManager.addEdge(from: "A", to: "C")

        // Now add N1 downstream of C - should still prefer proximity
        layoutManager.addNodeDownstream(newId: "N1", of: "C")

        let cNode = layoutManager.findNode(byId: "C")!
        let n1Node = layoutManager.findNode(byId: "N1")!

        // N1 should still be placed adjacent to C despite other nodes existing
        XCTAssertEqual(n1Node.col, cNode.col + 1, "N1 should be immediately adjacent to C even with other nodes present")
        XCTAssertEqual(n1Node.row, cNode.row, "N1 should be in the same row as C")

        // Verify system integrity with more complex graph
        XCTAssertTrue(layoutManager.validateNoOverlaps(), "No overlaps in complex graph")
        XCTAssertTrue(layoutManager.validateTopologicalOrder(), "Topological order maintained in complex graph")

        // Verify all expected edges exist
        XCTAssertTrue(layoutManager.edges.contains { $0.from == "A" && $0.to == "B" })
        XCTAssertTrue(layoutManager.edges.contains { $0.from == "A" && $0.to == "C" })
        XCTAssertTrue(layoutManager.edges.contains { $0.from == "C" && $0.to == "N1" })

        print("Complex proximity test - C: \(cNode.gridPosition), N1: \(n1Node.gridPosition)")
    }

    // MARK: - Regression Tests

    func testSpecificBugCase_MultipleUpstreamToSameTarget() throws {
        // This is the exact scenario from the bug report

        // Start with Node A
        let nodeA = Node(id: "A", col: 1, row: 1)
        layoutManager.addNode(nodeA)

        // Insert N2 upstream of A
        layoutManager.addNodeUpstream(newId: "N2", of: "A")

        // Verify state after first insertion
        XCTAssertTrue(layoutManager.validateNoOverlaps(), "After first upstream insertion")
        XCTAssertTrue(layoutManager.validateTopologicalOrder(), "After first upstream insertion")

        // Insert N3 upstream of A - this should NOT cause overlap with N2
        layoutManager.addNodeUpstream(newId: "N3", of: "A")

        // This is the critical test - no overlaps should exist
        XCTAssertTrue(layoutManager.validateNoOverlaps(), "After second upstream insertion - the bug!")
        XCTAssertTrue(layoutManager.validateTopologicalOrder(), "After second upstream insertion")

        // Verify all nodes are in expected positions
        let n2 = layoutManager.findNode(byId: "N2")!
        let n3 = layoutManager.findNode(byId: "N3")!
        let aNode = layoutManager.findNode(byId: "A")!

        // Both N2 and N3 should be upstream of A
        XCTAssertLessThan(n2.col, aNode.col, "N2 upstream of A")
        XCTAssertLessThan(n3.col, aNode.col, "N3 upstream of A")

        // N2 and N3 should not occupy the same position
        XCTAssertNotEqual(n2.gridPosition, n3.gridPosition, "N2 and N3 should have different positions")

        print("Final positions - N2: \(n2.gridPosition), N3: \(n3.gridPosition), A: \(aNode.gridPosition)")
    }
}
