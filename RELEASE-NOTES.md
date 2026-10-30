# PSInsightInventory 1.0.0

PSInsightInventory 1.0.0 is the first public release of the existing read-only Active Directory inventory module.

## Included inventories

- Domain controller infrastructure
- Sites & Services
- Forest and domains
- Trusts
- DNS configuration
- Group Policy
- Organizational units
- Computers
- Groups
- Users

No collectors or inventory categories were added for this release. Existing scope, output schemas, failure/unknown semantics, console banner and progress, `-Quiet`, and JP-branded HTML behavior are preserved.

## Release preparation

- Reconciled manifest, catalog, snapshot, result, help, and documentation versions at 1.0.0.
- Added comprehensive prerequisites, installation, command, demo, output, permission, limitation, and troubleshooting documentation.
- Added Help & About links for Jonathan Preetham, the repository, support, and documentation to every HTML report; these links are not printed in the console banner.
- Replaced organization-like examples with reserved `example.test` names and removed generated example logs containing old build paths.
- Added allowlisted GitHub source, GitHub ZIP, and PowerShell Gallery staging plus SHA-256 verification.
- Retained the MIT license and Windows PowerShell 5.1 target.

## Validation boundaries

Offline fixtures and mocked-provider checks validate parsing, module exports, demo generation, report/export behavior, collection contracts, Help & About links, and package contents. They do not validate a live Active Directory environment, WinRM/DNS provider access, native Windows PowerShell 5.1 host behavior, or visual browser behavior. See `VALIDATION.md` for the exact results run for this release.
