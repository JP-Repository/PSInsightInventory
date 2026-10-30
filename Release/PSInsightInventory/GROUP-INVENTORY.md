# AD Group Inventory

`Invoke-ADGroupInventory` inventories group properties and direct membership links in one explicit domain. It uses the JP report layout, CSV/JSON exports and structured logs, independently of PSInsightExpl.

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Get-PSInsightInventory
Get-Help Invoke-ADGroupInventory -Examples
Invoke-ADGroupInventory -Demo -Open
Invoke-ADGroupInventory -Domain ad.example.test -Open
Invoke-ADGroupInventory -Domain example.test -TimeoutSeconds 1200 -OutputPath C:\Temp\Reports -Open
```

## What the report captures

Seven navigation sections cover overview, groups, direct linked members, nested group links, parent group links, member resolution and collection coverage. Select a group to see its properties and related membership records. Detail previews show up to 25 rows; Open matching records uses a relationship filter with pagination, search and filtered CSV export. Reset clears that relationship filter. Full JSON contains the complete normalized snapshot.

| Dataset | Inventory fields |
|---|---|
| Groups | Name, GUID, SAM account name, SID, scope, security/distribution category, description, managedBy reference, location DN, DN, timestamps, direct linked-member count and membership status |
| Direct linked members | Source group GUID/name, member DN, resolved name/GUID/SID/class when returned, resolution status |
| Nested group links | Parent/child IDs, names and child DN for selected-domain catalog groups |
| Parent group links | Reverse relationships derived from collected local nested links |
| Member resolution | Lookup/exclusion outcome and message per source-group/member reference |
| Collection | Metadata and per-group member-list status, count, timestamp, duration and errors |

Scope/category/location and member types remain searchable table values. managedBy is a directory reference, not proof of business ownership or delegated rights. This is inventory without privilege scores, excessive-access findings, cleanup recommendations or remediation.

## Membership semantics and scope

Direct linked members are the group's **member attribute references**. They exclude membership represented only by primaryGroupID. Counts therefore are not complete effective group membership, recursive user totals, access-token contents or unique people. Contacts and other object classes can appear as linked members when returned. A local foreignSecurityPrincipal is shown as that local object and SID; the external account is not resolved.

No recursive expansion occurs. Nested and parent relationships are derived only between groups in the selected-domain metadata catalog, using successful member-list reads. This does not establish every parent in the forest or other domains. Cycles and self-links are retained as relationships rather than traversed. If another group's list fails, parent coverage can be incomplete even when the selected group's own list succeeded.

The domain is explicit and all live collection is pinned to one discovered DC serving it. Metadata is limited to that domain naming context. Member DNs from other/child domains or other naming contexts are retained with NotAttempted resolution and unknown type. They are not dereferenced. Local group references use the metadata catalog; other local references use Get-ADObject with only objectSid requested in addition to default identity/class fields. Repeated lookups are cached. A failed member lookup preserves the raw DN and valid linked-member count but leaves its type/identity unknown and marks resolution coverage incomplete.

## Large groups and collection failures

Direct member references are read using LDAP range retrieval in server-bounded blocks (typically 1,500 values), continuing until the server's terminal range. Requests use a wildcard upper bound, and an accompanying empty un-ranged member property is ignored when the server supplies a ranged property. Invalid, missing, non-progressing or duplicate ranges fail that group's collection rather than silently accepting a truncated list. Base searches disable referral chasing. This avoids relying on an initial member attribute block or Get-ADGroupMember's object expansion. It also preserves unresolved/foreign references without external requests.

A failed/incomplete list discards that group's accumulated records and leaves its direct count null. Successful empty lists have zero counts. Successful reads cannot prove that ACL-filtered attributes or objects were visible. Groups are processed independently and completed envelopes stream back to the collecting process. A failed metadata scan discards its partial catalog and stops dependent reads.

One background worker has a default overall budget of 600 seconds (10–3600 configurable), including discovery, metadata, per-group member ranges and member-type lookups. Completed group results survive timeout; missing per-group outcomes become TimedOut, with unknown counts. A group still being resolved when time expires has no guaranteed partial export. Large directories may need a larger TimeoutSeconds value. This release does not claim live performance at any specific directory scale. Worker jobs are removed after completion/error.

## Requirements and outputs

Live mode targets Windows PowerShell 5.1 on Windows with RSAT ActiveDirectory, authorized ADWS reads and LDAP read access to group member attributes. It uses the current Windows identity and has no alternate Credential parameter. It does not contact endpoints, trust partners or external-domain DCs, or enable services/connectivity.

Each invocation creates a unique run folder under C:\Temp\Reports or OutputPath, containing Reports/Groups.html, Groups.json, CSV/*.csv and Logs/*.jsonl. Previous runs are preserved. Assets and data are embedded for offline use, with a static fallback. CSV neutralizes formula-leading text; JSON preserves normalized values. Explicit retained fields exclude unexpected property bags and credentials.

The fictional sample at `Examples/GroupSampleOutput/Reports/Groups.html` includes four groups, five links, one nested relationship, a user, computer, local FSP, external reference, empty distribution group and denied membership query. No infrastructure or email is contacted in sample mode. No group changes, membership changes, assessment or remediation occur.

Native Windows PowerShell 5.1, LDAP range/provider behavior and live permissions require validation in your environment. Visual desktop/mobile and real browser download review remain pending. See VALIDATION.md for actual offline checks.

## Microsoft references

- https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroup
- https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adobject
- https://learn.microsoft.com/en-us/windows/win32/ad/enumerating-groups-that-contain-many-members
- https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adcap/3501d61e-43c7-499b-a596-6c261124e008
