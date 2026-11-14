# PSInsightInventory 2.0.0

PSInsightInventory 2.0.0 is the second public release of the read-only Active Directory inventory module. It retains the existing ten inventories and introduces a shared interactive offline dashboard across every report.

## Highlights

- Shared JP-branded dashboard with focused navigation, light and dark themes, filtering, sorting, pagination and record details.
- Browser CSV and JSON exports while retaining the existing on-disk HTML, JSON, CSV and JSONL outputs.
- Section-specific icons, compact embedded data and bounded static fallback tables.
- Improved controller progress and final complete/partial summaries.
- Improved group membership collection and forest relationship evidence while preserving explicit unknown and partial outcomes.
- Date-only output names with numbered run folders for same-day reruns.
- Fixed user summary generation when optional directory attributes serialize without a value.

## Preserved scope

The release still provides exactly these ten read-only inventories:

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

No collector or inventory category was added. The module continues to target Windows PowerShell 5.1, exports the same 11 public commands, preserves `-Quiet`, and performs no remediation or configuration changes.

## Validation boundaries

All 579 module/source checks and 28 clean-package checks passed on PowerShell 7.6.8 on macOS, for 607 offline checks in total. Native Windows PowerShell 5.1, live Active Directory collection and native Windows browser validation were unavailable and are not claimed. See `VALIDATION.md` for details.
