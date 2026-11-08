# Application management table design QA

## Target and evidence

- Selected visual: `.build/uninstall-table-qa/selected-reference.png` (1487 × 1058).
- Native light view: `.build/uninstall-table-qa/snapshots-verified/04-uninstaller-light.png`; viewport 1440 × 1024 points.
- Compact Chinese/English: `snapshots-verified/04-uninstaller-compact.png` and `04-uninstaller-light-en.png`; viewport 1000 × 700 points.
- Full comparison: `comparison-final.png`; focused column/row comparison: `comparison-detail-verified.png` under the same QA folder.
- Comparison normalizes AppKit point size and scales the reference proportionally. OS titlebar and the existing global navigation are intentional product constraints. Nine deterministic fixture rows are used for layout comparison; production icon loading was checked separately in the installed app.
- Real-machine check: installed `0.2.0 Beta (30)` in `/Applications/TraceHalo.app`. The app is left on Application Management with all 48 applications visible.

## Comparison history

1. Initial comparison found version columns too far right, overly dense row typography and a native grey selection behind the custom highlight. Shared proportional columns, 80-point rows, larger identity text and single selection drawing corrected these issues.
2. Compact English check found `Uninstall…` wrapping. A wider action column and single-line label corrected it; the final English capture shows all actions intact.
3. The automation accessibility tree summarized list rows instead of listing their child buttons. Explicit child containment was added; native pointer interaction on the visible action and keyboard Escape were verified. This is not a claim of complete VoiceOver traversal coverage.

## Required surfaces

- Typography: native SF/PingFang, 28-point title, 18-point app names, 16-point versions/sizes/actions, readable secondary paths for duplicate names. Name text is slightly smaller than the conceptual mock; it preserves space for long names in the compact window.
- Layout: one application per full-width row, aligned app/version/size/action columns, toolbar search and refresh, footer status. No permanent detail pane. The uninstall flow opens in a separate sheet.
- Colors: existing semantic light/dark tokens, white light-mode surface, restrained blue selection/action and thin dividers. Global navigation remains consistent with the rest of TraceHalo.
- Assets: real bundle icons displayed in the installed app; fixture initials remain limited to isolated snapshots.
- Copy: new labels localized in Chinese and English; compact action labels stay on one line. Defaults and confirmation language preserve existing removal semantics.

## Verification

- Baseline build 28: 399 tests passed (369 XCTest + 30 Swift Testing), zero failures. Button-only build 29: four targeted loading-rendering and version-metadata tests passed, zero failures.
- 42 native snapshots generated. Reviewed the list's light, compact and English states and focused table comparisons.
- Main app and both helpers pass signature checks and contain arm64/x86_64 slices.
- Real machine: search returns only the matching app; no-match search has no uninstall target; the selected row opens its own review; default keeps data; select-all/clear-all work; one checked file yields application + one file in the final confirmation; cancelling keeps the app in the list; reopening resets to keep; Escape closes the review; Docker retains vendor-uninstaller guidance; About was verified on build 28; installed bundle metadata and the version contract test confirm build 30.
- Verification stopped at the final confirmation and cancelled. No application or associated file was removed.
- This is a locally signed development build; no new public release was requested or published.

## Follow-up polish / limits

- The existing global sidebar and native window chrome intentionally differ from the generated concept.
- Complete VoiceOver traversal, Intel hardware and a fresh-machine administrator-approval flow were not exercised in this layout pass.

## Row action button revision

User requested a visible button on every row. The row action now uses the existing outlined `CalmButtonStyle`, including a persistent background/border and pressed state, instead of an unselected-row text link. Installed build 29 screenshot: `.build/uninstall-table-qa/row-button-qa/installed-build29.png`. Checked selected and unselected rows, button click opening the matching Blender review, default keep and cancellation back to all 48 apps. The action is a persistent button on every row, as requested.

## Button label revision

Build 30 removes the ellipsis from the table row button in Chinese and English: `卸载` / `Uninstall`. One version-metadata test and both localization-resource checks passed. Installed native screenshot: `.build/uninstall-table-qa/plain-label-qa/installed-build30.png`. The existing scanner and deletion rules were not changed in this wording revision.

final result: passed


## Data discovery and cleanup review — build 34

The application table and plain row action remain the selected layout. Removal review now explains each finding’s purpose, possible deletion impact, path, available allocated size and retention reason. Technical discovery counts live in a disclosure. Repeated introductory copy was removed, the content is leading-aligned, long explanations wrap, and the sheet explicitly receives the app locale.

Discovery reads signed host/component identities, app-group entitlements, direct LaunchAgent executable references, bounded literal script paths, exact-entry package receipts and documented Chrome/Blender locations. Scripts are never executed. Whole shared groups, name-only/unstructured findings, symlink paths and receipt-only components remain protected. Browser profiles, saved content, website data and automation files require individual selection; bulk selection is restricted to eligible caches, logs, preferences and saved-window state. ByHost matching requires an exact domain followed by a host UUID; a longer extension domain is retained. The executor also rejects protected/forged findings and overlapping selected paths before moving the app.

Observed during review: two installed WeChat copies share identifiers; Docker declares a shared app group; installed Strava/Tesla web apps declare Chrome profile subdirectories. The latter prompted an additional protection for the browser’s profile, cache and settings, with a regression fixture.

Validation: 425 tests passed (395 XCTest + 30 Swift Testing), zero failures/skips in the final serial run. A 50ms menu performance gate fluctuated to 53.03ms under concurrent compilation and to 50.37ms in another run; the threshold and menu implementation were not changed. The final full suite’s slowest warm switch was 43.47ms. Logs are retained for all attempts. Xcode project loading and localization syntax checks passed. Forty-two full native snapshots and four focused Chinese/English data-review states were generated; the final app source was manually checked after installation.

Installed `/Applications/TraceHalo.app`, 0.2.0 Beta build 34. Main app and both helpers pass deep/strict signature validation and contain arm64/x86_64 slices. The running About sheet reports build 34. English removal review uses English throughout the visible flow; Chrome shared data has lock indicators and no checkbox. In Chinese, Charles starts with keep selected, bulk selection includes only its eligible preference file, and the final alert lists that file under removal and the name-only support folder under retention. The final alert was cancelled; reopening resets to keep. Language was restored to Follow System, search was cleared and all 48 apps remain listed. No application/data was removed by manual QA.

Artifacts: `.build/data-discovery-qa/verification34.json`, `installed34-about.png`, `installed34-shared-en.png`, `installed34-selection-zh.png`, `installed34-final-confirmation.png`, `installed34-ready.png`, `snapshots33/`, `data-review33/`, `full-test34-serial.log`.

Limits: discovery is bounded and read-only, does not cover all historical/dynamic/custom writes, and does not imply complete data attribution. Personal documents, cloud data and unlisted locations are untouched. This pass did not exercise actual Trash moves, a fresh administrator/Full Disk Access approval, Intel hardware or complete VoiceOver traversal. See `docs/application-data-discovery.md`. No public release was published.

Data discovery review result: passed within the stated verification boundary.

## First-run uninstall permission setup — build 36

Permission configuration now has a shared, optional setup sheet. First active main-window launch reads actual helper/revision and Trash-access readiness after startup loading; a ready installation skips the introduction. Skipping persists across launches without implying that access was granted. Settings → Uninstall Permissions reopens the same view. Returning from System Settings probes actual access again. The main-window startup task only presents a needed introduction; it does not dismiss an existing guide on reactivation.

Helper registration, helper revision updates and opening System Settings are explicit button actions. Startup does not request administrator authorization or register a daemon. Missing permission/approval is shown inline in protected-app removal review; the old repeated helper/FDA alerts are removed. The existing target-bound administrator verification and final removal confirmation remain in place. Connection/check errors are distinct from denied Trash access, concurrent probes coalesce, and a stale successful result cannot overwrite a recorded denial.

Live build 35 checks: the introduction appeared on first launch, showed the enabled helper and denied Trash access, opened System Settings directly to Full Disk Access, remained available on return, and allowed Set Up Later. The monitor worked afterward. The app was fully quit via its menu, confirmed no longer running, and relaunched; startup completed without a repeated guide. No permission switch was changed and no app/data was removed.

Important observed state: System Settings showed TraceHalo enabled for Full Disk Access while TraceHaloUninstallHelper was disabled. Build 36 therefore explicitly names both entries and adds a collapsed missing-entry help section with Finder links. This separates background-helper approval from the helper’s file-access permission.

Final automated verification: 440 tests passed (410 XCTest + 30 Swift Testing), zero failures/skips in `full-test36-isolated.log`; all 15 new setup tests passed. An earlier full run hit the existing menu warm-switch gate at 55.21ms; the final isolated run passed at 49.30ms. No threshold or menu implementation was changed. 54 native snapshots cover existing surfaces and six setup states in both languages; denied/setup/ready layouts were visually inspected. Localization syntax, diff whitespace and Xcode project loading checks passed. The installed build 36 main app and both helpers pass deep/strict signature checks and contain arm64/x86_64 slices.

Build 36 installed at `/Applications/TraceHalo.app`; executable SHA-256 `aaddb4b6e21da11f955328ea490d4a2f90c4e4acc586e54c03fc27d9dceb7c63`. Build 35 rollback copy is under `.build/permission-onboarding-qa/install-build36/TraceHalo-build35.backup`.

Pending live checks: final build 36 About/Settings entry, missing-permission inline review and the missing-entry help links. After the user reported unlocking, `IOConsoleLocked=false` was confirmed. Native UI automation repeatedly returned `-10005 timeoutReached` when binding the installed TraceHalo, including after restarting its exact executable and opening it through Finder. Finder and System Settings remained readable; the latter still showed TraceHalo on and TraceHaloUninstallHelper off. Only one installed main-app process was running, and a process sample showed the main event loop waiting rather than a sustained busy stack. This does not establish that the app window works. Manual opening/frontmost confirmation was requested to distinguish an automation connection issue from an application window issue. These pending checks must not be represented as passed. No permission switch was changed; newly granted access and real app removal were not exercised in this pass.

Artifacts: `.build/permission-onboarding-qa/verification36.json`, `installed35-first-launch.png`, `snapshots36/`, `full-test36-isolated.log`, `build36.log`, `xcode-project.log`. No public release was published.

Build 36 follow-up result: the user confirmed that the main window could not open after unlock. The pending checks above were subsequently completed on build 37, as recorded below.

## Primary-window startup recovery and permission acceptance — build 37

The original build 36 app identity repeatedly failed to expose its main window even after restart. LaunchServices identified the expected installed executable as a foreground app. The same signed executable in an isolated diagnostic bundle opened its main window and permission guide. This narrowed the failure to launch/window recovery under the original identity, rather than proving a process deadlock. The diagnostic app was fully quit afterward.

Build 37 explicitly presents the primary SwiftUI scene and disables scene restoration on macOS 15+, matching the existing non-restorable AppKit window policy. macOS 14 keeps the original scene through the public SceneBuilder availability-erasure functions. Launch completion requests activation; an activation received before the SwiftUI bridge exists is retained and replayed once, preserving the current destination. Existing user preferences were retained. Apple API reference: https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:).

Validation: 27 targeted window/layout tests and the final full suite passed; the full suite has 441 tests (411 XCTest + 30 Swift Testing), zero failures/skips. The new test covers two early activation requests coalescing into one replay when the scene bridge becomes available, without changing the selected destination. Both arm64 and x86_64 binaries built, and the installed main app and both helpers pass deep/strict signature checks under team 4DXU5FSLLY. The running About sheet reports 0.2.0 Beta (37). Installed executable SHA-256: `e971614d1042f2ba2be40035b85ff4c4540a121930f64f432e0714d035439dd4`.

Installed UI checks passed: main-window startup and live readings; settings permission entry; correct Full Disk Access navigation; guide retained on return; denied access retained after recheck; missing-entry helper link selecting `/Applications/TraceHalo.app/Contents/Resources/TraceHaloUninstallHelper` in Finder; inline missing-permission state for 爱奇艺; opening the same setup guide from that review; cancellation retaining the app. Closing the main window and reactivating restored the interface. Full Quit was observed as not running before cold relaunch; the monitor loaded without a repeated introduction. Activation after entering menu-bar mode also restored the main interface. These activation checks used native app automation, not a physical status-item popover click.

The final app is left on Settings → Uninstall Permissions. Full Disk Access remains on for TraceHalo and off for TraceHaloUninstallHelper, so the guide correctly reports that Trash access is not ready. No permission switch was changed and no application/data was removed. Fresh administrator/helper approval, newly granted access, real deletion, Intel hardware and macOS 14 runtime remain outside this manual verification boundary.

Artifacts: `.build/permission-onboarding-qa/verification37.json`, `window-recovery/targeted37.log`, `window-recovery/full-test37.log`, `window-recovery/build37.log`, `window-recovery/installed37-about.png`, `window-recovery/installed37-permissions.png`, `window-recovery/installed37-inline-permission.png`, `window-recovery/installed37-reopened-main.png`, `window-recovery/installed37-ready-for-user.png`. Build 36 rollback copy: `.build/permission-onboarding-qa/install-build37/TraceHalo-build36.backup`. No public release was published.

Permission setup and launch recovery review result: passed within the stated verification boundary.

## Select All and explicit cleanup warnings — build 38

User-approved policy supersedes build 34's ownership-based selection restrictions. All in-scope data candidates can now be checked individually or through Select All, including uncertain/name-only paths, shared app groups, saved content, website data, automation, legacy sources and in-scope receipt findings. Ownership confidence is a visible warning rather than a veto. Exact ByHost domain/UUID matches retain stronger evidence; longer domains are selectable with an uncertainty label. A broader candidate inherits shared-use warnings for known app data below it. System/out-of-scope paths, symbolic links and parents containing hard-protected findings remain unavailable, with an explanation.

The list labels unconfirmed ownership, shared data and saved content, and explains each cleanup impact. Default removal keeps local data; choosing cleanup starts with no checks. Select All / Deselect All applies to all selectable findings. The final destructive step is a separate 660 × 610 point scrollable confirmation with warning counts and impacts, every selected target path and an expandable retained-items list. It does not truncate the path list. Text uses the primary/secondary palette for legibility with amber warning icons. Chinese and English layouts were reviewed; neutral English count labels avoid incorrect singular/plural suffixes.

Selecting a parent includes its discovered selectable children. Unchecking a child also unchecks selected ancestors. The plan moves a fully selected parent once and includes covered-child warnings in review, without incorrectly calling those children retained. The executor still checks unchanged scan membership/metadata, current-user Library scope (now including individual Group Containers), protected descendants, overlap, filesystem identity, permission and symlink constraints. The application must reach Trash before selected data cleanup begins.

Validation: the final full suite passed 451 tests (421 XCTest + 30 Swift Testing), zero failures/skips. Regression cases cover weak/shared/content selection, hard path restrictions, preserving shared warnings, parent/child deduplication, unchecked-child preservation, warning metadata tampering and executor acceptance of explicit in-scope shared/name-only selections. Eight final native snapshots cover keep, empty cleanup, all selected and final confirmation in both languages. Localization plist syntax, Xcode project loading and diff whitespace checks passed. The main app and both helpers are Universal2 (arm64/x86_64), signed under 4DXU5FSLLY and pass deep/strict verification.

Installed `/Applications/TraceHalo.app`, 0.2.0 Beta build 38; executable SHA-256 `52e47549c4b0d21471cc823b102a273f5c312a6e56f13c156853894309f8a463`. About was checked in the running app. In the real Charles review, the previously locked `~/Library/Application Support/Charles` folder is now selectable and shows uncertainty/saved-content explanations. Select All checked it and the preferences file; final review listed the app plus both paths and impacts. Deselect All cleared both; selecting only the support folder retained the preferences file, verified in the final disclosure. Confirmations were cancelled. Closing and reopening reset to Keep Local Data, where the app is left for the user. Charles and both data paths still exist; no app/data was moved and no permission was changed.

Artifacts: `.build/all-selection-qa/verification38.json`, `full-test38.log`, `build38.log`, `snapshots38-final/`, `installed38-Charles-selected.png`, `installed38-final-confirmation.png`, `installed38-individual-confirmation.png`, `installed38-about.png`, `xcode-project38.log`. Build 37 rollback copy: `.build/all-selection-qa/install-build38/TraceHalo-build37.backup`. Shared-data movement, Intel hardware and macOS 14 runtime were not exercised on real systems. No public release was published.

Select All review result: passed within the stated verification boundary.

## v0.2.1 Beta release candidate — build 39

Prepared from the latest fetched master `831619ff3c916457d144b5fb08c4a199bbbed889` on `codex/release-v0.2.1`. The app bundle, Xcode Debug/Release configurations, About fixture and version contract test now agree on 0.2.1 Beta (39). READMEs point to `docs/releases/v0.2.1.md`. Functional sources are unchanged from user-accepted build 38; the release-preparation edits only change version/build metadata and documentation.

Final candidate verification: 451 tests passed (421 XCTest + 30 Swift Testing), zero failures/skips. A source-hash manifest confirms no Sources/Tests/Tools/Resources changed between the final test run and submission preparation. The installed app and both helpers contain arm64/x86_64 slices, have Developer ID team 4DXU5FSLLY and pass deep/strict signature verification. The installed executable SHA-256 is `52a0045361d5d7182b88cc7c347d68c6a4a7b2e254982c79015e3d4037646f9c`. Native UI confirmed the running About version, main-window startup/live readings and application-management inventory. No app/data was removed and no permission was changed.

Artifacts: `.build/release-v0.2.1-qa/verification39.json`, `full-test39.log`, `build39.log`, `installed39-about.png`, `installed39-app-management.png`, `approved38-source-hashes.json`, `tested39-source-hashes.json`. Build 38 rollback copy is under `install-build39/TraceHalo-build38.backup` in that QA folder. This step prepares a reviewable code submission; it does not create a tag, publish a GitHub Release or perform public-distribution notarization.
