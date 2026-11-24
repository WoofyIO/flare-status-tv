import Foundation

/// The route the display takes through a long page when nobody is using the
/// remote. tvOS scrolls by moving the focus, so the route is a list of tiles
/// to focus one after another.
public enum IdleTour {
    /// The tiles to visit, top to bottom.
    ///
    /// - Parameters:
    ///   - leading: tiles shown above the groups (the "down now" block), in order.
    ///   - sections: the groups, each a list of tile ids laid out `columns` to a row.
    ///   - rowsPerStep: how many rows the focus moves down at a time.
    ///
    /// The first tile of every `rowsPerStep`-th row is a stop, and so is the
    /// last row of every group, so that every row comes on screen at least once.
    public static func stops(leading: [String], sections: [[String]], columns: Int, rowsPerStep: Int = 2) -> [String] {
        let columns = max(1, columns)
        let step = max(1, rowsPerStep)
        var result: [String] = []
        if let first = leading.first { result.append(first) }
        for tiles in sections where !tiles.isEmpty {
            let rowCount = (tiles.count + columns - 1) / columns
            var rows = Array(stride(from: 0, to: rowCount, by: step))
            if rows.last != rowCount - 1 { rows.append(rowCount - 1) }
            result.append(contentsOf: rows.map { tiles[$0 * columns] })
        }
        return result
    }

    /// The stop to move to next: the first one after the tile that has focus
    /// now, in page order, or the first stop when the focus is at or past the
    /// last one (or nowhere on the page).
    public static func next(after focused: String?, stops: [String], order: [String]) -> String? {
        guard let first = stops.first else { return nil }
        guard let focused, let position = order.firstIndex(of: focused) else { return first }
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return stops.first { (positions[$0] ?? -1) > position } ?? first
    }
}
