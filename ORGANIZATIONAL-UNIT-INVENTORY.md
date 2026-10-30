# Organizational Unit Inventory

`Invoke-ADOrganizationalUnitInventory` inventories OUs in one explicit domain. It uses the existing JP layout and remains independent of PSInsightExpl.

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Get-PSInsightInventory
Get-Help Invoke-ADOrganizationalUnitInventory -Examples
Invoke-ADOrganizationalUnitInventory -Demo -Open
Invoke-ADOrganizationalUnitInventory -Domain ad.example.test -Open
Invoke-ADOrganizationalUnitInventory -Domain example.test -TimeoutSeconds 900 -OutputPath C:\Temp\Reports -Open
```

## Report and datasets

The eight navigation sections are overview, organizational units, object counts, direct GPO links, inheritance configuration, delegation ACEs, OU collection and category collection. The overview has expandable hierarchy branches; selecting an OU opens its properties, immediate child OUs, counts, GPO links, inheritance flags, reported ACEs and collection outcomes. Related records use OU GUIDs. Duplicate display names are distinguished by DNs and GUIDs.

| Dataset | Captured inventory |
|---|---|
| OUs | Name, GUID, DN, parent DN, canonical path, description, managedBy reference, deletion protection and timestamps |
| Counts | Direct and all-descendant counts for users, computers, groups and OUs, plus count status |
| Direct GPO links | GPO GUID/DN reference, link order, enabled/enforced flags and raw options |
| Inheritance | GPO inheritance blocking, raw GPO options and separate DACL inheritance protection |
| Delegations | Reported DACL ACEs with trustee SID, allow/deny, AD rights, object/inherited-object GUIDs and inheritance flags |
| Collection | Per-OU GPO-link/DACL outcomes and separate category outcomes with counts, timestamps, duration and errors |

This is configuration inventory. No severity, score, recommendations, effective-permission calculation or cleanup inference is made.

## Scope and counts

The supplied domain is explicit: child domains are not enumerated. Discovery pins collection to one DC serving that domain. The report inventories OU objects rather than general CN containers or domain-root configuration. Counts can include selected object types stored inside CN containers underneath an OU, because those objects are descendants of that OU.

A single domain-wide Get-ADObject scan retrieves the default minimal identity/class fields and computes counts in memory. It does not export individual user, computer or group identities. Direct means the object's immediate parent is the OU; descendant means anywhere beneath it, at all depths. The OU itself is excluded. Child OUs count as OU objects. Computers are classified separately from users. Contacts, service-account classes, inetOrgPerson and other classes are excluded; group counts count directory group objects rather than their members.

Descendant totals overlap between ancestor OUs. Do not add them across all OU rows to infer a domain total. Counts cover only returned objects visible to the running identity. If a scan fails after partial output, its accumulated counts are discarded: rows retain OU identity and null counts with Unavailable status. A successful empty OU has zero counts. A timed-out count category also produces unknown counts for available OU identities. No count scan is needed when OU enumeration successfully returns no OUs.

## GPO links and delegation

Only links directly stored on each returned OU are captured. Cross-domain GPO references are retained as GUID/DN references but their targets are not queried. GPO names, inherited links, actual application and resultant policy are outside this report. Link order reflects the complete stored list; enabled and enforced bits are separate observations. Validate native ordering against GPMC in your environment.

GPO inheritance blocking and DACL inheritance protection are different settings and have separate fields. Missing attributes remain null rather than being guessed. ProtectedFromAccidentalDeletion is the returned AD property; it is not an effective-delete test.

DACL reads use LDAP pinned to the same DC, request only DACL security information, and collect explicit and inherited access rules as SIDs. There is no owner/SACL export, trustee/schema name resolution, nested group expansion or effective-access conclusion. ACE counts are rows rather than unique delegation relationships. GUIDs and inheritance flags preserve the reported scope of each rule. A denied DACL read keeps other OUs' ACEs and leaves that OU's DACL protection flag null. It also leaves the independently collected hierarchy/counts available.

## Collection and output

Live mode targets Windows PowerShell 5.1 on Windows with RSAT ActiveDirectory, ADWS access and LDAP DACL read access to the pinned DC. Run under a current Windows identity authorized for these reads. This command has no alternate Credential parameter. It uses no WinRM endpoint and does not enable services, grant permissions or change connectivity.

One background worker has an overall budget of 600 seconds by default, including startup, discovery and all reads (10–3600 seconds configurable). Completed categories survive timeout; missing categories get TimedOut outcomes. Rows from a category still in progress are not guaranteed after timeout. Discovery failure before domain scope is established stops collection. Jobs are removed on completion or error.

Each run creates a unique folder under C:\Temp\Reports (or OutputPath), containing Reports/Organizational-Units.html, a JSON snapshot, CSV/*.csv and Logs/*.jsonl. Previous runs remain intact. CSV neutralizes formula-leading text; normalized JSON preserves original values. The report embeds its data, branding and scripts for offline use, with a static fallback when scripting is disabled.

The sample at `Examples/OrganizationalUnitSampleOutput/Reports/Organizational-Units.html` is fictional: three OUs, a parent-child branch, an empty OU and a synthetic denied DACL read. Sample mode does not contact infrastructure. No AD, GPO or ACL changes, remediation or email occur. See VALIDATION.md for actual checks and remaining Windows/live/browser limitations.

## Microsoft provider references

- https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adorganizationalunit
- https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adobject
- https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.securitymasks
- https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.directoryobjectsecurity.getaccessrules
