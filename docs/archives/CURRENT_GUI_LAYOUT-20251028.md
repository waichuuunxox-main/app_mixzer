# CURRENT GUI LAYOUT (Archive snapshot) — 2025-10-28

Snapshot of `docs/CURRENT_GUI_LAYOUT.md` taken on 2025-10-28. This file is an immutable archive record for this deployed/uploaded version.

## (Archived content)

- Top-level container: GeometryReader { geo in HStack(spacing: 0) { ... } }
- LEFT pane  : `rightPaneView()` — fixed width = geo.size.width * 0.35
- Divider    : standard `Divider()` between panes
- RIGHT pane : `sidebarView()` — fixed width = geo.size.width * 0.65
- Each `RankingRow` reserves trailing transparent view to stabilize layout; overlay controls are shown via `.overlay` so they do not participate in the main HStack measurement.

## Diagnostics present in this snapshot

- `DEBUG: RankingRow.layoutProbe ...`
- `INFO: RowSafety rank=... main.maxX=... trailing.minX=... gap=... safe=...`
- `INFO: RankingsView.layoutContract -> leftFraction=0.35 rightFraction=0.65 reservedTrailing=hoverWidth+trailingStatusWidth`

---

This archived file is intended to be kept as a historical snapshot. Do not modify in-place; future snapshots will be created with new date suffixes.