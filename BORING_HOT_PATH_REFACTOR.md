# Boring Hot Path Refactor

## Goal
- Refactor QuestTogether so Blizzard-facing work follows one uniform defensive model.
- Make presenter paths boring: resolve frame, read addon-owned state, apply or clear visuals, stop.
- Remove feature-level map-open policy and other bandaid retry patterns.

## Non-Negotiable Invariants
- No feature code branches on world map visibility.
- No presenter path performs live tooltip, quest-log, task-map, or waypoint work.
- No QuestTogether state is written onto Blizzard-owned frames or frame members.
- Deferred work is coalesced through shared scheduler infrastructure, not feature-local booleans.
- Any surviving engine-specific restriction check must be documented here with why it could not be eliminated.

## Ordered Implementation
- [x] Add shared runtime restriction gate and deferred work scheduler.
- [x] Add an explicit addon-owned runtime state store and keep legacy aliases synced from it.
- [x] Route nameplate refresh through cached state and scheduled resolver work.
- [x] Remove world-map-visible nameplate branches and map-hidden retry logic.
- [x] Route quest-log drain and task-area refresh through shared scheduler.
- [x] Route waypoint/supertrack mutations through shared boundary policy.
- [x] Update tests to assert boring-hot-path behavior and use the runtime store source of truth.
- [ ] Run live-client validation and record any surviving engine-level restrictions.

## Remaining Work Checklist
- [x] Add an addon-owned quest snapshot store for title, quest-log index, task/world classification, tag metadata, and POI icon metadata.
- [x] Rebuild the quest snapshot only through the shared `quest_snapshot_refresh` worker or safe on-demand snapshot rebuilds.
- [x] Route quest scan, task-area candidate building, and nameplate title-cache rebuilds through the quest snapshot store instead of direct live quest-log walks.
- [x] Remove live `C_QuestLog` classification fallbacks from ordinary runtime helpers; classification now comes from the quest snapshot/tracker path, while live `C_QuestLog` classification is confined to snapshot building.
- [x] Remove dead legacy compatibility state and test-harness preservation for pre-refactor map-hidden pending fields.
- [x] Remove dead per-feature tint retry counter state.
- [x] Remove the remaining live `C_QuestLog` metadata fallbacks from ordinary runtime helpers and wrappers; titles, tag info, POI icon metadata, quest-log index lookup, and quest-log row lookup now resolve from snapshots or sanitized `GetQuestLogTitle()` data only.
- [x] Formalize task-area logic into a dedicated resolver/coordinator subsystem and keep it snapshot-only; live local-task engine helpers were tested and removed after they still produced delayed world-map taint.
- [ ] Re-run `/qt test` and live world-map / quest-log / combat regressions after the snapshot-store conversion.
- [ ] Record any remaining unavoidable engine restrictions and mark the checklist complete only after those are the only documented exceptions.

## Banned Patterns To Remove
- `IsWorldMapVisible` as feature logic.
- `ScheduleDeferred*AfterMapHidden` style recovery.
- Per-feature retry counters for blocked visual work.
- Live tooltip scans from presenter paths.
- Best-effort protected map mutations in feature code.

## Progress Log
- Planned architecture captured.
- Runtime inventory completed for `Core.lua`, `EventHandlers.lua`, and `Nameplates.lua`.
- Added `HotPathState.lua` and made it the runtime-owned cache/state source of truth.
- Added `HotPathRuntime.lua` and loaded it before `Nameplates.lua`.
- Added shared runtime gate and keyed deferred work scheduler.
- Bound deferred-work state, pending task/nameplate flags, and waypoint intent to the shared runtime store.
- Rewired quest-log drain, task-area refresh, nameplate presentation refresh, tooltip resolution, and waypoint mutations onto shared runtime work classes.
- Converted nameplate icon/tint refresh to cache-first presenter behavior with scheduled resolver work.
- Reset and disable paths now rebuild store-backed aliases instead of replacing ad hoc top-level tables.
- Removed the last runtime `IsWorldMapVisibleForNameplateRefresh` compatibility stub.
- Removed feature-level world-map-visible branching from runtime code.
- Updated affected tests toward runtime-gate and resolver expectations.
- Reworked the isolated test harness so runtime-store state is reset and restored through the new store helpers instead of direct top-level mutations.
- Verified Lua syntax with `luac -p` for `Core.lua`, `HotPathState.lua`, `HotPathRuntime.lua`, `Nameplates.lua`, `EventHandlers.lua`, and `Tests.lua`.
- Ran a live `/qt test` pass via the user and used the failures to fix one real scheduler defect: blocked delayed work no longer recursively re-enqueues itself under synchronous delay stubs.
- Realigned failing tests to shared-runtime behavior where feature-local pending flags and per-feature helper methods were intentionally removed.
- Fixed a live combat-end scheduler bug in `FlushDeferredWork()`: it now snapshots deferred entries before replay so Lua table iteration cannot be invalidated by mid-flush rewrites.
- Reintroduced one narrow map-specific boundary rule after live validation: `nameplate_tooltip_resolve` is blocked while the world map is visible, because Blizzard's AreaPOI/QuestOffer tooltip layout path still taints on retail if live quest-tooltip resolution runs concurrently.
- Expanded that same world-map boundary to `quest_log_drain`, `task_area_refresh`, and `quest_snapshot_refresh` after live quest-map validation showed Blizzard quest-list layout can also surface secret-number taint if QuestTogether performs quest-log/task snapshot work while the map UI is building.
- Hardened quest-log numeric wrappers so `GetQuestLogIndexForQuestID`, `GetNumQuestLogEntries`, and `GetNumQuestLeaderBoards` always return normalized primitive numbers instead of raw Blizzard numerics.
- `GetQuestLogIndexForQuestID` now prefers a sanitized quest-log scan over `C_QuestLog.GetLogIndexForQuestID`, and sanitized quest-log snapshots now carry an addon-owned `questLogIndex` so `WatchQuest()` does not need to re-query Blizzard for it during full scans.
- Removed the last runtime uses of `GetTasksTable()`, `GetTaskInfo()`, and `IsQuestOnMap()` from task-area snapshots. Task-area enter/leave detection is now derived from sanitized quest-log rows only to avoid contaminating Blizzard's map canvas and quest-list flows.
- Removed the remaining `C_QuestLog.GetLogIndexForQuestID`, `C_QuestLog.GetQuestIDForLogIndex`, and `C_QuestLog.GetInfo` fallback paths from the sanitized quest-log wrappers. On retail, quest-log snapshots now stay on the `GetQuestLogTitle()` path instead of dropping back into broader Blizzard quest-info tables.
- Disabled the legacy hidden-tooltip nameplate scan on structured-tooltip clients. On retail/mainline, QuestTogether now follows a stricter Plater-style branch split: Questie or cached state only, with no hidden `GameTooltip:SetHyperlink("unit:...")` fallback left to poison later world-map tooltip/layout flows.
- Added an explicit quest snapshot store to the runtime state and routed quest scan, task-area snapshot building, nameplate title-cache rebuilds, and ordinary quest classification/title lookups through that addon-owned snapshot.
- Restricted snapshot auto-rebuilds so blocked map/restriction windows return stale-or-empty snapshot state instead of probing live Blizzard quest APIs.
- Removed the remaining ordinary-runtime `C_QuestLog` metadata fallbacks. Snapshot consumers now no longer fall through to live `C_QuestLog` tag/theme/title/index/info helpers, and the snapshot builder itself no longer relies on `C_QuestLog.IsWorldQuest()` / `IsQuestTask()` classification probes.
- Added `TaskArea.lua` as a first-class subsystem. Task-area truth now flows through one resolver/coordinator that consumes addon-owned quest snapshot fields only and produces addon-owned resolver state plus active world/bonus snapshots.
- Cleaned up the first post-refactor architectural leftovers:
  - task-area reads are now store-backed and side-effect free; resolver rebuilds happen in refresh paths instead of snapshot accessors
  - nameplate quest title cache now reads only from the quest snapshot store and no longer owns a backup quest-log scan path
  - removed the dead quest tag/theme announcement metadata layer and standardized world/bonus/quest announcement icon policy to static cache-safe assets
  - centralized tracker/snapshot-first quest status resolution and narrowed live quest-status fallbacks behind one helper instead of probing ad hoc from multiple sites
- Removed the explicit legacy runtime alias-sync layer from `HotPathState.lua`; runtime store tables now retain identity across resets and the remaining compatibility references stay attached without a mirror pass.
- Added a small shared debounce to `task_area_refresh` so noisy map/blob/quest events coalesce through the scheduler instead of rebuilding immediately on every event.
- Tightened quest-compare/shareable status reads so they go through the shared quest-status/shareability policy instead of calling live APIs directly from comms code.

## Open Risks
- Static validation is clean, and one live `/qt test` pass already exposed and validated follow-up fixes, but another in-game `/qt test` and combat/world-map regression pass is still needed after the latest patches.
- Some legacy top-level aliases still exist as compatibility surfaces, even though the store now owns the underlying runtime data.
- The remaining live Blizzard quest dependencies are now mostly status-oriented helpers (`C_QuestLog.ReadyForTurnIn`, `IsComplete`, `IsOnQuest`, `IsPushableQuest`, `IsQuestFlaggedCompleted`) and sanitized row reads from `C_QuestLog.GetInfo`. The old task-area helpers and quest tag/theme metadata helpers are no longer part of the runtime path.
