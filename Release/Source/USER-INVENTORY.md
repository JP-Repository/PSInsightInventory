# AD User Inventory

`Invoke-ADUserInventory` inventories user objects in one explicit domain, using the existing JP report layout. It is read-only and remains separate from PSInsightExpl assessments.

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Get-PSInsightInventory
Get-Help Invoke-ADUserInventory -Examples
Invoke-ADUserInventory -Demo -Open
Invoke-ADUserInventory -Domain ad.example.test -Open
Invoke-ADUserInventory -Domain example.test -TimeoutSeconds 1200 -OutputPath C:\Temp\Reports -Open
```

## Contents and navigation

Ten navigation sections cover overview, users, reported account flags, reported direct group links, primary group references, departments, companies, directory locations, enabled status and collection coverage.

| Dataset | Inventory captured |
|---|---|
| Users | Name/GUID/SAM name, UPN, email, enabled state, department/title/company, manager DN, parent location/DN, creation/modification/password-last-set/account-expiry/approximate-logon timestamps and observed backlink count |
| Account flags | PasswordNeverExpires, PasswordNotRequired, CannotChangePassword, SmartcardLogonRequired, AccountNotDelegated, TrustedForDelegation and TrustedToAuthForDelegation |
| Group links | memberOf DNs returned by Get-ADUser, related to user GUID |
| Primary group references | User SID, primaryGroupID RID, and derived primary-group SID when the account-domain SID is valid |
| Summaries | Observed counts by exact department, company, immediate parent DN and enabled value |
| Collection | One domain-user enumeration outcome with status, returned count, timestamp, duration and errors |

Click a summary to open matching users. Filters for department, company, location and enabled status can be combined with text search. Missing values, empty strings and false enabled values remain distinct. Summary counts reconcile to returned user objects rather than a claimed complete population. Select a user for properties, account flags, group links and primary-group reference. Related previews are bounded to 25 rows; Open matching records provides pagination, search and filtered CSV export. Reset clears active filters. Full JSON exports the complete normalized snapshot.

## Semantics and scope

The domain is explicit; child domains are not enumerated. All live reads use one discovered DC serving the supplied domain. Locations are immediate parent DNs and can include CN containers rather than OUs. Manager and group references are retained as DNs without querying their targets, including external/child-domain references. Profile values are reported configuration, not proof of employment status, business ownership or effective permissions.

Last logon timestamp comes from replicated lastLogonTimestamp FILETIME and is approximate. It is not exact last sign-in, current activity or an inactivity finding. Zero/missing values remain null. Account expiration is the returned AccountExpirationDate; null does not establish a particular cause, and account expiration is not password expiration. Password-last-set is a reported timestamp. Account flags are returned AD properties, some of which the module/provider computes from directory attributes; no policy effectiveness or sign-in availability is asserted.

Direct group links are **memberOf backlinks as returned by Get-ADUser**. The reported count excludes primary-group membership and recursive membership. It is not complete forest-wide membership, token membership or effective access. No independent ranged backlink retrieval or completeness validation is performed by this command. ACL visibility and provider behavior can limit returned attributes. A zero observed backlink count is not proof that an account has no groups.

Primary group is shown separately. For a valid account-domain SID and primaryGroupID, the SID domain prefix is combined with that RID. No group object is queried, no group name is invented, and the derived SID is not a verified effective-membership result. Missing/invalid SID inputs leave the derived SID null.

No password values, hashes, history, managed-password data, secret attributes, group expansion, privilege analysis, stale-account scoring, recommendations, changes, remediation or email are included.

## Collection and requirements

Live mode targets Windows PowerShell 5.1 on Windows with RSAT ActiveDirectory and authorized ADWS reads, using the current Windows identity. There is no alternate Credential parameter and no endpoint, manager or group-target collection. Only explicit profile/flag/reference properties are requested and retained; there is no wildcard property request or raw user-object export.

One bounded background worker has a default overall budget of 600 seconds (10–3600 configurable), including discovery and the bulk query. Summary and relationship datasets are derived from that query, rather than independent live reads. A query failure after partial output discards its accumulated records to avoid misleading totals and marks coverage unavailable. A timeout produces an explicit TimedOut outcome. A successful empty query is a valid empty inventory. Discovery failure before scope is established stops collection. Worker jobs are cleaned up. Successful reads cannot establish ACL-filtered visibility or a transactional point-in-time snapshot.

## Output and sample

Each run creates a unique folder under C:\Temp\Reports or OutputPath, containing Reports/Users.html, Users.json, CSV/*.csv and Logs/*.jsonl. Previous runs remain intact. HTML embeds its branding, data and scripts, with a static fallback. CSV protects formula-leading strings; normalized JSON preserves values.

The sample in `Examples/UserSampleOutput/Reports/Users.html` has five fictional users, including enabled, disabled and unknown status, missing/empty departments, reported group references, separate primary-group SIDs and nullable timestamps. Sample mode does not contact infrastructure or send mail. Native Windows/AD behavior and visual browser review remain pending as documented in VALIDATION.md.

## Microsoft references

- https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
- https://learn.microsoft.com/en-us/powershell/module/activedirectory/about/about_activedirectory_objectmodel
- https://learn.microsoft.com/en-us/windows/win32/ad/security-properties
