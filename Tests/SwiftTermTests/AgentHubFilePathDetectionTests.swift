//
//  AgentHubFilePathDetectionTests.swift
//
//
//  Created by Codex on 4/18/26.
//

import Foundation
import Testing

@testable import SwiftTerm

#if os(macOS)
final class AgentHubFilePathDetectionTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
    }

    private func makeTerminal(cols: Int = 120, rows: Int = 6) -> Terminal {
        Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: rows))
    }

    private func write(_ text: String, terminal: Terminal, row: Int, col: Int = 0) {
        guard row >= 0 && row < terminal.displayBuffer.lines.count else {
            return
        }
        let line = terminal.displayBuffer.lines[row]
        var x = col
        for ch in text {
            guard x < terminal.cols else { break }
            line[x] = terminal.makeCharData(attribute: CharData.defaultAttr, char: ch)
            x += 1
        }
    }

    @Test func detectsClaudeExplicitNewlineWrappedPathFromAnySegment() {
        let terminal = makeTerminal(cols: 128, rows: 4)
        let expected = "/Users/jamesrochabrun/Desktop/git/agenthub-buenos-aires-692130/app/modules/AgentHubCore/Sources/AgentHub/Intelligence/WorktreeOrchestrationTool.swift"
        let firstSegment = "/Users/jamesrochabrun/Desktop/git/agenthub-buenos-aires-692130/app/modules/AgentHubCore/Sources/AgentHub/Intelligence/"

        write("› \(firstSegment)", terminal: terminal, row: 0)
        write("  WorktreeOrchest", terminal: terminal, row: 1)
        write("    rationTool.swift this one", terminal: terminal, row: 2)

        let firstRowResult = AgentHubFilePathDetector.detect(at: Position(col: 4, row: 0), in: terminal)
        #expect(firstRowResult?.path == expected)

        let middleRowResult = AgentHubFilePathDetector.detect(at: Position(col: 5, row: 1), in: terminal)
        #expect(middleRowResult?.path == expected)

        let finalRowResult = AgentHubFilePathDetector.detect(at: Position(col: 8, row: 2), in: terminal)
        #expect(finalRowResult?.path == expected)
    }

    @Test func detectsNativeTerminalWrappedPath() {
        let terminal = makeTerminal(cols: 16, rows: 4)
        terminal.feed(text: "/tmp/very/long/path/File.swift")

        let result = AgentHubFilePathDetector.detect(at: Position(col: 2, row: 1), in: terminal)
        #expect(result?.path == "/tmp/very/long/path/File.swift")
    }

    @Test func doesNotReturnURLFragmentsAsFilePaths() {
        let terminal = makeTerminal(cols: 80, rows: 2)
        write("https://example.com/path/File.swift", terminal: terminal, row: 0)

        let result = AgentHubFilePathDetector.detect(at: Position(col: 22, row: 0), in: terminal)
        #expect(result == nil)
    }

    @Test func detectsPathAfterColonSeparatedLabel() {
        let terminal = makeTerminal(cols: 80, rows: 1)
        write("error: /tmp/example.swift", terminal: terminal, row: 0)

        let result = AgentHubFilePathDetector.detect(at: Position(col: 10, row: 0), in: terminal)
        #expect(result?.path == "/tmp/example.swift")
    }

    @Test func parsesLineAndColumnSuffix() {
        let terminal = makeTerminal(cols: 80, rows: 1)
        write("src/components/Button.swift:42:10", terminal: terminal, row: 0)

        let result = AgentHubFilePathDetector.detect(at: Position(col: 5, row: 0), in: terminal)
        #expect(result?.path == "src/components/Button.swift")
        #expect(result?.lineNumber == 42)
        #expect(result?.column == 10)
    }

    @Test func stopsBeforeUnrelatedIndentedRows() {
        let terminal = makeTerminal(cols: 80, rows: 3)
        write("/tmp/example.swift", terminal: terminal, row: 0)
        write("  unrelated continuation", terminal: terminal, row: 1)

        let pathResult = AgentHubFilePathDetector.detect(at: Position(col: 4, row: 0), in: terminal)
        #expect(pathResult?.path == "/tmp/example.swift")

        let unrelatedResult = AgentHubFilePathDetector.detect(at: Position(col: 4, row: 1), in: terminal)
        #expect(unrelatedResult == nil)
    }
}
#endif
