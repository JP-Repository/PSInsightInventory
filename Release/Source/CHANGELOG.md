# Version 1.0.0 — 30 October 2026

- Prepared the existing ten-inventory module for its first public release without adding collectors or changing collection scope.
- Reconciled module, catalog, result, snapshot, help, and validation version references at 1.0.0.
- Added public-release installation, prerequisite, command, demo, output, permission, limitation, and troubleshooting documentation.
- Added an allowlisted release builder and ignore rules that keep tests, examples, generated reports/logs, local credentials, and publishing artifacts out of the module package.
- Replaced organization-like documentation examples with reserved `example.test` names.
- Added PowerShell Gallery release metadata and HTML Help & About links for the author, repository, support, and documentation.
- Retained Windows PowerShell 5.1 targeting, MIT licensing, read-only behavior, JP branding, console banner/progress, and `-Quiet`.

# Version 0.12.0 — 30 October 2026

- Added a shared module-name/version/author/MIT banner to existing inventory commands.
- Added elapsed-time activity, real query-outcome denominators where available, received-row counts, worker activity and periodic text heartbeats.
- Added final collection summaries, explicit sample labeling and Quiet on all existing inventory commands.
- Progress stays on host/progress streams; returned objects, exports and existing inventory scope are preserved.
- Added a packaged MIT license and focused display/stream-isolation tests. No inventory commands or repository/contact placeholders were added.

# Version 0.11.0 — 30 October 2026

- Added Invoke-ADUserInventory, completing the agreed core inventory scope with ten catalog entries.
- Added user profiles, reported account flags, approximate logon timestamps, reported memberOf links and separate primary-group SID references.
- Added department/company/location/enabled-status summaries and matching-user filters in the ten-section JP report.
- Added sample fixtures, JSON/CSV/log exports, focused user tests and regression validation.
- Follow-up scope is user-directed improvements to existing inventories, without adding collectors unless newly requested.

# Version 0.10.0 — 30 October 2026

- Added Invoke-ADGroupInventory and a ninth catalog entry.
- Added group properties, direct member-attribute links, local nested/parent relationships and member-type resolution evidence.
- Added ranged LDAP retrieval, cached local lookups, external-reference exclusions, streaming per-group results and unknown counts on failure/timeout.
- Added seven-section JP report with bounded detail previews, paginated relationship views, fixtures and tests.
- Direct counts exclude primary-group membership; no recursive/effective-access assessment or remediation occurs.

# Version 0.9.0 — 30 October 2026

- Added Invoke-ADComputerInventory and an eighth catalog entry.
- Added directory computer properties, SPNs, reported delegation attributes and approximate replicated logon timestamps.
- Added OS/version breakdowns and exact combined filters for family, OS, release, version/build, enabled state, role and location.
- Added seven-section JP report, related computer details, sample fixtures and tests.
- No endpoint collection, patch-level assertion, stale-device assessment or remediation is included.

# Version 0.8.0 — 30 October 2026

- Expanded DNS Inventory to 17 sections with zone NS records and stored NS addresses.
- Added Primary/Secondary/Stub NS reads and exact A/AAAA reads from eligible hosted Primary/Secondary zones without resolver probes.
- Added query outcomes, external target exclusions, reused node reads, partial coverage and source-zone relationships.
- Refreshed fixtures, sample reports and DNS tests; public commands and inventory catalog entry count remain unchanged.

# Version 0.7.0 — 30 October 2026

- Added Invoke-ADOrganizationalUnitInventory and a seventh catalog entry.
- Added domain-scoped OU properties, hierarchy, one-scan direct/descendant counts, direct GPO references and explicit/inherited delegation ACEs.
- Added an eight-section JP report with expandable hierarchy and related OU records.
- Added separate GPO/DACL inheritance fields, null count fallback on failed scans, partial outcomes, fixtures and tests.

# Version 0.6.0 — 29 October 2026

- Added Invoke-ADGroupPolicyInventory and a sixth catalog entry.
- Added pinned domain GPO reads, domain/OU/site link observations, reported permissions, WMI definitions/references, versions and settings structure.
- Added GPO relationships, category/object collection ledgers, retained partial outcomes, offline fixtures and an 11-section JP report.
- Added safe XML parsing, explicit identity/scope guards, timeout cleanup and Group Policy regression tests.
- Settings export contains extension/node summaries; raw XML and arbitrary configured values are omitted.

# Version 0.5.0 — 29 October 2026

- Added Invoke-ADDnsInventory and a fifth inventory catalog entry.
- Added domain-scoped DNS configuration collectors with bounded workers, per-zone outcomes and retained partial results.
- Added the 15-section JP report, JSON/CSV/log exports, offline fixtures, sample report and tests.
- Distinguished absent DNS role, access failure, unsupported commands, declared zone exclusions and successful empty queries.
- Made shared static fallback scope metadata applicable to domain-scoped reports.

# Changelog

## 0.4.0

- Added Invoke-ADTrustInventory for local-forest trusted-domain observations.
- Added relative direction descriptions, separate reported SID-filtering settings, protocol/relationship flags and per-domain coverage.
- Added a safe property whitelist, domain scope guard, partner summaries and trust demo report.
- Preserved DC, Sites & Services, Forest & Domain inventories and JP branding.


## 0.3.0

- Added Invoke-ADForestInventory with forest/member-domain metadata and independent policy reads.
- Added functional levels, hierarchy, FSMO references, configured suffixes, partition/hosted-context inventory, containers and directory-server references.
- Preserved known domain rows through collection failures and added dynamic query coverage and a forest demo.
- Preserved the existing DC and Sites & Services commands and JP branding.


## 0.2.0

- Added Invoke-ADSitesAndServicesInventory with forest-wide Configuration-partition scope.
- Added sites, subnets, link/bridge memberships, directory servers, site settings, transports and stored UTC schedules.
- Added partial-query coverage, bounded collection, raw schedule preservation and object detail views.
- Preserved the existing DC inventory and JP branding.


## 0.1.0

- Packaged the existing standalone DC inventory engine as PSInsightInventory.
- Added Invoke-ADInfrastructureInventory and Get-PSInsightInventory, with command help and examples.
- Reused the JP monogram styling from PSInsightExpl 0.6.0 in the offline report.
- Preserved the 17-section layout, domain scope, read-only collectors, CSV/JSON exports, logging and coverage semantics.
- Added module import/export, repeated-run, help, demo-alias and branding checks.
