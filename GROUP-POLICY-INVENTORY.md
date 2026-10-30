# Group Policy Inventory

`Invoke-ADGroupPolicyInventory` creates a read-only configuration snapshot for one explicit domain, with a JP-branded offline report, JSON snapshot, CSV datasets and JSONL logs. It is part of PSInsightInventory and remains independent of PSInsightExpl.

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Get-PSInsightInventory
Get-Help Invoke-ADGroupPolicyInventory -Examples
Invoke-ADGroupPolicyInventory -Demo -Open
Invoke-ADGroupPolicyInventory -Domain ad.example.test -Open
Invoke-ADGroupPolicyInventory -Domain example.test -TimeoutSeconds 600 -OutputPath C:\Temp\Reports -Open
```

## Inventory rather than assessment

This report describes what exists and its returned configuration. It has no severity, score, cleanup recommendation or effective-policy verdict. An observed link count is scoped evidence; it is not proof a GPO is unused or can be deleted. Reported permission levels are not a complete effective-access evaluation. Use PSInsightExpl for assessment workflows.

The 11 navigation sections are overview, GPOs, versions, link containers, links, reported permissions, domain WMI filters, GPO WMI references, settings structure, object collection and category collection. Open a GPO to see its versions, links, permissions, WMI reference, locally matching WMI definition, settings structure and collection outcomes together. Container details show related links; WMI filter details show matching local-domain references. Search, sorting, pagination, column selection, light/dark themes and filtered CSV/full JSON downloads use the same normalized snapshot.

## Collected data and boundaries

| Dataset | Captured configuration |
|---|---|
| GPOs | Display name, GUID, domain, owner, status, description and timestamps |
| Versions | User/computer AD and SYSVOL versions reported by Get-GPO on the pinned DC |
| Link containers | Domain root, OUs in the selected domain, and forest sites; inheritance option and link counts |
| Links | Selected-domain GPO references, container identity, link order, enabled/enforced flags and raw option bits |
| Permissions | Get-GPPermission levels, trustee names/domain/SID/type and inherited flag |
| WMI filters | Selected-domain stored name, GUID, author, description and raw query definition |
| WMI references | GPC filter reference string, parsed filter ID and domain where recognized |
| Settings structure | User/computer side, extension name, top-level setting node types and counts |
| Collection | Category outcomes plus separate per-GPO/source outcomes, timestamps, counts, durations and errors |

Settings structure deliberately omits individual setting values, arbitrary preference values, scripts and raw XML. Node counts describe report structure rather than distinct configured policy settings. XML is read in memory with DTD/external entity resolution disabled, checked against the requested GPO GUID, and reduced to the documented columns. Full policy-value inventory is outside this release.

GPO enumeration uses only the explicit domain. AD and GroupPolicy reads are pinned to the discovered DC serving that domain. Link containers include the selected domain, its OUs and all forest sites; only references to that domain's GPOs are retained. Other domains' OU/domain links, including links to selected-domain GPOs, are not searched. Site rows can therefore include containers with zero selected-domain links. Link order includes other-domain entries in the source order before filtering, so retained order values can have gaps. Enforced and disabled bits are stored separately; their combination is not an applicability conclusion. No client inheritance/resultant-set-of-policy computation is performed.

WMI filters are stored configuration; queries are not executed. References to external-domain filters are retained but not dereferenced. Unrecognized reference formats remain raw with null parsed IDs. GPO versions are not compared across DCs. Permission levels can include GpoApply, GpoRead, editing levels or custom levels; there is no nested-group expansion, raw ACE evaluation or effective-access conclusion.

## Collection behavior

One background worker has a configurable overall budget (default 300 seconds, range 10–3600), including startup/discovery and all domain reads. It streams completed categories. A timeout retains completed categories and marks missing ones TimedOut. A category still in progress can have no exported rows after timeout; partial per-object results from that unfinished category are not guaranteed. Before scope discovery succeeds, a failure stops collection rather than generating a report with an invented scope. Worker jobs are removed on completion or error.

Per-GPO permission/XML failures retain other completed GPO records and mark the category Partial. Link container sources are independent; a denied site read retains collected domain/OU data. GPO enumeration failure marks dependent version/permission/settings categories NotAttempted while independent AD reads continue. Successful zero-row categories are valid empty results. Object collection being Succeeded means its outcome ledger was captured; inspect each row for actual source/query success. A successful read cannot establish that ACL-filtered objects were visible.

## Requirements and output

Live collection targets Windows PowerShell 5.1 on Windows with RSAT ActiveDirectory and GroupPolicy installed. Use a current Windows identity authorized to read the selected domain, GPO permissions, GPO reports/SYSVOL and forest site configuration. This command has no alternate Credential parameter because GroupPolicy cmdlets use the running identity. No WinRM endpoint is used for the GPO collector; normal AD/GPMC provider connectivity is required. Installing/configuring RSAT, connectivity or delegation is outside the command.

The default parent is C:\Temp\Reports. Each invocation creates its own PSInsightInventory_GroupPolicy_timestamp_run folder, containing Reports/Group-Policy.html, Group-Policy.json, CSV/*.csv and Logs/GroupPolicy_timestamp.jsonl. Previous runs are preserved. CSV exports neutralize formula-leading text; JSON preserves normalized values. No credentials or raw report XML are written.

The included offline example is `Examples/GroupPolicySampleOutput/Reports/Group-Policy.html`. Its three GPOs, three links, one WMI filter and synthetic failed settings query are fictional. No AD/GPO changes, backup, cleanup, gpupdate, endpoint probe or email occur.

Validation details and remaining native Windows/live environment/browser review limits are recorded in VALIDATION.md.

## Microsoft provider references

- https://learn.microsoft.com/en-us/powershell/module/grouppolicy/get-gpo
- https://learn.microsoft.com/en-us/powershell/module/grouppolicy/get-gppermission
- https://learn.microsoft.com/en-us/powershell/module/grouppolicy/get-gporeport
- https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpol/08090b22-bc16-49f4-8e10-f27a8fb16d18
