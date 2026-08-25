# MarkAgent Design

## Workspace Foundation

`AppDelegate` owns one app-scoped `ProjectStore`. The store depends only on Foundation facilities: `UserDefaults` for persistence and `FileManager` for directory validation.

Successful project additions and updates persist canonical directory paths. Records whose directories later become unavailable remain persisted; project selection revalidates the current path before use. Terminal creation occurs only after that validation succeeds. The store does not own selection state or terminal lifecycle.

```text
AppDelegate
    |
    v
ProjectStore --> Foundation (UserDefaults, FileManager)

Workspace selection --> ProjectStore
Workspace selection --> Terminal lifecycle
```

Prohibited reverse dependencies:

- `ProjectStore` must not depend on `AppDelegate`, workspace selection, or terminal lifecycle.
- Foundation persistence and filesystem validation must not depend on UI or terminal code.
- Terminal lifecycle must not create or mutate projects before workspace validation.

### Project workspace partition

`ProjectSidebar` is the fixed primary workspace selector. Selecting a project replaces the
entire region to its right: the visible tab strip, active terminal/content, and Right Sidebar.
Tabs from another project must never appear in the selected project's visible tab strip.

`TabCollection` retains every tab object in `allTabs` so inactive Ghostty surfaces and shell
sessions remain alive. Its public `tabs` projection exposes only the active
`TabWorkspaceID` (`unscoped` or `project(Project.ID)`). Each workspace independently owns tab
order, active tab, and last active group. A/B/A switching changes only the active projection
and restores the same tab, terminal, `TabGroupState`, and right-utility route objects.

Inactive terminal views remain mounted so their Ghostty surfaces and shell sessions stay alive,
but they are not visible, hit-testable, accessible, or eligible for first-responder focus. An
inactive terminal synchronously relinquishes first responder, and deferred focus rechecks
authoritative active-workspace state on the next main runloop. Inactive nonterminal views are
unmounted while their tab/model objects remain retained; this prevents Settings, Markdown,
About, and Git Diff controls from keeping keyboard focus in another workspace.

The fixed `미분류` row exposes the launch workspace and receives open tabs when a project is
deleted. Project path edits keep existing shells and add one terminal at the new canonical
root because a live shell cannot be safely retargeted.

## Round 2 UI Shell

### Reference and visual boundary

Orca commit `b55836d` is a structure-only reference: MarkAgent adopts the left workspace navigation, central work surface, and right utility placement without Orca branding, copy, assets, colors, or materials. The spatial pattern is StyleGallery's `holy-grail` viewport shell (`patterns/viewport-shell/holy-grail.md`): semantic and focus source order remains left, main, right even when a side is automatically collapsed.

MarkAgent's existing visual tokens remain authoritative. New shell controls use the current terminal theme's `background`, `panel`, `elevated`, `foreground`, `accent`, and `border` colors; existing system typography, 4pt spacing rhythm, 6pt row/control radius, native button styles, and existing sidebar resize feedback are preserved. No Orca visual token or brand element enters the app.

```text
AppDelegate
    |
    +--> ProjectStore --> ProjectSidebar --workspace selection--> TabCollection
    |
    +--> DirectoryScanner ------------------------------+
    +--> RecentDocumentStore ---------------------------+
    +--> SidebarSearchCommandCenter --------------------+--> Right File Browser

Full-height HStack source and visual order:
ProjectSidebar | VStack(TabBarView, ActiveTabContentView) | RightSidebarView
```

The shell geometry owns the entire content height. `ProjectSidebar` spans the shared top
chrome row and body; the center tab strip begins immediately at the project column's trailing
edge; and `RightSidebarView` spans its own header, Git status, and selected body. All three
column headers use one machine-consumed `40pt` chrome-height metric so their lower edges align.
This adopts only the supplied Orca screenshots' placement contract, never Orca navigation,
branding, copy, assets, colors, or materials.

### Width and restoration contract

The supported minimum window content size is `570 x 320pt`. `AppDelegate` applies both `contentMinSize` and the corresponding decorated `minSize` before frame restoration. A saved frame is expanded to the minimum before visible-screen validation; vertical expansion preserves its top edge.

Shell width tokens are:

- Supported content minimum: `570pt`
- Reserved center: `320pt`
- Left project minimum: `220pt`
- Right utility minimum: `250pt`
- Defensive right rail: `40pt`
- Persisted requested defaults: left `260pt`, right `420pt`

For requested `260/420` widths, required allocations are:

| Content width | Project Sidebar | Center | Right utility |
|---:|---:|---:|---:|
| `570` | collapsed | `320` | expanded `250` |
| `980` | `250` | `320` | expanded `410` |
| `1440` | `260` | `760` | expanded `420` |

At every supported width, a visible right route mounts its expanded body. Below `570pt`, the allocator's rail-only behavior is defensive and unreachable through normal resizing/restoration. Automatic collapse does not mutate requested widths or persisted left visibility. Resize handles render only beside expanded panels. The center remains `minWidth: 0` so long terminal, markdown, and diff content cannot force shell overflow.

### Scroll ownership

The outer shell does not scroll. Each child owns only its content scroll:

- Project Sidebar: project list.
- Center: the active terminal, markdown preview/editor, Git diff, settings, or about surface.
- Right utility: the selected Snippets, Timeline, Git History/Changes, or File Browser body.
- File Browser retains its existing browser/search/preview/recent-document child scroll regions.

Headers, the tab bar, project action bar, horizontal utility header, Git status strip, Git mode controls, and resize handles remain fixed within their regions. No shell-level nested scroller is introduced.

### Project Sidebar primitive and state

`ProjectSidebarController` owns transient editor, rejection, and delete-request state and delegates all persistence and validation to `ProjectStore`. Add defaults the name from the selected directory. Failed add/update keeps the editor open and records `storeRejected`. Delete request and destructive confirmation are separate transitions. Selection emits the project exactly once and does not mutate the store.

`ProjectSidebar` provides a native directory-only `NSOpenPanel`, a fixed `미분류` row, project rows with name and middle-truncated path, add/edit sheet, folder replacement, destructive delete confirmation, store-rejection alert, and a `ContentUnavailableView` empty state. Selection is in-memory, starts at `미분류` on launch, and exactly one workspace row uses the existing accent token as its selected background.

Its `40pt` header contains the title, add action, and the actual `sidebar.left` hide control. When allocation removes the left column, the center `TabBarView` exposes that same identified control at its leading edge so the column can be restored. The project sidebar identifier is an accessibility grouping identifier; it must contain, not replace or propagate over, the direct identifiers of row and add/edit/delete controls.

Machine-facing controls use these identifiers on the actual interactive controls or state roots:

- `project-sidebar`, `project-sidebar-add`, `project-sidebar-empty`, `project-sidebar-empty-add`
- `project-sidebar-row-unscoped`
- `project-sidebar-row-<UUID>`, `project-sidebar-edit-<UUID>`, `project-sidebar-delete-<UUID>`
- `project-editor`, `project-editor-name`, `project-editor-path`, `project-editor-choose-folder`
- `project-editor-save`, `project-editor-cancel`, `project-delete-confirm`

### Right utility and routing

The expanded right column starts with a `40pt` horizontal utility header containing exactly four direct buttons in this order:

1. Snippets
2. Timeline
3. Git History
4. File Browser

Only one body is active. `TabGroupState.rightUtilityRoute` owns generalized visibility and selection. Selecting a tool reveals it; visibility toggling preserves selection. Snippet routing reveals Snippets. File and content search call `showFileBrowserSearch`, reveal the right File Browser, and issue exactly one matching focus request without forcing the Project Sidebar visible.

The selected tool uses the existing accent tint plus a bottom selection indicator. A trailing `sidebar.right` control collapses the expanded column. Expanded presentation is one vertical stack: horizontal utility header, divider, compact `TitlebarGitBranchView` status strip, divider, then exactly one selected body. Git Init, branch popover, refresh, and checkout behavior are unchanged, but this status is visible only inside the right column; it is not a titlebar accessory. Defensive `railOnly(40)` presentation contains one compact horizontal right-sidebar control and never a vertical tool stack. When the right column is absent, `TabBarView` exposes the identified right restore control at its trailing edge.

File Browser exists only on the right and receives the unchanged app-scoped scanner, recent-document store, current markdown URL, open callbacks, width, and search command center. Its expansion, hidden-file, preview, search, recent-document, navigation, refresh, and file-opening behavior remains intact.

### Git History and Changes

Git History is one outer tool with two group-scoped internal modes: `History` and `Changes`. The mode controls are actual interactive controls identified by `git-utility-mode-history` and `git-utility-mode-changes`. History uses `GitHistoryStore`; Changes preserves `GitDiffState`, `GitChangesSidebar`, changed-file preview, mention badges, diff-tab open/focus callbacks, refresh, and Git behavior. General right visibility is not stored in `GitDiffState`.

History executes the absolute `/usr/bin/git` binary with structured arguments:

```text
/usr/bin/git -C <repository-root> log --all --max-count=100 --date=iso-strict \
  --pretty=format:%H%x00%h%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00
```

Each record has seven NUL-terminated fields. Git's one inter-record LF is stripped only from subsequent full-hash fields; hashes, arity, UTF-8, and dates are validated, while empty and multiline bodies are preserved. Output order is Git order and the result is capped at 100 commits.

The runner has a `5s` deadline and a combined stdout/stderr ceiling of `4MiB`. It uses
`posix_spawn` with `POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT`, explicitly wires only
stdin/stdout/stderr, and passes only fixed `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and
`LC_ALL=en_US.UTF-8` environment entries. Pipe reads wait in bounded kernel `poll` windows so
descriptor closure and cancellation cannot strand a blocking read. Timeout, cancellation,
oversize output, read failure, or nonzero exit terminates and reaps the whole group with
structured cleanup, including the case where the direct child exits before a descendant.
SHA-1 and SHA-256 object IDs are accepted. Parsing runs off the main actor; publication is
guarded by request generation and standardized repository root so stale work cannot overwrite
current state.

### Workspace switching and accessibility

Project selection revalidates the current stored path through
`ProjectStore.validatedDirectoryURL(for:)`. A new project workspace receives one terminal;
subsequent selections reuse its retained tabs and group state without inserting, removing, or
recreating them. Tab creation, close replacement, reorder, tab-index shortcuts, group
shortcuts, Markdown deduplication, and Settings/About singleton behavior are scoped to the
active workspace. Configuration reload, dirty-document checks, and window-close prompting
scan `allTabs` across every workspace.

Accessibility constraints: source/focus order follows left, center, right; exactly one
workspace row is selected; every icon-only action has localized help/label text; inactive
workspace content is accessibility-hidden; destructive deletion requires confirmation and
explains that the folder remains while open tabs move to `미분류`; store rejection remains
visible while the editable draft stays available; long paths truncate in the middle without
removing their accessibility value.
