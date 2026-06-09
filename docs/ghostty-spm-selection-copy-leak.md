# libghostty-spm Selection Copy Leak

## Summary

MarkAgent reproduced a per-invocation leak in `libghostty-spm` version `1.2.2` when terminal selection text was copied through `AppTerminalView.copySelectedTextToPasteboard()`.

The leak was visible in the MarkAgent `Cmd+Shift+C` terminal-snippet workflow because that workflow copied the selected terminal text before saving it as a prompt snippet.

## Affected Version

- Repository: `Lakr233/libghostty-spm`
- Version: `1.2.2`
- Revision observed by SwiftPM: `c69c34354e511af7a3e6d7e5e2a4fa2fed4b90ff`

## Evidence

In a release-signed MarkAgent app using `libghostty-spm` `1.2.2`, repeated selection-copy actions produced one additional leaked allocation per invocation:

```text
iter=1 snippets=1  Process 53913: 284 leaks for 14224 total leaked bytes.
iter=2 snippets=2  Process 53913: 285 leaks for 14352 total leaked bytes.
iter=3 snippets=3  Process 53913: 286 leaks for 14480 total leaked bytes.
iter=4 snippets=4  Process 53913: 287 leaks for 14608 total leaked bytes.
iter=5 snippets=5  Process 53913: 288 leaks for 14736 total leaked bytes.
```

With debug entitlements and `MallocStackLogging=1`, the leaked allocation resolved to the selection-copy path:

```text
heap.CAllocator.alloc
AppTerminalView.copySelectedTextToPasteboard()
TerminalSelectionPasteboardReader.readSelectedText(...)
AppDelegate.saveSnippetFromActiveTerminalSelection()
```

## Local Workaround

MarkAgent vendors `libghostty-spm` and enables Ghostty's selection clipboard support:

```swift
runtimeConfig.supports_selection_clipboard = true
```

MarkAgent then invokes Ghostty's `copy_to_clipboard` binding action instead of calling `copySelectedTextToPasteboard()` directly.

After this change, the same release-signed app produced stable zero-leak results while saving snippets:

```text
baseline  Process 73403: 0 leaks for 0 total leaked bytes.
iter=1 snippets=1  Process 73403: 0 leaks for 0 total leaked bytes.
iter=2 snippets=2  Process 73403: 0 leaks for 0 total leaked bytes.
iter=3 snippets=3  Process 73403: 0 leaks for 0 total leaked bytes.
```

## Upstream Patch

A patch was opened against `Lakr233/libghostty-spm` so AppKit selection copy can use Ghostty's clipboard callback path instead of the manual selection-read path that leaks:

- PR: https://github.com/Lakr233/libghostty-spm/pull/23
