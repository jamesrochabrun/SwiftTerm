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

struct AgentHubFilePathDetector {
  private struct CellRef {
    let row: Int
    let col: Int
    let width: Int
  }

  private struct LineMap {
    var text: String
    var cells: [CellRef]
    let targetRow: Int
    let targetCol: Int
    var startRow: Int
    var endRow: Int
    var explicitContinuationRows: Int
  }

  private struct RowEdgeInfo {
    let firstCol: Int
    let firstChar: Character
    let lastCol: Int
    let lastChar: Character
  }

  private static let maxExplicitContinuationRows = 4
  private static let logPrefix = "[AH-OPEN][SwiftTerm]"

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

  private static let pathContinuationCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-@+~"
  )

  static func detect(at position: Position, in terminal: Terminal) -> DetectedFilePath? {
    log("detect start position=(row:\(position.row), col:\(position.col)) cols=\(terminal.cols) yDisp=\(terminal.displayBuffer.yDisp)")
    return detect(
      at: position,
      in: terminal.displayBuffer,
      cols: terminal.cols,
      characterProvider: { terminal.getCharacter(for: $0) }
    )
  }

  static func detect(
    at position: Position,
    in buffer: Buffer,
    cols: Int,
    characterProvider: (CharData) -> Character
  ) -> DetectedFilePath? {
    guard let lineMap = buildLineMap(
      around: position,
      in: buffer,
      cols: cols,
      characterProvider: characterProvider
    ) else {
      log("detect no line map position=(row:\(position.row), col:\(position.col)) bufferRows=\(buffer.lines.count) cols=\(cols)")
      return nil
    }

    let nsLine = lineMap.text as NSString
    let matches = Self.filePathPattern.matches(
      in: lineMap.text,
      range: NSRange(location: 0, length: nsLine.length)
    )
    log("detect candidate rows=\(lineMap.startRow)...\(lineMap.endRow) explicitContinuations=\(lineMap.explicitContinuationRows) matches=\(matches.count) text=\"\(preview(lineMap.text))\"")

    var best: (result: DetectedFilePath, length: Int)?

    for match in matches {
      guard match.range.length > 0,
            let textRange = Range(match.range, in: lineMap.text)
      else {
        continue
      }

      let startOffset = lineMap.text.distance(from: lineMap.text.startIndex, to: textRange.lowerBound)
      let endOffset = lineMap.text.distance(from: lineMap.text.startIndex, to: textRange.upperBound)
      guard startOffset < lineMap.cells.count,
            endOffset > startOffset
      else {
        continue
      }

      let boundedEndOffset = min(endOffset, lineMap.cells.count)
      guard containsTarget(in: lineMap, startOffset: startOffset, endOffset: boundedEndOffset) else {
        continue
      }

      let fullMatch = nsLine.substring(with: match.range)
      guard !isURLFragment(matchText: fullMatch, matchStart: match.range.location, in: nsLine) else {
        log("detect skip url-fragment match=\"\(preview(fullMatch))\" range=\(match.range.location)..<\(match.range.location + match.range.length)")
        continue
      }

      var lineNumber: Int? = nil
      if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
        lineNumber = Int(nsLine.substring(with: match.range(at: 1)))
      }

      var column: Int? = nil
      if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
        column = Int(nsLine.substring(with: match.range(at: 2)))
      }

      var path = fullMatch
      if let colonRange = path.range(of: #":\d+(?::\d+)?$"#, options: .regularExpression) {
        path = String(path[path.startIndex..<colonRange.lowerBound])
      }
      guard path.count >= 3 else {
        continue
      }

      let result = DetectedFilePath(path: path, lineNumber: lineNumber, column: column)
      if best == nil || match.range.length > best!.length {
        best = (result, match.range.length)
      }
    }

    if let result = best?.result {
      log("detect success path=\"\(result.path)\" line=\(result.lineNumber.map(String.init) ?? "nil") column=\(result.column.map(String.init) ?? "nil")")
      return result
    }

    log("detect no containing file-path match")
    return nil
  }

  private static func buildLineMap(
    around position: Position,
    in buffer: Buffer,
    cols: Int,
    characterProvider: (CharData) -> Character
  ) -> LineMap? {
    guard position.row >= 0,
          position.row < buffer.lines.count,
          cols > 0
    else {
      return nil
    }

    let targetRow = position.row
    let targetLine = buffer.lines[targetRow]
    let rawTargetLimit = min(cols, targetLine.count)
    guard rawTargetLimit > 0 else {
      return nil
    }

    var targetCol = max(0, min(position.col, rawTargetLimit - 1))
    if targetCol > 0 && targetLine[targetCol].code == 0 && targetLine[targetCol - 1].width == 2 {
      targetCol -= 1
    }

    let startRow = findStartRow(around: targetRow, in: buffer, cols: cols, characterProvider: characterProvider)
    var map = LineMap(
      text: "",
      cells: [],
      targetRow: targetRow,
      targetCol: targetCol,
      startRow: startRow,
      endRow: startRow,
      explicitContinuationRows: 0
    )
    var row = startRow
    var explicitContinuationRows = 0

    while row < buffer.lines.count {
      map.endRow = row
      map.explicitContinuationRows = explicitContinuationRows
      let isExplicitContinuation = row > startRow && !buffer.lines[row].isWrapped
      appendRow(
        row,
        to: &map,
        in: buffer,
        cols: cols,
        stripLeadingWhitespace: isExplicitContinuation,
        characterProvider: characterProvider
      )

      let nextRow = row + 1
      guard nextRow < buffer.lines.count else {
        break
      }

      if buffer.lines[nextRow].isWrapped {
        row = nextRow
        continue
      }

      let canJoin = canJoinExplicitRows(
        upper: row,
        lower: nextRow,
        alreadyInExplicitContinuation: explicitContinuationRows > 0,
        in: buffer,
        cols: cols,
        characterProvider: characterProvider
      )
      guard canJoin && explicitContinuationRows < maxExplicitContinuationRows else {
        break
      }

      explicitContinuationRows += 1
      row = nextRow
    }

    guard !map.text.isEmpty, !map.cells.isEmpty else {
      return nil
    }
    return map
  }

  private static func findStartRow(
    around row: Int,
    in buffer: Buffer,
    cols: Int,
    characterProvider: (CharData) -> Character
  ) -> Int {
    var start = row
    while start > 0 && buffer.lines[start].isWrapped {
      start -= 1
    }

    while start > 0 {
      let upper = start - 1
      let canJoin = canJoinExplicitRows(
        upper: upper,
        lower: start,
        alreadyInExplicitContinuation: false,
        in: buffer,
        cols: cols,
        characterProvider: characterProvider
      )
      guard canJoin else {
        break
      }
      start = upper
    }

    return start
  }

  private static func appendRow(
    _ row: Int,
    to map: inout LineMap,
    in buffer: Buffer,
    cols: Int,
    stripLeadingWhitespace: Bool,
    characterProvider: (CharData) -> Character
  ) {
    let line = buffer.lines[row]
    let rawLimit = min(cols, line.count)
    let lineLimit = min(rawLimit, line.getTrimmedLength())
    guard lineLimit > 0 else {
      return
    }

    let startCol = stripLeadingWhitespace ? firstNonWhitespaceColumn(
      in: line,
      lineLimit: lineLimit,
      characterProvider: characterProvider
    ) : 0
    guard startCol < lineLimit else {
      return
    }

    for col in startCol..<lineLimit {
      if col > 0 && line[col].code == 0 && line[col - 1].width == 2 {
        continue
      }
      var character = characterProvider(line[col])
      if character == "\u{0}" {
        character = " "
      }
      map.text.append(character)
      map.cells.append(CellRef(row: row, col: col, width: max(1, Int(line[col].width))))
    }
  }

  private static func canJoinExplicitRows(
    upper: Int,
    lower: Int,
    alreadyInExplicitContinuation: Bool,
    in buffer: Buffer,
    cols: Int,
    characterProvider: (CharData) -> Character
  ) -> Bool {
    guard let upperInfo = rowEdgeInfo(row: upper, in: buffer, cols: cols, characterProvider: characterProvider),
          let lowerInfo = rowEdgeInfo(row: lower, in: buffer, cols: cols, characterProvider: characterProvider)
    else {
      return false
    }

    guard lowerInfo.firstCol > 0,
          isPathContinuationCharacter(lowerInfo.firstChar),
          isPathContinuationCharacter(upperInfo.lastChar)
    else {
      return false
    }

    if alreadyInExplicitContinuation || upperInfo.firstCol > 0 {
      return true
    }

    let continuationThreshold = max(0, cols - max(2, cols / 5))
    return upperInfo.lastCol >= continuationThreshold
  }

  private static func rowEdgeInfo(
    row: Int,
    in buffer: Buffer,
    cols: Int,
    characterProvider: (CharData) -> Character
  ) -> RowEdgeInfo? {
    guard row >= 0 && row < buffer.lines.count else {
      return nil
    }
    let line = buffer.lines[row]
    let rawLimit = min(cols, line.count)
    guard rawLimit > 0 else {
      return nil
    }
    let lineLimit = min(rawLimit, line.getTrimmedLength())
    guard lineLimit > 0 else {
      return nil
    }

    var first: (col: Int, char: Character)?
    var col = 0
    while col < lineLimit {
      if let character = characterAt(line: line, col: col, characterProvider: characterProvider),
         !character.isWhitespace {
        first = (col, character)
        break
      }
      col += 1
    }

    var last: (col: Int, char: Character)?
    var rcol = lineLimit - 1
    while rcol >= 0 {
      if let character = characterAt(line: line, col: rcol, characterProvider: characterProvider),
         !character.isWhitespace {
        last = (rcol, character)
        break
      }
      if rcol == 0 {
        break
      }
      rcol -= 1
    }

    guard let first, let last else {
      return nil
    }
    return RowEdgeInfo(
      firstCol: first.col,
      firstChar: first.char,
      lastCol: last.col,
      lastChar: last.char
    )
  }

  private static func firstNonWhitespaceColumn(
    in line: BufferLine,
    lineLimit: Int,
    characterProvider: (CharData) -> Character
  ) -> Int {
    var col = 0
    while col < lineLimit {
      if let character = characterAt(line: line, col: col, characterProvider: characterProvider),
         !character.isWhitespace {
        return col
      }
      col += 1
    }
    return lineLimit
  }

  private static func characterAt(
    line: BufferLine,
    col: Int,
    characterProvider: (CharData) -> Character
  ) -> Character? {
    guard col >= 0 && col < line.count else {
      return nil
    }
    if col > 0 && line[col].code == 0 && line[col - 1].width == 2 {
      return nil
    }
    let character = characterProvider(line[col])
    return character == "\u{0}" ? " " : character
  }

  private static func containsTarget(in lineMap: LineMap, startOffset: Int, endOffset: Int) -> Bool {
    guard startOffset < endOffset else {
      return false
    }
    for index in startOffset..<endOffset {
      let cell = lineMap.cells[index]
      if cell.row == lineMap.targetRow,
         lineMap.targetCol >= cell.col,
         lineMap.targetCol < cell.col + cell.width {
        return true
      }
    }
    return false
  }

  private static func isPathContinuationCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { pathContinuationCharacters.contains($0) }
  }

  private static func isURLFragment(matchText: String, matchStart: Int, in nsLine: NSString) -> Bool {
    if matchText.hasPrefix("//") {
      return true
    }

    if matchStart >= 3 {
      let preceding = nsLine.substring(with: NSRange(location: matchStart - 3, length: 3))
      if preceding == "://" {
        return true
      }
    }

    if matchStart > 0 {
      let prefix = nsLine.substring(with: NSRange(location: 0, length: matchStart))
      if let last = prefix.last, !last.isWhitespace {
        let tokenPrefix = prefix
          .split(whereSeparator: { $0.isWhitespace })
          .last
          .map(String.init) ?? ""
        if tokenPrefix.range(of: #"[A-Za-z][A-Za-z0-9+.-]*://\S*$"#,
                             options: .regularExpression) != nil {
          return true
        }
        if tokenPrefix.range(of: #"[A-Za-z][A-Za-z0-9+.-]*:\S*$"#,
                             options: .regularExpression) != nil {
          return true
        }
      }
      if prefix.range(of: #"[A-Za-z][A-Za-z0-9+.-]*:?//$"#, options: .regularExpression) != nil {
        return true
      }
      if prefix.range(of: #"[A-Za-z][A-Za-z0-9+.-]*:$"#, options: .regularExpression) != nil {
        return true
      }
    }

    return matchText.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                           options: .regularExpression) != nil
  }

  private static func log(_ message: @autoclosure () -> String) {
    print("\(logPrefix) \(message())")
  }

  private static func preview(_ text: String, limit: Int = 260) -> String {
    let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
    guard normalized.count > limit else {
      return normalized
    }
    return "\(normalized.prefix(limit))..."
  }
}

extension TerminalView {

  /// Detects a file path at the mouse event position.
  /// Returns nil if no file path is found at the click location.
  func detectFilePath(at event: NSEvent) -> DetectedFilePath? {
    let hit = calculateMouseHit(with: event).grid
    return AgentHubFilePathDetector.detect(at: hit, in: terminal)
  }
}
#endif
