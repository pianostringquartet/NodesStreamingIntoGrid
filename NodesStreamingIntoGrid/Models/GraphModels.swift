//
//  GraphModels.swift
//  NodesStreamingIntoGrid
//
//  Core data models for graph representation
//

import SwiftUI

struct Node: Identifiable, Equatable, CustomStringConvertible {
    let id: String
    var col: Int
    var row: Int
    var createdAt: Date = Date()

    var description: String {
        "Node(\(id) @ col:\(col), row:\(row))"
    }

    var gridPosition: GridPosition {
        GridPosition(col: col, row: row)
    }

    mutating func moveTo(position: GridPosition) {
        print("📍 Moving \(id) from (\(col),\(row)) to (\(position.col),\(position.row))")
        self.col = position.col
        self.row = position.row
    }
}

struct Edge: Identifiable, Equatable, CustomStringConvertible {
    let id = UUID()
    let from: String
    let to: String
    var createdAt: Date = Date()

    var description: String {
        "Edge(\(from) → \(to))"
    }

    static func == (lhs: Edge, rhs: Edge) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to
    }
}

struct GridPosition: Equatable, Hashable, CustomStringConvertible {
    let col: Int
    let row: Int

    var description: String {
        "(\(col),\(row))"
    }

    func offset(cols: Int = 0, rows: Int = 0) -> GridPosition {
        GridPosition(col: col + cols, row: row + rows)
    }

    func distance(to other: GridPosition) -> Double {
        let dcol = Double(col - other.col)
        let drow = Double(row - other.row)
        return sqrt(dcol * dcol + drow * drow)
    }

    var pixelPosition: CGPoint {
        let point = CGPoint(x: CGFloat(Double(col * 75) + 37.5), y: CGFloat(Double(row * 75) + 37.5))
        // Only log if this is a potentially problematic node
        if col == 2 && row == 2 {
            print("🔍 [Debug] Position calculation for (2,2): \(point)")
        }
        return point
    }

    static let gridCellSize: CGFloat = 75
    static let nodeSize: CGFloat = 50
}

enum PlacementType: String {
    case upstream = "upstream"
    case downstream = "downstream"
    case disconnected = "disconnected"
}

struct PlacementResult {
    let position: GridPosition
    let shiftsRequired: [NodeShift]
    let conflictResolution: String

    struct NodeShift {
        let nodeId: String
        let from: GridPosition
        let to: GridPosition
    }
}
