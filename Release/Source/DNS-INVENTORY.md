# DNS Configuration Inventory

`Invoke-ADDnsInventory` inventories configuration on selected domain controllers in one explicitly supplied domain. It is independent of PSInsightExpl and retains the authorized JP branding.

```powershell
Import-Module .\PSInsightInventory\PSInsightInventory.psd1 -Force
Invoke-ADDnsInventory -Demo -Open
Invoke-ADDnsInventory -Domain ad.example.test -Open
Invoke-ADDnsInventory -Domain ad.example.test -ComputerName dc01.example.test -Open
```

## Included data

The 17-section report includes an overview plus selected DCs, DNS role/service state, client adapter resolver order, server forwarders, recursion settings, server scavenging settings, root hints, zone observations, conditional forwarders, zone aging, delegations, zone scopes, zone NS records, stored NS addresses, per-zone collection and category collection. Each dataset has CSV output; the complete snapshot is also exported as JSON. HTML embeds its branding, data and JavaScript for offline use, with search, sorting, pagination, column controls, theme switching and related server/zone details.

The sample uses fictional addresses and three DCs: two DNS servers and one without the DNS role. One server has a synthetic denied delegation query. Other successful rows remain visible. Open `Examples/DnsSampleOutput/Reports/Dns-Configuration.html` to inspect the report without contacting infrastructure.

## Zone NS and stored address inventory (v0.8)

Zone NS records are read with Get-DnsServerResourceRecord -RRType NS from hosted Primary, Secondary and Stub zones, including apex and child owners. Forwarder/other types receive explicit NotAttempted entries. Reads use the default zone scope and virtualization instance. The dataset preserves server, source zone, owner, advertised NS name, TTL and nullable timestamp. An NS name is advertised configuration, not proof of a functioning or authoritative endpoint. NS records are separate from client DNS resolvers, server forwarders and root hints.

Stored NS addresses are a separate dataset. For each observed target, collection selects the longest matching hosted Primary/Secondary address zone on that DC and queries only its exact A and AAAA node, using -Name and -Node. Cached reads are reused for repeated targets; exported rows retain the source NS-zone relationship. Apex address targets use the @ node. No full A/AAAA zone dump occurs. Targets without an eligible hosted address zone are marked NotAttempted rather than resolved externally. Stub zones are eligible NS sources but are not selected as address zones.

Address rows identify the source NS zone, name server, address zone, owner, record type, address and TTL. They are stored observations, not DNS responses, verified glue, a complete address set or evidence of resolution/reachability. CNAME chains are not followed. Successful zero-row address queries stay empty. Provider errors, including no-record errors, remain Failed outcomes; the collector does not infer that an address is absent. Successful A rows survive an AAAA failure. Failed NS inputs make address coverage Partial even when other stored addresses were read successfully.

Every selected DC has 15 category outcomes (including identity discovery), with the category ledger excluded from that denominator. Per-zone/query outcomes appear separately. Existing timeout and partial-result behavior applies to the new categories. The overall per-DC default remains 180 seconds; larger zones may need a higher TargetTimeoutSeconds value. This release reads NS records but does not perform a full resource-record dump, resolver probe, assessment, cleanup or remediation.

Provider reference: https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverresourcerecord

## Scope and interpretation

DC discovery uses RSAT ActiveDirectory against the explicit DNS domain. Optional ComputerName values are exact short names or FQDNs selected from that discovery. Child domains and non-DC DNS servers are not enumerated. Server observations retain their target identity; repeated zone names are not merged into a claim of uniform configuration.

Per-zone aging, delegation and scope queries select **Primary zones in the default virtualization instance**. Non-Primary zones have NotAttempted ledger rows. Delegations are read in the default zone scope. No full DNS resource-record dump or custom virtualization-instance enumeration is included. Root hints expose configured name servers and returned addresses. Missing provider properties remain null.

A category is Partial when any selected zone operation fails or is unsupported; successful rows remain exported. Per-zone collection being Succeeded means its ledger was captured: inspect each ledger row to assess its queries. Successful zero-row queries are valid empty results. An absent DNS service produces NotApplicable configuration categories; access denial, transport failure and missing modules produce failures, never inferred absence. Overview counts describe observations and completeness, not operational health.

## Requirements and outputs

Live mode requires Windows, RSAT ActiveDirectory on the collecting host, authorized AD reads and Kerberos WinRM access to selected DCs. The DNS Server PowerShell module must be available on each DNS target, with sufficient rights for its read commands and local CIM queries. Existing WinRM HTTPS endpoints can be selected with UseSSL and Port; normal certificate validation remains enabled. No endpoint or service is enabled by the module.

Defaults: throttle 4, per-DC budget 180 seconds, discovery budget 60 seconds and connection-open budget 15 seconds. Target timeout includes worker startup and all queries. Completed categories survive timeout; missing categories receive explicit TimedOut outcomes. Local output defaults to `C:\Temp\Reports`, with a unique run folder containing Reports/HTML, JSON, CSV and Logs/JSONL. Use OutputPath to select another parent folder. No credentials are written to output.

All operations are inventory reads. No resolver probe, health assertion, DNS update, scavenging run, cache flush, remediation or email is performed. Native Windows PowerShell 5.1, live DNS permissions/provider behavior and browser visual/download review require validation in your environment; offline results are recorded in VALIDATION.md.

## Provider references

Read commands follow Microsoft DNS Server PowerShell documentation:

- https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverzoneaging
- https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverzonedelegation
- https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverzonescope
- https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverroothint
- https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverscavenging
- https://learn.microsoft.com/en-us/powershell/module/dnsserver/get-dnsserverrecursion
