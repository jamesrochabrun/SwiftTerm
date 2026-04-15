//
//  FilePathDetection.swift
//  SwiftTerm — AgentHub Extension
//
//  Detects file paths in terminal output for Cmd+Click opening in editor.
//  Supports absolute paths, relative paths, and paths with line numbers
//  (e.g. src/Button.tsx:42).
//

#if os(macOS)
import AppKit
import Foundation

/// Result of a file path detection at a click position.
public struct DetectedFilePath {
  /// The file path (may be relative or absolute)
  public let path: String
  /// Line number if present (from `file:42` or `file:42:10` format)
  public let lineNumber: Int?
  /// Column number if present (from `file:42:10` format)
  public let column: Int?
}

extension TerminalView {

  // Matches file paths like:
  //   /absolute/path/file.ext
  //   ./relative/path/file.ext
  //   ~/home/path/file.ext
  //   src/components/Button.tsx
  //   file.swift:42
  //   file.swift:42:10
  //   path/to/file.rs:123:5
  // Requires at least one `/` or a known extension to avoid false positives on plain words.
  private static let filePathPattern = try! NSRegularExpression(
    pattern: #"(?:[~.]?/[\w./_\-@+]+|[\w./_\-@+]*?/[\w./_\-@+]+)(?::(\d+))?(?::(\d+))?"#,
    options: []
  )

  /// Detects a file path at the mouse event position.
  /// Returns nil if no file path is found at the click location.
  func detectFilePath(at event: NSEvent) -> DetectedFilePath? {
    let hit = calculateMouseHit(with: event).grid
    let col = hit.col
    let visibleRow = hit.row - terminal.displayBuffer.yDisp

    guard let bufferLine = terminal.getLine(row: visibleRow) else { return nil }
    let lineText = bufferLine.translateToString(trimRight: true)
    guard !lineText.isEmpty else { return nil }

    let nsLine = lineText as NSString
    let matches = Self.filePathPattern.matches(
      in: lineText,
      range: NSRange(location: 0, length: nsLine.length)
    )

    for match in matches {
      let start = match.range.location
      let end = start + match.range.length
      if col >= start && col < end {
        let fullMatch = nsLine.substring(with: match.range)

        var lineNumber: Int? = nil
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
          lineNumber = Int(nsLine.substring(with: match.range(at: 1)))
        }

        var column: Int? = nil
        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
          column = Int(nsLine.substring(with: match.range(at: 2)))
        }

        // Strip the :line:col suffix to get the raw path
        var path = fullMatch
        if let colonRange = path.range(of: #":\d+(?::\d+)?$"#, options: .regularExpression) {
          path = String(path[path.startIndex..<colonRange.lowerBound])
        }

        guard path.count >= 3 else { continue }

        return DetectedFilePath(path: path, lineNumber: lineNumber, column: column)
      }
    }
    return nil
  }
}
#endif
