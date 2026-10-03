import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct ChangeDetectorConfiguration: Sendable, Equatable {
    /// Size of a detection cell, in downsampled pixels.
    public var cellSize: Int = 8
    /// Per-pixel luminance difference regarded as a real change.
    public var pixelThreshold: Int = 24
    /// Fraction of pixels in a cell that must change for the cell to count.
    public var cellChangeRatio: Double = 0.06
    /// Regions smaller than this many cells are ignored (cursor blink, clocks...).
    public var minimumRegionCells: Int = 2
    /// Changed cells closer than this (in cells) are merged into one region.
    public var mergeDistanceCells: Int = 2
    /// EMA decay of per-cell activity. Cells that keep changing (video,
    /// animations, scrolling) become "volatile" and are suppressed.
    public var activityDecay: Double = 0.8
    public var volatileThreshold: Double = 0.6
    /// When more than this fraction of the screen changes, a single full-screen region is reported.
    public var fullScreenRatio: Double = 0.6

    public init() {}
}

/// Finds the parts of the screen that changed, ignoring noise and constantly
/// changing areas such as video.
///
/// Volatile cells are suppressed while they keep changing and are reported
/// once, as "settled", on the first frame they stop changing. That way the
/// final state of a scroll or a paused video can still be analyzed.
public struct ChangeDetector: Sendable {
    public let configuration: ChangeDetectorConfiguration
    private var activity: [Double] = []
    private var suppressed: [Bool] = []
    private var gridSize: (cols: Int, rows: Int) = (0, 0)

    public init(configuration: ChangeDetectorConfiguration = ChangeDetectorConfiguration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        activity = []
        suppressed = []
        gridSize = (0, 0)
    }

    public mutating func detect(previous: GrayscaleFrame, current: GrayscaleFrame) -> [ChangedRegion] {
        guard previous.width == current.width, previous.height == current.height else {
            reset()
            return [ChangedRegion(rect: .unit, confidence: 1)]
        }
        let cell = max(1, configuration.cellSize)
        let cols = (current.width + cell - 1) / cell
        let rows = (current.height + cell - 1) / cell
        if gridSize.cols != cols || gridSize.rows != rows {
            activity = Array(repeating: 0, count: cols * rows)
            suppressed = Array(repeating: false, count: cols * rows)
            gridSize = (cols, rows)
        }

        let ratios = cellChangeRatios(previous: previous, current: current, cols: cols, rows: rows)
        var emit = Array(repeating: false, count: cols * rows)
        var changedCount = 0
        let decay = configuration.activityDecay

        for index in ratios.indices {
            let changed = ratios[index] >= configuration.cellChangeRatio
            if changed {
                changedCount += 1
                activity[index] = activity[index] * decay + (1 - decay)
                if activity[index] >= configuration.volatileThreshold {
                    suppressed[index] = true
                } else {
                    emit[index] = true
                }
            } else {
                activity[index] *= decay
                if suppressed[index] {
                    // The area just calmed down: analyze its final state once.
                    suppressed[index] = false
                    emit[index] = true
                }
            }
        }

        let emitted = emit.filter { $0 }.count
        guard emitted > 0 else { return [] }

        if Double(changedCount) / Double(cols * rows) >= configuration.fullScreenRatio,
           Double(emitted) / Double(cols * rows) >= configuration.fullScreenRatio {
            return [ChangedRegion(rect: .unit, confidence: 1)]
        }

        let boxes = connectedBoxes(emit: emit, ratios: ratios, cols: cols, rows: rows)
        let width = CGFloat(current.width)
        let height = CGFloat(current.height)
        let regions: [ChangedRegion] = boxes.compactMap { box in
            guard box.cells >= configuration.minimumRegionCells else { return nil }
            let rect = CGRect(
                x: CGFloat(box.minCol * cell) / width,
                y: CGFloat(box.minRow * cell) / height,
                width: CGFloat((box.maxCol - box.minCol + 1) * cell) / width,
                height: CGFloat((box.maxRow - box.minRow + 1) * cell) / height
            ).clampedToUnit()
            let meanRatio = box.ratioSum / Double(box.cells)
            return ChangedRegion(rect: rect, confidence: min(1, meanRatio / 0.5))
        }
        let mergeDistance = CGFloat(configuration.mergeDistanceCells * cell) / max(width, height)
        return RegionMerger.merge(regions, within: mergeDistance)
    }

    private func cellChangeRatios(previous: GrayscaleFrame, current: GrayscaleFrame, cols: Int, rows: Int) -> [Double] {
        let cell = max(1, configuration.cellSize)
        let threshold = configuration.pixelThreshold
        var changed = Array(repeating: 0, count: cols * rows)
        var totals = Array(repeating: 0, count: cols * rows)
        previous.pixels.withUnsafeBufferPointer { old in
            current.pixels.withUnsafeBufferPointer { new in
                for y in 0..<current.height {
                    let rowBase = (y / cell) * cols
                    let pixelRow = y * current.width
                    for x in 0..<current.width {
                        let index = rowBase + x / cell
                        totals[index] += 1
                        if abs(Int(old[pixelRow + x]) - Int(new[pixelRow + x])) > threshold {
                            changed[index] += 1
                        }
                    }
                }
            }
        }
        return zip(changed, totals).map { $1 > 0 ? Double($0) / Double($1) : 0 }
    }

    private struct CellBox {
        var minCol: Int, maxCol: Int, minRow: Int, maxRow: Int
        var cells: Int
        var ratioSum: Double
    }

    /// 8-connected components of emitted cells.
    private func connectedBoxes(emit: [Bool], ratios: [Double], cols: Int, rows: Int) -> [CellBox] {
        var visited = Array(repeating: false, count: emit.count)
        var boxes: [CellBox] = []
        for start in emit.indices where emit[start] && !visited[start] {
            var box = CellBox(minCol: start % cols, maxCol: start % cols, minRow: start / cols, maxRow: start / cols, cells: 0, ratioSum: 0)
            var stack = [start]
            visited[start] = true
            while let index = stack.popLast() {
                let col = index % cols
                let row = index / cols
                box.minCol = min(box.minCol, col)
                box.maxCol = max(box.maxCol, col)
                box.minRow = min(box.minRow, row)
                box.maxRow = max(box.maxRow, row)
                box.cells += 1
                box.ratioSum += ratios[index]
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nc = col + dx
                        let nr = row + dy
                        guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                        let neighbor = nr * cols + nc
                        if emit[neighbor] && !visited[neighbor] {
                            visited[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }
            }
            boxes.append(box)
        }
        return boxes
    }
}
