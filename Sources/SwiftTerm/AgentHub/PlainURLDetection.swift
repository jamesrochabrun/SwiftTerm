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

  private static let urlPattern = try! NSRegularExpression(
    pattern: #"https?://[^\s<>\"'\)\]}`\x1B]+"#,
    options: [.caseInsensitive]
  )

  /// Detects a plain-text URL at the mouse event position.
  /// Returns nil if no URL is found at the click location.
  func detectPlainURL(at event: NSEvent) -> URL? {
    let hit = calculateMouseHit(with: event).grid
    let col = hit.col
    let row = hit.row

    guard let bufferLine = terminal.getLine(row: row) else {
      print("[URLDetect] no buffer line at row=\(row)")
      return nil
    }
    let lineText = bufferLine.translateToString(trimRight: true)
    print("[URLDetect] row=\(row) col=\(col) lineText='\(lineText)'")
    guard !lineText.isEmpty else { return nil }

    let nsLine = lineText as NSString
    let matches = Self.urlPattern.matches(
      in: lineText,
      range: NSRange(location: 0, length: nsLine.length)
    )
    print("[URLDetect] found \(matches.count) URL matches")

    for match in matches {
      let start = match.range.location
      let end = start + match.range.length
      let matchText = nsLine.substring(with: match.range)
      print("[URLDetect] match: '\(matchText)' range=\(start)..<\(end) col=\(col) hit=\(col >= start && col < end)")
      if col >= start && col < end {
        var urlString = matchText
        while let last = urlString.last, ".,;:!?)".contains(last) {
          urlString.removeLast()
        }
        print("[URLDetect] opening: \(urlString)")
        return URL(string: urlString)
      }
    }
    return nil
  }
}
#endif
