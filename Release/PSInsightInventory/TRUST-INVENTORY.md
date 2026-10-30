# Trust Inventory — 0.4.0

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Invoke-ADTrustInventory -Demo -Open
Invoke-ADTrustInventory -Domain ad.example.test -Open
```

## Collection scope

The connection domain selects the local forest. The command verifies forest membership, then reads Get-ADTrust results through a pinned DC in each returned local domain. A TDO outside that verified domain's System container fails the scope guard. **Remote trust partners are not contacted.** This is a local observation inventory, not a complete two-sided inventory of every external forest.

Windows with RSAT ActiveDirectory and authorized directory-read access are required for live mode. No WinRM is used. One collection outcome is recorded per local forest domain, including discovery and the TDO read. A successful empty query is zero records; a failed/timed-out query has an unknown count. Completed domain results survive a later worker timeout.

```powershell
Invoke-ADTrustInventory `
    -Domain example.test `
    -Credential (Get-Credential) `
    -TimeoutSeconds 300 `
    -OutputPath C:\Temp\Reports `
    -Open
```

The default overall budget is 180 seconds, including forest discovery and all domains. Cleanup can take additional time. If local forest context cannot be verified, a forest-scoped report is not generated.

## Report sections

| Section | Contents |
|---|---|
| Overview | Observed TDO/partner counts, domains collected, reported selective-authentication values |
| Observed domains | Every returned local forest domain, selected DC, query status and nullable TDO count |
| Trust observations | Partner, local observation domain, direction, reported protocol/relationship flags, transitivity flags, DN and source DC |
| Direction descriptions | Raw direction and a description relative to the observed local domain |
| Trust settings | Separate SID-filtering properties, selective authentication, encryption/delegation values, raw attributes, SID/flat name and timestamps |
| Observed partners | Partner-name grouping with local domains and observed directions; no reciprocal validation |
| Collection | Independent domain outcomes, timestamps, durations, counts and errors |

Every observed TDO remains a separate row. Parent/child reciprocal observations are not collapsed into a claimed verified relationship. Selecting a domain or trust opens related records; selecting a partner shows its collected local observations.

## Interpreting values

- **Inbound:** the partner trusts the observed domain, according to the local configuration.
- **Outbound:** the observed domain trusts the partner, according to the local configuration.
- **Bidirectional:** both direction flags are configured on the observed object; this does not verify agreement at both ends.
- **Disabled (0):** no direction flags are set on that object. Unknown values remain explicitly unknown.

The reported protocol type, such as Uplevel or MIT, is kept distinct from forest/within-forest relationship flags. The non-transitive raw bit is retained rather than inventing a single universal transitivity result.

**SIDFilteringForestAware and SIDFilteringQuarantined are shown separately.** Neither alone is labeled as overall SID filtering enabled/disabled. The raw quarantined-domain and treat-as-external bits are also retained. Reported selective authentication does not establish effective Allowed-to-Authenticate permissions. Encryption/delegation flags do not establish actual negotiated ticket algorithms or end-to-end authentication behavior.

Nulls mean not returned/not available; false remains a reported false value. Known flag bits are decoded alongside original attributes. No health score, security grade, remediation or effective-access claim is made.

## Data and outputs

An explicit property whitelist is requested and retained. No Properties * request or trust-authentication secret-attribute read is used. Unexpected fields in returned objects are not serialized. Domain SIDs, trust names and configuration properties are inventory data; passwords and trust authentication secrets are not exported.

Each run creates a unique `PSInsightInventory_Trusts_<timestamp>_<RunId>` folder under C:\Temp\Reports, with offline HTML, JSON, six CSV datasets and JSONL logs. The HTML embeds the JP mark and all assets. Static tables remain available without JavaScript. JSON retains safe raw observations; CSV neutralizes formula-leading strings. Browser CSV includes all filtered rows and schema columns across pages; snapshot JSON includes the full captured data.

Demo mode uses fictional fixtures and makes no infrastructure requests. Live Windows PowerShell 5.1 execution, live directory behavior and visual browser/download review remain pending; see VALIDATION.md.

## Microsoft references

- [Get-ADTrust](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adtrust)
- [trustDirection definition](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/5026a939-44ba-47b2-99cf-386a9e674b04)
- [trustAttributes definition](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/e9a2d23c-c31e-4a6f-88a0-6646fdb51a3c)
