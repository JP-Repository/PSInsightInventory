# Console collection display

The existing inventory commands now identify PSInsightInventory, its current module version, author Jonathan Preetham and MIT license before collection. The package includes the MIT LICENSE file. Module import and Get-PSInsightInventory remain quiet; the banner appears when an inventory command runs. HTML reports retain the existing JP branding.

The banner also shows inventory name, explicit connection domain or fictional sample indication, output parent and source mode. The display uses plain text, restrained console colors and native Write-Progress rather than ANSI cursor-control sequences or an external UI dependency. Exact appearance depends on the host, font, theme and terminal width.

## During collection

Native progress updates include the stage, elapsed time, activity spinner, query outcomes received, rows observed and incomplete outcomes. A percentage appears only when an actual query plan/target count is known. It describes collection outcomes rather than a fabricated overall run percentage. Unknown discovery/bulk-query totals stay indeterminate. No ETA is guessed. Samples run at their real speed without simulated delays.

Periodic plain text heartbeats (approximately every 15 seconds while parent polling runs) provide visible information in hosts that hide progress. Preparing report data and saving reports are separate stages. A long synchronous normalization/export can hold that stage until it returns; it is not an independent rendering thread.

Group, GPO and OU workers send activity-only messages naming the current group/GPO/OU operation. User and Computer workers identify the active directory query before bulk enumeration. These messages are consumed by the parent and never enter datasets. Other collectors show returned query keys/targets as the latest outcome; the label does not imply a new per-object activity signal when none was received. DC discovery also updates while waiting. Display repainting is throttled; collection behavior and timeouts remain authoritative.

Rows observed are returned collection rows, not unique objects or a fixed inventory population. Context, derived datasets and repeated source observations must not be interpreted as one universal object count. Query denominators differ by inventory: for example, Groups includes metadata plus each group's member-list read; bulk User/Computer inventories have one query. Discovery can establish the denominator later.

Completed envelopes are deduplicated for display. Final summaries use the normalized collection ledger, including missing timed-out/failed/dependent outcomes. NotApplicable is not counted as an incomplete query; Failed, TimedOut, Partial and NotAttempted remain visible as incomplete outcomes. REPORT SAVED means local output was created, not that every source was collected or is healthy. A stopped/failed run clears the progress area and shows a stopped message while preserving the original error.

## Automation

Every existing inventory command accepts Quiet:

```powershell
$result = Invoke-ADGroupInventory -Domain ad.example.test -Quiet
$result.HtmlReport
Invoke-ADDnsInventory -Demo -Quiet
```

Quiet suppresses the banner, native progress, heartbeats and completion decoration. Warnings/errors and structured report results remain available. Host output is separate from the normal success stream. Explicitly merging streams such as 6>&1 naturally includes host information records, so use Quiet when a clean merged stream is required. ProgressPreference can hide native progress without hiding the banner/heartbeat; Quiet suppresses all decoration.

The display does not change AD/DNS/GPO/ACL configuration, send mail or add collectors. It prints no credentials. Output paths and the selected domain are expected visible context. Author, repository, support and documentation links appear only in the generated HTML Help & About section, not in the console banner.

## Validation limits

Offline tests exercise all existing sample commands plus metadata, Quiet behavior, original success objects, deduplication, known group denominator, worker activity consumption, timeout/incomplete summaries, state cleanup and packaged license. Windows PowerShell 5.1, ISE, Windows Terminal and remote/noninteractive hosts still need native visual validation. Read VALIDATION.md for the actual runtime and remaining limitations. The earlier generated image was a design illustration rather than an exact native terminal capture.
