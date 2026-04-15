//
//  TerminalContextMenu.swift
//  SwiftTerm — AgentHub Extension
//
//  Right-click context menu with context-aware actions:
//  Copy, Paste, Open URL, Open File, Reveal in Finder, Search Google.
//

#if os(macOS)
import AppKit
import Foundation

extension TerminalView {

  // Store the event that triggered the menu for use in action methods
  private static var _lastContextMenuEvent: NSEvent?

  open override func menu(for event: NSEvent) -> NSMenu? {
    Self._lastContextMenuEvent = event
    let menu = NSMenu()

    let hasSelection = selection.active
    let selectedText = hasSelection ? selection.getSelectedText() : nil

    // -- Copy / Paste --
    if hasSelection {
      let copyItem = NSMenuItem(title: "Copy", action: #selector(contextCopy(_:)), keyEquivalent: "")
      copyItem.target = self
      menu.addItem(copyItem)
    }

    let pasteItem = NSMenuItem(title: "Paste", action: #selector(contextPaste(_:)), keyEquivalent: "")
    pasteItem.target = self
    menu.addItem(pasteItem)

    // -- URL / File actions --
    let url = detectPlainURL(at: event)
    let file = detectFilePath(at: event)

    if url != nil || file != nil {
      menu.addItem(.separator())
    }

    if let url {
      let urlItem = NSMenuItem(
        title: "Open URL",
        action: #selector(contextOpenURL(_:)),
        keyEquivalent: ""
      )
      urlItem.target = self
      urlItem.representedObject = url
      menu.addItem(urlItem)
    }

    if let file {
      let openItem = NSMenuItem(
        title: "Open File",
        action: #selector(contextOpenFile(_:)),
        keyEquivalent: ""
      )
      openItem.target = self
      openItem.representedObject = file
      menu.addItem(openItem)

      let revealItem = NSMenuItem(
        title: "Reveal in Finder",
        action: #selector(contextRevealInFinder(_:)),
        keyEquivalent: ""
      )
      revealItem.target = self
      revealItem.representedObject = file
      menu.addItem(revealItem)
    }

    // -- Search / Select All / Clear --
    menu.addItem(.separator())

    if let selectedText, !selectedText.isEmpty {
      let searchItem = NSMenuItem(
        title: "Search Google",
        action: #selector(contextSearchGoogle(_:)),
        keyEquivalent: ""
      )
      searchItem.target = self
      searchItem.representedObject = selectedText
      menu.addItem(searchItem)
    }

    let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
    selectAllItem.target = self
    menu.addItem(selectAllItem)

    let clearItem = NSMenuItem(title: "Clear Terminal", action: #selector(contextClear(_:)), keyEquivalent: "")
    clearItem.target = self
    menu.addItem(clearItem)

    return menu
  }

  // MARK: - Actions

  @objc private func contextCopy(_ sender: Any) {
    copy(sender)
  }

  @objc private func contextPaste(_ sender: Any) {
    paste(sender)
  }

  @objc private func contextOpenURL(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    terminalDelegate?.requestOpenLink(source: self, link: url.absoluteString, params: [:])
  }

  @objc private func contextOpenFile(_ sender: NSMenuItem) {
    guard let file = sender.representedObject as? DetectedFilePath else { return }
    terminalDelegate?.requestOpenFile(source: self, path: file.path, lineNumber: file.lineNumber)
  }

  @objc private func contextRevealInFinder(_ sender: NSMenuItem) {
    guard let file = sender.representedObject as? DetectedFilePath else { return }
    let path = (file.path as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: path) {
      NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
  }

  @objc private func contextSearchGoogle(_ sender: NSMenuItem) {
    guard let text = sender.representedObject as? String,
          let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://www.google.com/search?q=\(query)") else { return }
    NSWorkspace.shared.open(url)
  }

  @objc private func contextClear(_ sender: Any) {
    // Send "clear" escape: ESC[2J (clear screen) + ESC[H (cursor home)
    let clearSequence: [UInt8] = [0x1B, 0x5B, 0x32, 0x4A, 0x1B, 0x5B, 0x48]
    feed(byteArray: ArraySlice(clearSequence))
    needsDisplay = true
  }
}
#endif
