# Sites & Services Inventory — 0.2.0

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Invoke-ADSitesAndServicesInventory -Demo -Open
Invoke-ADSitesAndServicesInventory -Domain ad.example.test -Open
```

`-SampleData` and `-Demo` are equivalent. Sample mode uses deterministic fictional fixtures and does not query infrastructure.

## Scope and collection

`Domain` identifies the connection domain, not a domain-only scope. The command resolves a DC, verifies the supplied domain, then pins all configuration queries to that DC. The report prominently records the forest, connection domain, source DC and Configuration naming context. It uses RSAT ActiveDirectory on Windows; authorized directory read access is required. No WinRM or local-administrator provider reads are used by this command.

Eight independent Get-ADObject queries read sites, subnets, site links, site link bridges, servers, NTDS Site Settings, transports and NTDS Settings objects beneath CN=Sites in the Configuration partition. Each query has its own outcome. A successful empty result is different from failure. Successful directory reads cannot prove visibility of objects or attributes hidden by ACLs.

```powershell
Invoke-ADSitesAndServicesInventory `
    -Domain example.test `
    -Credential (Get-Credential) `
    -TimeoutSeconds 180 `
    -OutputPath C:\Temp\Reports `
    -Open
```

Default output parent is C:\Temp\Reports. A unique PSInsightInventory_Sites timestamp/RunId folder contains Reports and Logs, with an offline HTML console, JSON snapshot, eleven CSV datasets and JSONL collection logs. The final object returns exact paths. No retention deletion or automatic email occurs.

The overall worker budget defaults to 120 seconds. Completed streamed query results survive a later timeout. Missing outcomes become TimedOut or Failed. Cancellation and cleanup can add time after a budget expires. If the forest context cannot be verified, report generation stops rather than inventing a scope.

## Report sections

| Section | Contents |
|---|---|
| Overview | Forest scope, counts, zero-DC-object sites and absent subnet assignment values |
| Sites | Descriptions, locations, associated object counts, ISTG, options, timestamps and DN |
| Subnets | All returned objects, assigned site, raw site DN, absent values and unresolved references |
| Site links | Sites, transport, cost, interval, options, notification/two-way/compression flags and schedule summary |
| Site link membership | One row per link/site reference, with DNs and resolution state |
| Site link bridges | Transport and member links |
| Bridge membership | One row per bridge/link reference |
| Directory servers | Host name, site, NTDS-object observation, configured bridgehead transport list and server reference |
| Site configuration | NTDS Site Settings, ISTG DN, raw options, preferred-GC-site reference and stored schedule |
| Transports | Raw options, ignore-schedule flag, bridge-all-site-links setting and address attribute |
| Stored schedules | Parse status, permitted-hour total, original base64 bytes and 168 hourly UTC masks |
| Collection | Eight raw-query outcomes with counts, methods, timestamps, duration and error context |

Sites remain visible when they contain zero returned DC/server objects. The DC-object count means NTDS Settings objects associated with server objects, not a live or online DC census. Use the existing DC inventory command for server inventory.

Counts whose prerequisite query failed remain null/Unknown. A failure never becomes a zero-object assertion. A subnet with no returned siteObject value is labeled `Unassigned / no value returned`; unresolved references retain their original DN. These are configuration observations, not health findings or remediation instructions.

The bridgehead transport list is configuration inventory, not confirmation of current replication traffic. Site options are retained as raw numbers. Known link and transport bits are decoded alongside their original values; missing option values remain unknown rather than assuming zero.

## Schedules

The report preserves every returned schedule as base64. Supported SCHEDULE blobs are validated before decoding: header size, schedule count/type, offset, 168 hourly entries and reserved bits. Unsupported/truncated values retain their raw bytes with a parse message.

The weekly grid is labeled **UTC**, starting Sunday 00:00. Each cell displays how many of the four stored quarter-hour flags are permitted, from 0/4 to 4/4. It does not relabel individual quarter flags as local wall-clock times. The permitted-hour total is the count of enabled quarter flags divided by four. Missing schedules remain `Not set or not returned`; no availability is inferred.

This is the **stored** schedule, not effective replication behavior. Transport ignore-schedule settings and combined site-link paths can affect effective schedules. No local-time conversion, live replication checks or topology simulation is performed.

## Interaction and exports

Search, sort, pagination, column selection, theme switching and object detail pages work offline. Select a site to inspect related servers, subnets, site links and site settings. Select a link to see its site membership and stored UTC schedule. Raw DN references and unparsed schedule bytes remain available in JSON/CSV.

Filtered CSV exports include all matching rows across pages and all schema columns. Snapshot JSON includes normalized datasets, raw returned property bags and collection coverage. Spreadsheet-facing CSV neutralizes formula-leading strings; JSON retains originals. The static no-JavaScript fallback includes all eleven datasets.

## Validation

See VALIDATION.md. Offline tests and mocked provider checks passed under PowerShell 7.4.13 on Linux. Native Windows PowerShell 5.1/live AD execution and visual browser review remain pending.

## Microsoft references

- [Site Link Object and options](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/f148e965-e4d7-413a-acfc-0e9a9e591708)
- [SCHEDULE_HEADER and UTC schedule data](https://learn.microsoft.com/en-us/windows/win32/api/schedule/ns-schedule-schedule_header)
- [IP Transport Container options](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/66db6a63-52d2-4980-b87b-7b2d598dba81)
- [NTDS Site Settings class](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adls/f96fdd59-f2cd-41ca-91b3-de16fdd4195c)
- [Bridgehead transport list](https://learn.microsoft.com/en-us/windows/win32/adschema/a-bridgeheadtransportlist)
