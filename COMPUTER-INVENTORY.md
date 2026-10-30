# AD Computer Inventory

`Invoke-ADComputerInventory` creates a read-only inventory of computer objects in one explicit domain, with OS breakdowns and filters in the JP report layout. It does not connect to each computer.

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Get-PSInsightInventory
Get-Help Invoke-ADComputerInventory -Examples
Invoke-ADComputerInventory -Demo -Open
Invoke-ADComputerInventory -Domain ad.example.test -Open
Invoke-ADComputerInventory -Domain example.test -TimeoutSeconds 900 -OutputPath C:\Temp\Reports -Open
```

## OS segregation and navigation

The overview shows counts for observed computers, OS/version groups, directory locations and collection gaps. Click an OS/version group to open its exact matching computer list. The table supports combined filters for OS family, reported OS name, server release, reported version, parsed build, enabled state, reported DC role and directory location, along with text search. Reset clears both search and filters. Filtered CSV uses the matching records; full JSON exports the complete normalized snapshot.

Windows Server, Windows client, other/unclassified and unknown families stay separate. Server release labels recognize reported Windows Server names from 2000 through 2025, including 2003/2008/2012 R2. Raw OS names are preserved. Build values are parsed only from recognized version formats such as `10.0 (20348)` or `10.0.20348.100`; unrecognized formats retain the raw version with null build. The module does not infer Windows 10 versus Windows 11 from a shared version prefix or infer server releases from build numbers.

OS group keys combine family, raw OS name, server release, raw version and parsed build. Their counts reconcile to returned computer rows. Missing/unrecognized values remain visible. These values come from AD and may be absent or outdated. They do not establish actual installed OS, installed KBs, exact current patch level or support status.

The seven navigation sections are overview, computers, OS breakdown, directory locations, reported SPNs, delegation attributes and collection coverage. Select a computer to see its properties, SPNs and delegation attributes. OS and location detail pages open their matching computer lists with pagination rather than rendering an unbounded related table.

## Collected fields

| Dataset | Captured inventory |
|---|---|
| Computers | Name/GUID/DNS hostname/domain, reported OS/version/service pack, derived family/release/build, enabled state, role indicator, parent DN, DN, managedBy reference, timestamps and raw UAC/primary group ID |
| OS breakdown | Exact reported OS/version grouping and observed count |
| Directory locations | Immediate parent DN and observed computer count |
| SPNs | One reported servicePrincipalName value per row, related by computer GUID |
| Delegation | TrustedForDelegation, TrustedToAuthForDelegation, AccountNotDelegated, allowed target SPNs and RBCD descriptor presence |
| Collection | One computer enumeration outcome with status, count, method, timestamp, duration and error |

Locations include OU paths and CN containers; there is no assumption all computers are in OUs. DC role is a directory indicator using returned userAccountControl and primaryGroupID, including RODC group indication, rather than a live DC test. It is independent of the reported OS family. Missing role inputs can remain Unknown.

Last logon timestamp is converted from lastLogonTimestamp FILETIME to UTC. It is a replicated, approximate attribute, not exact last logon, last user sign-in, current user or proof of device inactivity. Zero/missing values remain null. Password-last-set and creation/modification values are reported directory timestamps. No stale-device threshold or cleanup recommendation is applied.

Delegation rows report configuration, not effective permissions or security findings. An empty allowed-target list retains a row with null target so flags remain visible. RBCD presence is true when a descriptor is returned; null means not returned/unknown, not a definitive absent configuration. The binary descriptor, its ACEs and secret attributes are not exported. No group membership or effective-access calculation occurs.

## Collection and outputs

Live mode targets Windows PowerShell 5.1 on Windows with RSAT ActiveDirectory and authorized ADWS reads. Uses the current Windows identity; there is no alternate Credential parameter. Discovery selects and pins one DC serving the exact DNS domain. The Get-ADComputer subtree search is based on that domain naming context; child domains are not enumerated. No endpoint WinRM, CIM, WMI, registry, service, ping or port probe is made.

One background worker has a default overall budget of 600 seconds (10–3600 configurable), including discovery and the bulk query. The computer query retains only explicit output fields. Other datasets are derived from the same returned computer records; they are not independent live queries. If enumeration fails after partial output, all accumulated computer records are discarded to avoid misleading totals. Failure or timeout marks coverage unavailable. A successful query returning no records is valid empty inventory. Discovery failure before scope is established stops collection. Jobs are removed after completion/error. Successful reads cannot prove ACL-filtered visibility.

Each run creates a unique folder under C:\Temp\Reports or OutputPath, containing Reports/Computers.html, Computers.json, CSV/*.csv and Logs/*.jsonl. Reports embed branding, data and scripts for offline use, with a static fallback. Previous runs remain intact. CSV neutralizes formula-leading text; JSON preserves normalized values.

The sample in `Examples/ComputerSampleOutput/Reports/Computers.html` has ten fictional objects: Server 2016/2019/2022/2025 and 2012 R2, Windows clients, another OS, unknown OS, a disabled object, a DC indicator and repeated Windows 11 grouping. Sample mode makes no infrastructure requests or email. No AD changes, remediation or recommendations occur. See VALIDATION.md for test evidence and remaining limitations.

Provider reference: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adcomputer
