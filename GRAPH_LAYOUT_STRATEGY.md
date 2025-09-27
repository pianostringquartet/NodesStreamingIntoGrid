# Graph Layout Strategy: Proximity-First Placement

## Current Problems

### 1. **Unstable Two-Phase Updates**
The current system runs `updateTopologicalOrder()` twice:
1. Initial placement → topological optimization
2. Record constraints → topological optimization again

This creates unpredictable behavior where nodes move, constraints are recorded, then nodes move again.

**Example Issue:**
- C at (2,2) → N1 placed at (3,2)
- Layer assignment moves C to (1,2)
- Constraint recorded: "N1 downstream of C at layer 1"
- Second optimization creates gap between C and N1

### 2. **Overly Aggressive Global Optimization**
`assignLayers()` tries to minimize column numbers globally, fighting against user placement intent.

**User Intent:** "Place N1 downstream of C" → N1 should be adjacent to C
**System Behavior:** Moves C left to optimize layout, breaking adjacency

### 3. **Coarse Branch Shifting**
When conflicts occur, the system shifts entire branches, often moving nodes far from intended positions.

**Example:** N9 upstream of N7 → N7's branch shifts right → N9 placed at distant (0,2) instead of near N7

### 4. **No Concept of Anchor Nodes**
Selected reference nodes move during placement, disorienting users who expect visual stability.

### 5. **Conflicting Objectives**
- **User intent:** Immediate adjacency
- **Topological requirement:** Correct ordering
- **Global optimization:** Minimal column usage

Currently these fight each other instead of working together.

## Core Principles for Better Placement

### **Principle 1: Stable Placement**
- Reference nodes (selected by user) should NOT move during relative placement
- Place new nodes at ideal positions when possible
- Only move nodes when absolutely necessary for correctness

### **Principle 2: Local Conflict Resolution**
- Find nearby solutions before distant ones
- Consider multiple placement strategies:
  - Adjacent cells in same row
  - Nearby cells in different rows
  - Minimal displacement of conflicting nodes
- Avoid shifting entire branches unless no local solution exists

### **Principle 3: Single-Pass Correctness**
- Calculate correct positions once, not iteratively
- Build constraints into initial placement logic
- Eliminate multiple topological optimization passes

### **Principle 4: Respect User Intent**
- "Downstream" always means east, "upstream" always means west
- Prioritize visual proximity over global layout optimization
- Maintain predictable behavior: same action → same relative result

### **Principle 5: Explicit Intent Tracking**
- Record why each node is at its position:
  - User placement (high priority)
  - Topological requirement (medium priority)
  - Layout optimization (low priority)
- Respect intent hierarchy when making placement decisions

## Concrete Examples

### **Current vs. Desired Behavior**

#### Downstream Placement
```
Current:  C(1,2) → N1(3,2)  [gap created by optimization]
Desired:  C(1,2) → N1(2,2)  [immediate adjacency]
```

#### Upstream Placement
```
Current:  N7(3,2) → N9(0,2)  [distant placement after branch shift]
Desired:  N7(3,2) → N9(2,2)  [local adjacency]
```

#### Reference Node Stability
```
Current:  Select C(2,2), add N1 downstream → C moves to (1,2), N1 at (3,2)
Desired:  Select C(2,2), add N1 downstream → C stays at (2,2), N1 at (3,2)
```

## Implementation Roadmap

### **Phase 1: Eliminate Unstable Behavior**
- [ ] Remove double `updateTopologicalOrder()` calls
- [ ] Record spatial constraints once and apply consistently
- [ ] Ensure constraint recording happens at stable times

### **Phase 2: Implement Anchor Node Stability**
- [ ] Add concept of "locked" nodes during placement operations
- [ ] When adding upstream/downstream, lock the reference node
- [ ] Modify `assignLayers()` to respect locked nodes
- [ ] Add logging to show when nodes are locked/unlocked

### **Phase 3: Better Conflict Resolution**
- [ ] Implement local conflict resolution strategies:
  - Try adjacent cells in different rows
  - Consider minimal displacement of conflicting nodes
  - Look for nearby free positions in expanding radius
- [ ] Replace coarse `shiftBranchRight()` with targeted solutions
- [ ] Only fall back to distant placement as last resort
- [ ] Add conflict resolution logging to show decision process

### **Phase 4: Single-Pass Correctness**
- [ ] Redesign placement to be correct in one pass
- [ ] Build topological constraints into initial placement
- [ ] Eliminate need for post-placement optimization
- [ ] Ensure predictable, deterministic behavior

### **Phase 5: Intent-Based Optimization**
- [ ] Add intent tracking to nodes (user-placed vs. optimized)
- [ ] Respect intent hierarchy in all placement decisions
- [ ] Optimize layout while preserving user intent
- [ ] Add validation that user intent is never violated

## Success Metrics

### **Proximity Preservation**
- Downstream nodes placed immediately east when possible
- Upstream nodes placed immediately west when possible
- Reference nodes remain stable during relative placement

### **Predictable Behavior**
- Same action produces same relative positioning
- No unexpected distant placements
- Visual continuity maintained

### **Conflict Resolution Quality**
- Local solutions preferred over distant ones
- Minimal disruption to existing nodes
- Clear logging of placement decisions

### **User Experience**
- Selected nodes don't move unexpectedly
- Placement matches user mental model
- Visual relationships preserved

## Testing Strategy

### **Proximity Tests**
```swift
func testDownstreamImmedateAdjacency() {
    // C at (1,2) → N1 should be at (2,2)
}

func testUpstreamImmediateAdjacency() {
    // N7 at (3,2) → N9 should be at (2,2)
}

func testReferenceNodeStability() {
    // Selected node should not move during relative placement
}
```

### **Conflict Resolution Tests**
```swift
func testLocalConflictResolution() {
    // Should find nearby solutions before distant ones
}

func testMinimalDisplacement() {
    // Should minimize movement of existing nodes
}
```

### **Intent Preservation Tests**
```swift
func testUserIntentOverOptimization() {
    // User placement should not be undone by optimization
}
```

## Migration Strategy

1. **Document current behavior** with comprehensive tests
2. **Implement new system** alongside existing one
3. **A/B test** placement quality with both systems
4. **Gradual migration** with feature flags
5. **Performance validation** ensuring efficiency is maintained