//
//  URLHighlightOverlay.swift
//  SwiftTerm — AgentHub Extension
//
//  Highlights URLs under the cursor when Cmd is held,
//  providing visual feedback for Cmd+Click to open.
//

#if os(macOS)
import AppKit
import Foundation

extension TerminalView {

  private static let highlightViewID = "com.agenthub.urlHighlight"

  /// Shows a highlight overlay on a detected URL at the given mouse position.
  /// Call from mouseMoved when command key is active.
  func updateURLHighlight(at event: NSEvent) {
    removeURLHighlight()

    let hit = calculateMouseHit(with: event).grid
    let col = hit.col
    let row = hit.row

    guard let bufferLine = terminal.getLine(row: row) else { return }
    let lineText = bufferLine.translateToString(trimRight: true)
    guard !lineText.isEmpty else { return }

    // Find URL at cursor position
    let pattern = try! NSRegularExpression(
      pattern: #"https?://[^\s<>\"'\)\]}`\x1B]+"#,
      options: [.caseInsensitive]
    )
    let nsLine = lineText as NSString
    let matches = pattern.matches(in: lineText, range: NSRange(location: 0, length: nsLine.length))

    for match in matches {
      let start = match.range.location
      let end = start + match.range.length
      if col >= start && col < end {
        // Calculate the visual position of the URL
        let displayRow = row - terminal.displayBuffer.yDisp
        let cellW = cellDimension.width
        let cellH = cellDimension.height

        let x = CGFloat(start) * cellW
        let y = bounds.height - CGFloat(displayRow + 1) * cellH
        let width = CGFloat(match.range.length) * cellW

        // Draw underline highlight
        let underline = NSView(frame: CGRect(x: x, y: y - 1, width: width, height: 1.5))
        underline.wantsLayer = true
        underline.layer?.backgroundColor = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.8).cgColor
        underline.setAccessibilityIdentifier(Self.highlightViewID)
        addSubview(underline)

        // Also show the URL as a tooltip-style preview
        let urlString = nsLine.substring(with: match.range)
        showURLTooltip(urlString, at: CGPoint(x: x, y: y + cellH))

        // Change cursor to pointing hand
        NSCursor.pointingHand.set()
        return
      }
    }
  }

  /// Removes any URL highlight overlay.
  func removeURLHighlight() {
    subviews
      .filter { $0.accessibilityIdentifier() == Self.highlightViewID || $0.accessibilityIdentifier() == "com.agenthub.urlTooltip" }
      .forEach { $0.removeFromSuperview() }
    NSCursor.arrow.set()
  }

  private func showURLTooltip(_ url: String, at point: CGPoint) {
    let label = NSTextField(labelWithString: url)
    label.setAccessibilityIdentifier("com.agenthub.urlTooltip")
    label.font = .systemFont(ofSize: 10, weight: .regular)
    label.textColor = NSColor(white: 0.9, alpha: 1)
    label.backgroundColor = NSColor(white: 0.15, alpha: 0.95)
    label.isBezeled = false
    label.isEditable = false
    label.drawsBackground = true
    label.wantsLayer = true
    label.layer?.cornerRadius = 3
    label.layer?.masksToBounds = true
    label.sizeToFit()
    label.frame.size.width = min(label.frame.width + 8, bounds.width - 16)
    label.frame.size.height += 4
    label.frame.origin = CGPoint(
      x: min(point.x, bounds.width - label.frame.width - 4),
      y: point.y
    )
    addSubview(label)
  }
}
#endif
