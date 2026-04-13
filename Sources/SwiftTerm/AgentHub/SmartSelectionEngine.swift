//
//  SmartSelectionEngine.swift
//  SwiftTerm — AgentHub Extension
//
//  Provides context-aware text selection in the terminal.
//  Recognizes URLs, file paths, emails, IP addresses, and
//  bracket-delimited text for intelligent double-click selection.
//

import Foundation

/// The type of content that was smart-selected.
public enum SmartSelectionType: Sendable {
  case url
  case filePath
  case email
  case ipAddress
  case quotedString
  case bracketedExpression
}

/// Result of a smart selection attempt.
public struct SmartSelectionResult: Sendable {
  /// The type of content matched
  public let type: SmartSelectionType
  /// Start column in the buffer line
  public let startCol: Int
  /// End column (exclusive) in the buffer line
  public let endCol: Int
  /// The matched text
  public let text: String

  public init(type: SmartSelectionType, startCol: Int, endCol: Int, text: String) {
    self.type = type
    self.startCol = startCol
    self.endCol = endCol
    self.text = text
  }
}

/// Protocol for pluggable selection recognizers.
public protocol SelectionRecognizer {
  /// The type of content this recognizer handles.
  var selectionType: SmartSelectionType { get }

  /// Attempts to expand a selection around the given index in the line text.
  /// Returns the range of the recognized content, or nil if no match.
  func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>?
}

// MARK: - Built-in Recognizers

/// Recognizes http://, https://, ftp://, and ssh:// URLs.
public struct URLRecognizer: SelectionRecognizer {
  public let selectionType: SmartSelectionType = .url
  // Matches common URL patterns
  private let pattern = try! NSRegularExpression(
    pattern: #"https?://[^\s<>\"'\)\]}`]+"#,
    options: [.caseInsensitive]
  )

  public init() {}

  public func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>? {
    let utf16Offset = text.utf16.distance(from: text.startIndex, to: index)
    let nsRange = NSRange(location: 0, length: text.utf16.count)
    let matches = pattern.matches(in: text, range: nsRange)

    for match in matches {
      if match.range.location <= utf16Offset && utf16Offset < match.range.location + match.range.length {
        return Range(match.range, in: text)
      }
    }
    return nil
  }
}

/// Recognizes absolute and relative file paths.
public struct FilePathRecognizer: SelectionRecognizer {
  public let selectionType: SmartSelectionType = .filePath
  // Matches paths like /foo/bar, ./foo, ~/bar, or paths with common extensions
  private let pattern = try! NSRegularExpression(
    pattern: #"(?:[~.]?/|(?:[a-zA-Z]:\\))[\w./_-]+"#,
    options: []
  )

  public init() {}

  public func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>? {
    let utf16Offset = text.utf16.distance(from: text.startIndex, to: index)
    let nsRange = NSRange(location: 0, length: text.utf16.count)
    let matches = pattern.matches(in: text, range: nsRange)

    for match in matches {
      if match.range.location <= utf16Offset && utf16Offset < match.range.location + match.range.length {
        return Range(match.range, in: text)
      }
    }
    return nil
  }
}

/// Recognizes email addresses.
public struct EmailRecognizer: SelectionRecognizer {
  public let selectionType: SmartSelectionType = .email
  private let pattern = try! NSRegularExpression(
    pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
    options: []
  )

  public init() {}

  public func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>? {
    let utf16Offset = text.utf16.distance(from: text.startIndex, to: index)
    let nsRange = NSRange(location: 0, length: text.utf16.count)
    let matches = pattern.matches(in: text, range: nsRange)

    for match in matches {
      if match.range.location <= utf16Offset && utf16Offset < match.range.location + match.range.length {
        return Range(match.range, in: text)
      }
    }
    return nil
  }
}

/// Recognizes IPv4 addresses.
public struct IPAddressRecognizer: SelectionRecognizer {
  public let selectionType: SmartSelectionType = .ipAddress
  private let pattern = try! NSRegularExpression(
    pattern: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?::\d+)?\b"#,
    options: []
  )

  public init() {}

  public func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>? {
    let utf16Offset = text.utf16.distance(from: text.startIndex, to: index)
    let nsRange = NSRange(location: 0, length: text.utf16.count)
    let matches = pattern.matches(in: text, range: nsRange)

    for match in matches {
      if match.range.location <= utf16Offset && utf16Offset < match.range.location + match.range.length {
        return Range(match.range, in: text)
      }
    }
    return nil
  }
}

/// Recognizes single- or double-quoted strings.
public struct QuotedStringRecognizer: SelectionRecognizer {
  public let selectionType: SmartSelectionType = .quotedString

  public init() {}

  public func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>? {
    let offset = text.distance(from: text.startIndex, to: index)

    // Try both quote styles
    for quote in ["\"", "'"] {
      if let range = findQuotedRange(in: text, around: offset, quote: Character(quote)) {
        return range
      }
    }
    return nil
  }

  private func findQuotedRange(in text: String, around offset: Int, quote: Character) -> Range<String.Index>? {
    let chars = Array(text)
    guard offset < chars.count else { return nil }

    // Search backward for opening quote
    var start = offset
    while start > 0 {
      start -= 1
      if chars[start] == quote {
        // Search forward for closing quote
        var end = offset
        while end < chars.count - 1 {
          end += 1
          if chars[end] == quote {
            // Return range including the quotes
            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(text.startIndex, offsetBy: end + 1)
            return startIndex..<endIndex
          }
        }
        break
      }
    }
    return nil
  }
}

/// Recognizes bracket-delimited expressions: (), [], {}.
public struct BracketedRecognizer: SelectionRecognizer {
  public let selectionType: SmartSelectionType = .bracketedExpression

  private static let pairs: [(open: Character, close: Character)] = [
    ("(", ")"), ("[", "]"), ("{", "}")
  ]

  public init() {}

  public func expandSelection(in text: String, around index: String.Index) -> Range<String.Index>? {
    let offset = text.distance(from: text.startIndex, to: index)
    let chars = Array(text)
    guard offset < chars.count else { return nil }

    for pair in Self.pairs {
      if let range = findBracketedRange(in: chars, around: offset, open: pair.open, close: pair.close) {
        let startIndex = text.index(text.startIndex, offsetBy: range.lowerBound)
        let endIndex = text.index(text.startIndex, offsetBy: range.upperBound)
        return startIndex..<endIndex
      }
    }
    return nil
  }

  private func findBracketedRange(
    in chars: [Character],
    around offset: Int,
    open: Character,
    close: Character
  ) -> Range<Int>? {
    // Search backward for opening bracket
    var depth = 0
    var start = offset
    while start >= 0 {
      if chars[start] == close { depth += 1 }
      if chars[start] == open {
        if depth == 0 {
          // Found opening bracket, now search forward for closing
          var end = offset
          var innerDepth = 0
          while end < chars.count {
            if chars[end] == open { innerDepth += 1 }
            if chars[end] == close {
              innerDepth -= 1
              if innerDepth == 0 {
                return start..<(end + 1)
              }
            }
            end += 1
          }
          break
        }
        depth -= 1
      }
      start -= 1
    }
    return nil
  }
}

// MARK: - Smart Selection Engine

/// Engine that runs multiple recognizers to find the best smart selection.
///
/// Recognizers are tried in priority order. The first match wins.
/// Custom recognizers can be added via `addRecognizer(_:)`.
public final class SmartSelectionEngine {

  private var recognizers: [SelectionRecognizer]

  /// Creates an engine with the default set of recognizers (URL > path > email > IP > quoted > bracketed).
  public init() {
    self.recognizers = [
      URLRecognizer(),
      FilePathRecognizer(),
      EmailRecognizer(),
      IPAddressRecognizer(),
      QuotedStringRecognizer(),
      BracketedRecognizer()
    ]
  }

  /// Adds a custom recognizer at the given priority (lower index = higher priority).
  public func addRecognizer(_ recognizer: SelectionRecognizer, at index: Int? = nil) {
    if let index, index < recognizers.count {
      recognizers.insert(recognizer, at: index)
    } else {
      recognizers.append(recognizer)
    }
  }

  /// Attempts smart selection at a column position within a line of text.
  ///
  /// - Parameters:
  ///   - col: The column position (0-based) where the user double-clicked.
  ///   - lineText: The full text of the terminal line.
  /// - Returns: A `SmartSelectionResult` if any recognizer matched, nil otherwise.
  public func expandSelection(col: Int, lineText: String) -> SmartSelectionResult? {
    guard !lineText.isEmpty, col >= 0 else { return nil }

    // Convert column to string index (terminal columns may differ from string indices for wide chars)
    let clampedCol = min(col, lineText.count - 1)
    let index = lineText.index(lineText.startIndex, offsetBy: clampedCol)

    for recognizer in recognizers {
      if let range = recognizer.expandSelection(in: lineText, around: index) {
        let startCol = lineText.distance(from: lineText.startIndex, to: range.lowerBound)
        let endCol = lineText.distance(from: lineText.startIndex, to: range.upperBound)
        let text = String(lineText[range])
        return SmartSelectionResult(
          type: recognizer.selectionType,
          startCol: startCol,
          endCol: endCol,
          text: text
        )
      }
    }
    return nil
  }
}
