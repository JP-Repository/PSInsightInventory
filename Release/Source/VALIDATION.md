# Validation — PSInsightInventory 1.0.0

Release validation was run on 30 October 2026 with PowerShell 7.6.8 on macOS.

## Completed offline checks

All 13 offline suites passed: **592 checks total**.

| Suite | Checks |
|---|---:|
| Module, parser, manifest, exports, and public command behavior | 85 |
| Domain controller inventory engine | 74 |
| Sites & Services | 53 |
| Forest & Domain | 41 |
| Trust | 32 |
| DNS | 53 |
| Group Policy | 44 |
| Organizational Unit | 39 |
| Computer | 42 |
| Group | 37 |
| User | 42 |
| Console display and `-Quiet` | 24 |
| Release package | 26 |

`Test-ModuleManifest` also completed successfully and returned:

- Name: `PSInsightInventory`
- Version: `1.0.0`
- Author: `Jonathan Preetham`
- PowerShell version: `5.1`
- Exported functions: 11 (catalog plus ten inventory commands)
- Required modules at import: 0

The tests used fictional fixtures and mocked providers. They generated all ten demo reports and verified existing schemas, failure/unknown semantics, CSV/JSON agreement, static fallbacks, embedded JP branding, console stream isolation, `-Quiet`, and worker cleanup. Release tests additionally verified Help & About links in all ten packaged reports, absence of those links from the console banner, the GitHub source stage, Gallery module stage, ZIP layout, SHA-256 checksum, and exclusion of generated/sensitive paths.

The tests and their generated output were isolated in a temporary directory. No live AD, DNS, Group Policy, WinRM, domain controller, trust partner, or endpoint was contacted.

## Not validated in this environment

The following checks were **not run** and must not be reported as passed:

- Native Windows PowerShell 5.1 import and execution
- Live Active Directory provider collection
- Live DNS and Group Policy provider collection
- Live WinRM/Kerberos collection from a domain controller
- ISE, Windows Terminal, scheduled-task, or other Windows host rendering
- Manual visual/browser review and browser-initiated CSV/JSON downloads
- PowerShell Gallery publication/install round trip

PowerShell 7.6.8 parser, fixture, and mocked-provider success does not replace native Windows PowerShell 5.1 or live-environment validation.

## Scope and safety findings

- No collectors or inventory categories were added.
- Collection remains read-only; mutating AD/DNS/GPO cmdlets and remediation behavior are not present.
- The ten inventory commands, console banner, progress display, `-Quiet`, report layouts, output schemas, and JP branding are preserved.
- Organization-like examples were replaced with reserved `example.test` names.
- Old generated example logs containing internal build paths were removed.
- The publishable module package excludes examples, tests, reports, logs, test output, source-control metadata, build tooling, archives, credentials, certificate/key files, and publishing tokens.
- Author, repository, support, and documentation links are confined to HTML Help & About and documentation; the console banner contains no URLs or contact details.
