# macOS interaction parity

The Flutter sources remain the reference. Windows uses WinUI controls and a separate preferences file; macOS sources and build configuration are unchanged.

## Context menus

| Surface | Operations, in reference order |
| --- | --- |
| Connection row / pinned card | Open in terminal; Rename; Copy SSH command; separator; Pin/Unpin; Edit tags; Choose icon; Move to group; separator; New connection; New group; separator; Delete connection |
| Connection library background | New connection; New group |
| Connection group header | New connection; New group; separator; Group appearance; Rename group; Remove group |
| Favorites / Ungrouped header | New connection; New group |
| Mapping row | Edit mapping; Start/Stop mapping or selected mappings; Move to group; Copy mapping value; separator; New mapping; New group; separator; Remove mapping or selected mappings |
| Mapping background | New mapping; New group |
| Mapping group header | New mapping; New group; separator; Start group; Stop group; separator; Rename group; Remove group |

Connection-group creation preserves empty groups. New connections and mappings inherit their menu's group. Move submenus indicate the current group. Connection rename migrates tags, icon, group, favorites, recent history, proxy preferences and mapping references. Removing a group preserves its members and moves them to Ungrouped.

Ctrl+click and Shift+click select rows. Context-clicking an unselected row selects it; context-clicking a selected row preserves the selection. Mapping group operations use all group members. Mapping batch operations report failures independently. Windows shortcuts replace Command with Ctrl.

## Settings and detail pages

- Settings categories: All, Appearance, Connections, Proxy, Data & privacy, Keyboard shortcuts, About.
- Theme: System / Light / Dark. Copper, Teal, Blue, Violet and Rose use the reference light/dark palette. Reduce motion also respects Windows animation preferences.
- Segmented selections complete their slide before rebuilding dependent settings.
- Connections: start page, Windows terminal choice, connection timeout and keep-alive. OpenSSH host-specific options precede Harbor's tunnel defaults.
- Proxy: update proxy settings are separate from each connection's SSH proxy. SOCKS5 and HTTP CONNECT use a managed socket relay. Existing custom ProxyCommand takes precedence. Proxy authentication is unsupported.
- Data: recent connections can be disabled or cleared; paths open in Windows Explorer.
- About: version, automatic version checks, manual version check.
- Connection detail tabs: Overview, General, Connection, Advanced, Port mapping. General has grouping, tags and icon previews; Connection has identity selection, key creation and proxy controls. Advanced has individual option cards and a searchable picker using the reference's 28 option descriptions and examples. Port mapping edits the host's config directives separately from independent workspace mappings.
- Icon selection uses a grid, applies immediately and closes after choosing an icon. Group appearance applies immediately and supports Reset.

## Remaining visual and platform differences

This document records implemented operations, not a claim of complete visual equivalence. Menus and some dialogs still use Windows popup infrastructure with Harbor styling. File pickers and window controls use Windows behavior. Terminal choices are Windows Terminal / Console. Update installation remains manual, and activity lists Harbor-owned forwarding processes rather than system-wide SSH activity. A separate user-created group named Favorites is not implemented.

Runtime review covers both themes and all six pages, interrupted navigation, group expansion, native dialog focus animation and reduced motion. Pointer-driven rectangle selection and manual card dragging still require hands-on interaction review.

## Visual review checklist

- Top settings categories and connection detail tabs use a separate borderless button template. Pointer hover does not introduce the generic Windows button fill or border; keyboard focus remains visible.
- Segmented controls use their own sliding indicator without a selection outline. Color circles retain their color on pointer hover.
- The bottom settings control is an independent 30 by 30 button with no hover fill. The version label does not participate in hit testing.
- Appearance uses a section icon, a branded icon tile, an accent marker on the banner, the reference accent palette and compact segmented controls.
- Sidebar width follows the reference's 240-unit default, with a 220-unit compact layout. Pinned-card names truncate and star buttons have explicit bounds.
- Context menus use compact rows, theme-aware surfaces and destructive action colors. Connection/mapping menus are attached to rows, group headers and their library background.
- Action buttons use Harbor templates with custom surfaces and borders.
- Connection tabs use an animated translucent rounded selection box and a lighter matching hover preview. Settings categories use a bold active label and an animated underline, with a translucent underline on hover. Settings sections fade when categories change.
- Connection headers display the chosen host icon or initial; General also shows a preview beside Choose icon.
- Single sidebar selection belongs to one section only. Selection slides between rows in the same group and fades directly into place across groups. Insertion indicators use one canonical boundary between adjacent cards.
- Quick connect animates both entrance and dismissal. The Harbor mark includes its dark terminal backing in light and dark themes.
- Sidebar navigation selection moves directly to its destination and fades in place; it does not travel from the previously selected item.
- Scroll content reserves a separate right gutter for the scrollbar. Ordinary card text is not selectable.
- Drag from library background to rectangle-select connections, with edge scrolling and Escape cancellation. Ctrl/Shift selection is additive. Drag a row to move/reorder selected connections; drag a group header to reorder sections. Drop on Favorites to pin connections.
- The mapping selection count is centered with its toolbar buttons and updates without rebuilding the mapping rows. Segmented controls clear inherited minimum dimensions and center their contents; toggles use a compact width.
- Light mode uses darker group colors and explicit action-button foregrounds.

These changes still require visual review of the running Windows build, including DPI scaling and narrow-window layouts. They should not be described as pixel-perfect parity before that review is complete.
