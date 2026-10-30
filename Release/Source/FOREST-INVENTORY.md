# Forest & Domain Inventory — 0.3.0

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Invoke-ADForestInventory -Demo -Open
Invoke-ADForestInventory -Domain ad.example.test -Open
```

## Scope

The supplied DNS domain is the connection starting point. The command verifies the forest, obtains the returned forest member-domain list, then reads each domain's metadata and default password policy through a DC selected for that domain. The forest summary and partition-reference query use the initial pinned DC. All queries are directory reads; no WinRM is needed. Windows and RSAT ActiveDirectory are required for live mode. Authorization must cover the directory reads in the included domains.

This is **forest-wide inventory**, unlike the existing domain-scoped DC inventory command. Failed/unreachable member domains remain visible because their identities were returned by forest discovery. Their unavailable fields stay null/Unknown, with collection status shown. A failed policy query does not imply a zero-length password policy or discard domain metadata.

## Contents

| Dataset | Inventory |
|---|---|
| Forest | Root domain, functional level, membership references, forest FSMO owners, application partitions, sites |
| Domains | DNS/NetBIOS names, SID, GUID, DN, functional level, parent/children, source DC and query status |
| Domain hierarchy | Returned parent/child references and forest-root marker |
| Functional levels | Forest and domain values, with their collection status |
| FSMO owners | Two forest roles and three roles per known domain; unavailable owner values remain unknown |
| Configured suffixes | Additional UPN/SPN suffix lists returned by Get-ADForest |
| Partition references | Configuration crossRef objects and replica-reference DNs, flags and enabled values |
| Hosted naming contexts | Naming contexts reported by the observed DCs, not a claim to enumerate all forest-hosted replicas |
| Default containers | Six documented container properties returned by successful domain queries |
| Directory server references | Forest GC and domain replica-directory-server references, labeled with their source property |
| Default password policies | Minimum length, history, complexity, reversible encryption, ages and lockout settings |
| Collection | Independent forest, partition, per-domain metadata and per-domain policy outcomes |

The console has 13 navigation sections including Overview. Select a domain to inspect related FSMO owners, containers, policy and server references.

Configured suffixes are not an account-UPN usage census. Server references do not prove endpoint availability. Default password policies are not user-effective policies; fine-grained password policies are not evaluated. Durations retain PowerShell TimeSpan constant-format strings, such as `42.00:00:00`. No compatibility grade, health score, security recommendation, trust enumeration, password/hash retrieval or infrastructure change is performed.

## Usage and limits

```powershell
Invoke-ADForestInventory `
    -Domain example.test `
    -Credential (Get-Credential) `
    -TimeoutSeconds 300 `
    -OutputPath C:\Temp\Reports `
    -Open
```

Default overall worker budget is 180 seconds, including discovery and all domains. Completed results survive later timeouts; missing outcomes become TimedOut or Failed. Cleanup can add time. If forest identity and membership cannot be established, no report is labeled as a verified forest inventory.

The expected query denominator is **2 + 2 × member-domain count**: forest metadata, partition references, domain metadata per domain, and default policy per domain. The fictional two-domain sample has six outcomes. Domain discovery is needed to pin/verify each domain endpoint; failure produces explicit domain and policy outcomes rather than querying an unverified endpoint.

Each run creates a unique `PSInsightInventory_Forest_<timestamp>_<RunId>` folder under C:\Temp\Reports, or the selected parent. Reports include offline HTML, JSON, twelve CSV datasets and structured JSONL logs. JSON retains raw property bags and original strings; CSV neutralizes formula-leading strings. All datasets keep headers when empty. Import and demo mode do not contact AD.

Search, sorting, pagination, column selection, themes and CSV/JSON exports are available offline. Static tables remain readable without JavaScript. Snapshot JSON includes all data; filtered CSV includes all matching rows and schema columns, regardless of pagination or hidden columns.

## Validation

The included tests cover partial failures, unknown values, query denominators, cross-domain DC pinning, independent policy denial, encoding and cancellation. See VALIDATION.md for actual results and native Windows/live/visual limits.

## Microsoft references

- [Get-ADForest](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adforest)
- [Get-ADDomain](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addomain)
- [Get-ADDefaultDomainPasswordPolicy](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addefaultdomainpasswordpolicy)
