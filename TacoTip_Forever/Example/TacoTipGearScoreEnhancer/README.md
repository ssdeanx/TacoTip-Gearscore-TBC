# TacoTip GearScore Enhancer

TacoTip GearScore Enhancer is an unofficial companion addon for TacoTip. It adds enhancement-aware GearScore information to genuine player tooltips and enhancer-owned summaries in the Character and Inspect equipment windows. TacoTip remains separately installed and continues to provide its other features.

**Version:** 0.1.4
**Author:** NS

## Requirements

- World of Warcraft TBC Anniversary 2.5.6 (`Interface 20506`).
- TacoTip 0.5.1, installed separately and enabled.

Compatibility is intentionally exact. If the required TacoTip version or a surface-specific capability is unavailable, that enhancer surface fails closed without changing TacoTip's native display. Equipment-window compatibility can fail independently while supported player tooltips continue working.

## Features

- Current GS, Potential GS, Delta, Completion, Average iLvl, and optional Unenhanced GS for player tooltips.
- Enhancer-owned Basic and Detailed summaries for the local Character window and remote player Inspect windows.
- One shared equipment-summary mode with separately saved Character and Inspect positions.
- Locked-by-default movement using a small handle that appears only while positions are unlocked.
- Local, friendly remote, and permitted enemy remote player support with fail-closed non-player rejection.
- Native Options integration, `/ttgs`, a movable minimap shortcut, and reversible TacoTip coexistence.

## Metrics

- **Current GS** is the player's present and primary GearScore in this addon. It combines equipped-item GearScore with supported bonuses from installed permanent enchants and gems. Temporary weapon effects do not count.
- **Potential GS** adds only confirmed missing eligible permanent enchants and confirmed empty sockets to Current GS. It is not a best-in-slot estimate and does not select or recommend optimal enchants or gems.
- **Delta** is Potential GS minus Current GS. It represents only the confirmed missing enhancement potential included by this addon.
- **Completion** is the share of confirmed eligible permanent-enchant and socket opportunities that are filled. It measures enhancement completion, not character, equipment, or raid readiness.
- **Average iLvl** is the average item level across the addon's fixed TBC equipment-slot model. Enchants and gems do not affect it.
- **Unenhanced GS** is an optional comparison using the same equipped items with only the installed permanent-enchant and gem bonuses counted by this addon removed. It is not the player's present GearScore.

Potential GS, Delta, and Completion appear only when their required item and socket evidence is conclusive. Unavailable or unknown information is never represented as zero.

## Player-tooltip modes

- **Disabled:** shows no enhancer rows and safely releases the TacoTip player-GearScore takeover.
- **Minimal:** shows the shortest enabled summary, prioritizing Current GS and Average iLvl. It omits Unenhanced GS.
- **Compact:** shows up to two concise rows using `GS` for Current GS, optional Average iLvl, useful positive Delta, and Completion when available. It omits Potential GS, Unenhanced GS, and the completion fraction.
- **Detailed:** shows each enabled, available metric on a separately labelled row in this relative order: Current GS, Potential GS, Delta, Completion, Average iLvl, then Unenhanced GS when explicitly enabled.

When **Shift for Detailed** is enabled, holding Shift temporarily changes Minimal or Compact to Detailed with the same ordering. Detailed and Disabled are unchanged.

## Character and Inspect summaries

The Character and Inspect windows share one summary-mode setting:

- **Disabled:** shows no enhancer equipment summary and leaves TacoTip's native Character/Inspect GearScore and iLvl presentation in control.
- **Basic:** shows exactly `Current GS` and `Average iLvl`, with no heading or additional metrics.
- **Detailed:** shows available rows in this relative order: Current GS, Potential GS, Delta, Completion, Average iLvl, and optional Unenhanced GS last.

When Potential GS, Delta, and Completion are blocked but independently complete metrics remain usable, Detailed consolidates those enhancement rows into `Enhancement analysis: Unavailable`. A coherent scan in progress shows `Scanning equipment...`; when no usable result is available, the summary shows `Equipment data unavailable`. A successfully rendered Inspect result remains visible while the same player's Inspect window stays open, but stale cached data is not reused after the Inspect context is closed or changes. Invalid and non-player contexts show no summary, and remote results are bound to the current inspected player so an earlier player's values are cleared immediately.

The equipment-window Unenhanced preference is separate from the tooltip's `baseGS` preference. It is off by default and affects Detailed equipment summaries only.

Summary positions are locked by default. **Unlock summary positions** reveals a small drag handle and subtle outline on each currently visible summary. Only the handle receives the mouse; summary text remains mouse-disabled. Character and Inspect positions move and persist independently, use parent-relative offsets, and are clamped inside their respective safe equipment-window areas.

While Basic or Detailed is active and the exact TacoTip 0.5.1 object contract is valid, the enhancer temporarily hides TacoTip's native Character/Inspect score FontStrings and mover buttons through an in-memory visibility lease. It does not change TacoTip anchors, offsets, mover preferences, `show_gs_character`, or `show_avg_ilvl`. On release, the re-hide guard is disabled first and TacoTip's own refresh path restores its current saved presentation. No equipment visibility state is written to the recovery journal.

## Usage and settings

Open TacoTip GS Enhancer settings through any of these routes:

- `/ttgs`
- left-click the minimap button
- Esc -> Options -> AddOns -> TacoTip GS Enhancer

The main category retains tooltip, scoring-policy, minimap, restore, and reset controls. Its **Equipment Windows** child category contains the shared summary mode, the optional Detailed Unenhanced comparison, the lock/unlock control, and **Reset summary positions**. `/ttgs` and the minimap shortcut continue to open the main category.

The minimap button can be dragged around the minimap. Left-click opens the enhancer category, closes it when that exact category is active, or switches to it from another Settings category. `/ttgs` always opens or switches; it never closes Settings.

**Enable addon** is the master output switch. Disabling it retains child preferences, hides enhancer output, and releases every active TacoTip lease. **Restore TacoTip settings** remains a tooltip-only action: it disables and releases only the player-tooltip takeover and its `show_gs_player` recovery record. It does not change or suspend the equipment summary, its mode, or its positions.

A fresh profile starts with the equipment summary in Basic mode, Unenhanced GS off, positions locked, and both saved positions unset so tested defaults are used. A genuine schema-1 v0.1.1 profile migrates with the new equipment summary Disabled, preserving the user's existing native TacoTip Character/Inspect presentation until they opt in. **Reset enhancer settings** uses the fresh-profile defaults; **Reset summary positions** clears only the two equipment positions.

## Known limitations

- TacoTip 0.5.1 is required. Other TacoTip versions are unsupported until their internal compatibility contracts are validated.
- The supported client is TBC Anniversary 2.5.6.
- Remote Potential GS and Completion may be unavailable when native inspection data is not conclusive.
- TacoTip's own `/tacotip` opener may fail on the target client. Open TacoTip through Esc -> Options -> AddOns -> TacoTip instead.
- Per-slot enhancement markers, item-level or score overlays beside equipment slots, and enhancement details in item tooltips are not included.
- Current GS and Potential GS follow defined compatibility rules; they do not identify the best enhancement choices.

## Privacy and storage

Inspected player names, GUIDs, equipment, scores, diagnostics, scanner revisions, and cache entries remain session-only. SavedVariables contain normalized enhancer preferences, minimap state, independent Character/Inspect summary offsets, and the minimal recovery information needed for the managed player-tooltip setting. The Character/Inspect native-display visibility lease is memory-only.

## Credits and license

TacoTip GearScore Enhancer is independently written by NS and released under the MIT License. TacoTip is a required external dependency; it is not bundled, modified, redistributed, or forked, and this project does not imply endorsement by TacoTip or its author.

GearScore calculation behavior is derived from the MIT-licensed GearScoreTBCClassic project. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for complete attribution and license notices.
