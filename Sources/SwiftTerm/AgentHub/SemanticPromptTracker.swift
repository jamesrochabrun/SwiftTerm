//
//  SemanticPromptTracker.swift
//  SwiftTerm — AgentHub Extension
//
//  Tracks OSC 133 semantic prompt boundaries (FinalTerm protocol).
//  This enables features like click-to-move-cursor and prompt/output
//  distinction in the terminal.
//

import Foundation

/// Describes the type of a semantic prompt region boundary.
public enum PromptRegionType: Sendable {
  /// `A` — Prompt has started (the shell is drawing the prompt)
  case promptStart
  /// `B` — User input has started (prompt is complete, user is typing)
  case inputStart
  /// `C` — Command output has started (command is executing)
  case outputStart
  /// `D` — Command has completed with an exit code
  case commandComplete
}

/// A single OSC 133 event recorded at a specific buffer row.
public struct PromptEvent: Sendable {
  public let type: PromptRegionType
  public let row: Int
  public let exitCode: Int?
  public let timestamp: Date

  public init(type: PromptRegionType, row: Int, exitCode: Int? = nil, timestamp: Date = Date()) {
    self.type = type
    self.row = row
    self.exitCode = exitCode
    self.timestamp = timestamp
  }
}

/// A fully resolved prompt region spanning prompt -> input -> output -> completion.
public struct PromptRegion: Sendable {
  /// Row where the prompt started rendering
  public let promptRow: Int
  /// Row where user input began (after prompt)
  public let inputRow: Int?
  /// Row where command output began
  public let outputRow: Int?
  /// Row where command completed
  public let completionRow: Int?
  /// Exit code of the completed command (nil if still running or no D marker)
  public let exitCode: Int?

  /// Whether this region represents a completed command
  public var isComplete: Bool { completionRow != nil }

  /// Whether a given row falls within the prompt area (between A and B)
  public func isInPrompt(_ row: Int) -> Bool {
    guard let inputRow else { return row >= promptRow }
    return row >= promptRow && row < inputRow
  }

  /// Whether a given row falls within the input area (between B and C)
  public func isInInput(_ row: Int) -> Bool {
    guard let inputRow else { return false }
    guard let outputRow else { return row >= inputRow }
    return row >= inputRow && row < outputRow
  }

  /// Whether a given row falls within the output area (between C and D)
  public func isInOutput(_ row: Int) -> Bool {
    guard let outputRow else { return false }
    guard let completionRow else { return row >= outputRow }
    return row >= outputRow && row < completionRow
  }
}

/// Tracks OSC 133 semantic prompt events and builds prompt regions.
///
/// Usage:
/// ```swift
/// let tracker = SemanticPromptTracker()
/// terminal.registerOscHandler(code: 133, handler: tracker.handleOsc133)
/// ```
public final class SemanticPromptTracker {

  /// All recorded prompt events, in order of arrival.
  public private(set) var events: [PromptEvent] = []

  /// Resolved prompt regions built from events.
  public private(set) var regions: [PromptRegion] = []

  /// The current in-progress region (prompt started but not yet complete).
  public private(set) var currentRegion: PartialPromptRegion?

  public init() {}

  /// OSC 133 handler — register this on the Terminal instance.
  ///
  /// Call: `terminal.registerOscHandler(code: 133, handler: tracker.handleOsc133)`
  public func handleOsc133(_ data: ArraySlice<UInt8>) {
    // OSC 133 format: "X" or "X;extra" where X is A/B/C/D
    guard let first = data.first else { return }
    let command = Character(UnicodeScalar(first))

    switch command {
    case "A":
      recordEvent(.promptStart)
    case "B":
      recordEvent(.inputStart)
    case "C":
      recordEvent(.outputStart)
    case "D":
      let exitCode = parseExitCode(from: data)
      recordEvent(.commandComplete, exitCode: exitCode)
    default:
      break
    }
  }

  /// Records an event and builds/updates regions.
  ///
  /// - Parameters:
  ///   - type: The prompt region boundary type.
  ///   - row: The buffer row (defaults to -1; caller should set if available).
  ///   - exitCode: Exit code for `.commandComplete` events.
  public func recordEvent(_ type: PromptRegionType, row: Int = -1, exitCode: Int? = nil) {
    let event = PromptEvent(type: type, row: row, exitCode: exitCode)
    events.append(event)
    updateRegions(with: event)
  }

  /// Updates the row for the most recent event of a given type.
  /// Called from the terminal delegate when the actual row is known.
  public func updateLastEventRow(_ row: Int, for type: PromptRegionType) {
    guard let index = events.lastIndex(where: { $0.type == type }) else { return }
    let old = events[index]
    events[index] = PromptEvent(type: old.type, row: row, exitCode: old.exitCode, timestamp: old.timestamp)
    rebuildRegions()
  }

  /// Finds the region containing a given row, if any.
  public func region(containing row: Int) -> PromptRegion? {
    regions.last { region in
      row >= region.promptRow && (region.completionRow.map { row < $0 } ?? true)
    }
  }

  /// Clears all tracked state.
  public func reset() {
    events.removeAll()
    regions.removeAll()
    currentRegion = nil
  }

  // MARK: - Private

  private func updateRegions(with event: PromptEvent) {
    switch event.type {
    case .promptStart:
      // Finalize any in-progress region
      if let partial = currentRegion {
        regions.append(partial.finalize())
      }
      currentRegion = PartialPromptRegion(promptRow: event.row)

    case .inputStart:
      currentRegion?.inputRow = event.row

    case .outputStart:
      currentRegion?.outputRow = event.row

    case .commandComplete:
      currentRegion?.completionRow = event.row
      currentRegion?.exitCode = event.exitCode
      if let partial = currentRegion {
        regions.append(partial.finalize())
      }
      currentRegion = nil
    }
  }

  private func rebuildRegions() {
    regions.removeAll()
    currentRegion = nil
    for event in events {
      updateRegions(with: event)
    }
  }

  private func parseExitCode(from data: ArraySlice<UInt8>) -> Int? {
    // Format: "D;exitCode" or just "D"
    let bytes = Array(data)
    guard bytes.count > 2, bytes[1] == UInt8(ascii: ";") else { return nil }
    let codeStr = String(bytes: Array(bytes[2...]), encoding: .utf8) ?? ""
    return Int(codeStr)
  }
}

/// Intermediate state while building a prompt region.
public class PartialPromptRegion {
  public var promptRow: Int
  public var inputRow: Int?
  public var outputRow: Int?
  public var completionRow: Int?
  public var exitCode: Int?

  init(promptRow: Int) {
    self.promptRow = promptRow
  }

  func finalize() -> PromptRegion {
    PromptRegion(
      promptRow: promptRow,
      inputRow: inputRow,
      outputRow: outputRow,
      completionRow: completionRow,
      exitCode: exitCode
    )
  }
}
