//
//  MarkStore.swift
//  SwiftTerm — AgentHub Extension
//
//  Manages named/unnamed position markers in the terminal buffer,
//  enabling quick navigation between marked positions.
//

import Foundation

/// The kind of mark, which determines its visual appearance and behavior.
public enum MarkType: Int, Sendable {
  /// A user-placed mark (Cmd+Shift+M)
  case user
  /// An automatically placed mark at a prompt boundary (from OSC 133)
  case promptBoundary
  /// A mark placed at an error location (from trigger engine)
  case error
  /// A mark placed at the start of command output
  case output
}

/// Navigation direction for jumping between marks.
public enum MarkDirection: Sendable {
  case up
  case down
}

/// A single position marker in the terminal buffer.
public struct Mark: Identifiable, Sendable {
  public let id: UUID
  /// Buffer-absolute row index
  public var row: Int
  /// Optional user-provided label
  public let label: String?
  /// When the mark was created
  public let timestamp: Date
  /// The kind of mark
  public let type: MarkType
  /// Display color (nil uses default for the mark type)
  public let color: TerminalMarkColor?

  public init(
    id: UUID = UUID(),
    row: Int,
    label: String? = nil,
    timestamp: Date = Date(),
    type: MarkType = .user,
    color: TerminalMarkColor? = nil
  ) {
    self.id = id
    self.row = row
    self.label = label
    self.timestamp = timestamp
    self.type = type
    self.color = color
  }
}

/// Platform-independent color representation for marks.
public struct TerminalMarkColor: Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Default colors for each mark type
  public static let userDefault = TerminalMarkColor(red: 0.3, green: 0.6, blue: 1.0)
  public static let promptDefault = TerminalMarkColor(red: 0.4, green: 0.8, blue: 0.4)
  public static let errorDefault = TerminalMarkColor(red: 1.0, green: 0.3, blue: 0.3)
  public static let outputDefault = TerminalMarkColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.6)
}

/// Stores and manages marks in a terminal buffer.
///
/// Marks are stored sorted by row for efficient navigation.
/// The store provides methods to add, remove, and navigate between marks.
public final class MarkStore {

  /// All marks, sorted by row (ascending).
  public private(set) var marks: [Mark] = []

  /// The maximum number of marks to retain (prevents unbounded growth).
  public var maxMarks: Int = 1000

  public init() {}

  // MARK: - Mutation

  /// Adds a mark at the specified row.
  @discardableResult
  public func addMark(
    at row: Int,
    label: String? = nil,
    type: MarkType = .user,
    color: TerminalMarkColor? = nil
  ) -> Mark {
    let mark = Mark(row: row, label: label, type: type, color: color)
    // Insert in sorted position
    let index = marks.firstIndex(where: { $0.row > row }) ?? marks.endIndex
    marks.insert(mark, at: index)

    // Trim oldest marks if over limit
    if marks.count > maxMarks {
      marks.removeFirst(marks.count - maxMarks)
    }

    return mark
  }

  /// Removes the mark with the given ID.
  public func removeMark(id: UUID) {
    marks.removeAll { $0.id == id }
  }

  /// Removes all marks of a given type.
  public func removeMarks(ofType type: MarkType) {
    marks.removeAll { $0.type == type }
  }

  /// Removes the mark nearest to the given row (within tolerance).
  public func removeNearestMark(to row: Int, tolerance: Int = 2) {
    guard let index = marks.enumerated().min(by: {
      abs($0.element.row - row) < abs($1.element.row - row)
    })?.offset else { return }

    if abs(marks[index].row - row) <= tolerance {
      marks.remove(at: index)
    }
  }

  /// Clears all marks.
  public func removeAll() {
    marks.removeAll()
  }

  // MARK: - Navigation

  /// Finds the nearest mark in the given direction from a row.
  /// When scrolling up, includes marks at the current display position
  /// so you can return to a mark after scrolling past it.
  public func nearestMark(from row: Int, direction: MarkDirection) -> Mark? {
    switch direction {
    case .up:
      return marks.last { $0.row <= row }
    case .down:
      return marks.first { $0.row >= row }
    }
  }

  /// Returns all marks visible in the given row range.
  public func marks(inRange startRow: Int, endRow: Int) -> [Mark] {
    marks.filter { $0.row >= startRow && $0.row <= endRow }
  }

  /// Whether a mark of any type exists at the given row.
  public func hasMark(at row: Int) -> Bool {
    marks.contains { $0.row == row }
  }

  // MARK: - Scroll Adjustment

  /// Adjusts all mark rows when the scrollback buffer is trimmed.
  /// Call this when the terminal trims lines from the top of the buffer.
  public func adjustForScrollbackTrim(linesRemoved: Int) {
    guard linesRemoved > 0 else { return }
    // Remove marks that scrolled off the top
    marks.removeAll { $0.row < linesRemoved }
    // Shift remaining marks up
    for i in marks.indices {
      marks[i].row -= linesRemoved
    }
  }
}
