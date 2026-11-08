# Application data discovery

TraceHalo performs read-only, bounded discovery when an application’s removal sheet is opened. It does not execute third-party scripts or uninstall commands, read personal document contents, monitor historical writes, or promise complete removal of all historical data.

## Evidence and scope

- Direct bundle-identifier paths under the current user’s Library and matching ByHost preference files. An exact domain followed by a valid host UUID has stronger evidence; a longer extension/app domain sharing the prefix is selectable but labeled as unconfirmed ownership.
- Identifiers and application-group entitlements from valid Apple-anchored code signatures. Embedded `.appex`, `.xpc` and login/helper apps must have the same verified signing team as the host. Shared group directories are selectable and carry a shared-data warning.
- User LaunchAgent records that directly reference an executable inside the selected app. Similar labels alone do not grant cleanup eligibility.
- Literal, quoted Library paths in bounded UTF-8 bundled scripts. Only leading `~`, `$HOME` and `${HOME}` are expanded. Expressions, substitutions, traversal and wildcard paths are rejected. A literal script reference is an unconfirmed candidate, not proof of ownership. It can be explicitly selected, including through Select All, with that warning shown.
- System package receipts whose BOM contains the exact application-bundle entry. Receipts can also list shared components. Candidates inside the allowed user Library roots are selectable with unconfirmed-ownership warnings; system/out-of-scope components remain protected. No installer scripts are run or claimed to have been audited.
- Documented location rules gated by the verified host identifier and signing team: Chrome stable’s dedicated profile/cache folders and Blender’s current major/minor configuration folder. The parent Google or Blender directory is never selected by these rules. Custom profile paths, portable settings and other application versions are outside these rules.

The inventory checks the normal system and user Applications locations. Another installed app or component claiming the same identifier, or another copy using the same documented location, marks the data as shared. Chrome-created web apps that declare a profile subdirectory also mark the browser’s profile, cache and settings as shared. A selected broader parent inherits warnings about known app data below it. This inventory cannot establish global exclusivity across arbitrary external drives or custom locations.

## User choices and execution

Local data is kept by default. Choosing cleanup starts with no data selected. Select All includes all selectable findings, including name-only/script-reference, legacy/unstructured and in-scope receipt candidates, shared app groups, browser profiles, website/sign-in data, saved content, automation and background records. Ownership uncertainty, shared use and saved-content impacts are labeled in the list and repeated in the final confirmation. No extra ownership-confirmation toggle is required. Symbolic links, system/out-of-scope components and parents containing a hard-protected finding remain unavailable. Weak evidence alone never disables selection.

Each item shows its purpose, possible deletion impact, path, available allocated size and evidence. These are category-level explanations, not a claim that the user’s data contents were inspected. The scrollable final confirmation lists every selected target, summarizes all warning categories and distinguishes selected app/data from retained findings. It has a separate destructive Confirm Removal button; opening it does not move anything. Personal documents, unlisted locations and cloud data are not cleaned.

The executor independently checks scan membership, unchanged finding metadata, cleanup eligibility, allowed user Library roots (including individual Group Containers), protected descendants, duplicate/overlapping paths, symbolic links and filesystem identity before moving anything. Selecting a parent includes its discovered selectable children. Unchecking a child also unchecks selected ancestors, so an unchecked finding cannot be removed indirectly. Plans collapse fully selected parent/child targets to the parent once; covered child warnings remain in the final review and those children are never shown as retained. The executor independently rejects overlapping targets from any unnormalized plan. The app moves first; a failed or unconfirmed app move prevents data cleanup. Existing Trash recovery and macOS permission flows remain in effect. Discovering a system component does not authorize removing it or unregistering an extension; the vendor uninstaller is recommended for those cases.

## Bounds and unknowns

At most 256 findings are returned. Embedded-component directories, script enumeration, script byte counts and receipt output are bounded; cancellation propagates into enrichment. Directory sizes use allocated blocks without following links or crossing filesystems, with per-item and overall time/entry limits. A partial or denied measurement remains unknown rather than zero. Hard-protected directories are not recursively measured. Selectable shared and uncertain directories use the same bounded metadata-only size measurement. APFS clones and sparse files mean allocated size is not a promise of reclaimable space.

The sheet reports restricted/incomplete discovery and unmeasured sizes. Absence of a finding is not evidence that no data remains. Binary-generated paths, downloaded code, plugins outside the bundle, past writes, user-selected save locations and protected/unreadable storage can remain undiscovered. The OS signature validation calls themselves are synchronous; the overall deadline is cooperative rather than a hard process timeout.

## Maintained rule sources

Checked 2026-11-08:

- [Chromium user data and cache directory rules](https://chromium.googlesource.com/chromium/src/+/main/docs/user_data_dir.md). Stable profile paths can contain history, bookmarks and cookies; overrides may use different locations.
- [Blender directory layout](https://docs.blender.org/manual/en/5.1/advanced/blender_directory_layout.html). The documented macOS version-specific user directory is used only when the current app version parses into major/minor components.
- [Apple app-group containers](https://developer.apple.com/documentation/xcode/protecting-local-app-data-using-containers).
- [Apple sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

The signing team identifiers are validated against local installed application signatures, not inferred from product names. New vendor rules must include an exact identity/signing-team gate, a primary location source, purpose/impact wording, shared-use warnings and fixture tests.


## First-run permission setup

On the first active main-window launch after onboarding is introduced, TraceHalo reads the uninstall helper’s registration/revision and checks its ability to access the current user’s Trash. Existing ready installations skip the introduction. Other installations receive one optional setup sheet after startup loading; normal monitoring remains available when setup is skipped. Settings → Uninstall Permissions reopens the same sheet. The introduction marker records only that onboarding was handled, never that a permission was granted.

Registration, helper updates and opening System Settings require explicit clicks. No permission is silently granted and no administrator credential is stored by this setup flow. Full Disk Access is broad, is explained in the sheet and must be enabled manually by the user in macOS. The guide names both TraceHalo and TraceHaloUninstallHelper; granting the main app alone does not establish that the separate helper can access Trash. Finder links help locate the programs if an entry is missing. Returning to the app rechecks the actual capability. Missing approval, outdated helpers, denied Trash access and connection/check failures are distinct states.

When a protected application is selected for removal, missing setup appears inline with a link to the setup sheet. The previous repeating Full Disk Access/helper-approval alerts are removed. The app still rechecks access, validates the selected target and performs the existing system administrator verification. The final destructive confirmation remains mandatory. Completing setup does not authorize a removal.
