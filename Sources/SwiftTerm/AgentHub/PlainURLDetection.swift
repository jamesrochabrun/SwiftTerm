//
//  PlainURLDetection.swift
//  SwiftTerm — AgentHub Extension
//
//  Detects plain-text URLs in terminal output for Cmd+Click opening.
//  This supplements OSC 8 hyperlinks by making any visible URL clickable.
//

#if os(macOS)
import AppKit
import Foundation

extension TerminalView {

  // Match only RFC 3986 URL characters — stops at em-dashes, spaces, quotes, etc.
  private static let urlPattern = try! NSRegularExpression(
    pattern: #"https?://[a-zA-Z0-9._~:/?#\[\]@!$&'()*+,;=\-%]+"#,
    options: [.caseInsensitive]
  )

  /// Detects a plain-text URL at the mouse event position.
  /// Returns nil if no URL is found at the click location.
  func detectPlainURL(at event: NSEvent) -> URL? {
    let hit = calculateMouseHit(with: event).grid
    let col = hit.col
    let visibleRow = hit.row - terminal.displayBuffer.yDisp

    guard let bufferLine = terminal.getLine(row: visibleRow) else { return nil }
    let lineText = bufferLine.translateToString(trimRight: true)
    guard !lineText.isEmpty else { return nil }

    let nsLine = lineText as NSString
    let matches = Self.urlPattern.matches(
      in: lineText,
      range: NSRange(location: 0, length: nsLine.length)
    )

    for match in matches {
      let start = match.range.location
      let end = start + match.range.length
      if col >= start && col < end {
        var urlString = nsLine.substring(with: match.range)
        while let last = urlString.last, ".,;:!?)".contains(last) {
          urlString.removeLast()
        }
        return URL(string: urlString)
      }
    }
    return nil
  }
}
#endif
