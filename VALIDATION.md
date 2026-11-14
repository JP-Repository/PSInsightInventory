# PSInsightInventory validation

## Version 2.0.0

On 12 November 2026, all 579 module/source checks and 28 clean-package checks passed in PowerShell 7.6.8 on macOS, for 607 offline checks in total. Coverage included missing user attributes when the serializer emits nothing for null, date-only filenames, preservation of reports on same-day reruns, package allowlisting, metadata, checksums and all ten fictional demo pipelines. Windows PowerShell 5.1, live Active Directory collection and native Windows browser validation were unavailable and are not claimed.

The actual fictional Domain Controller, Sites & Services and User dashboards were rendered at 1440×1000 in headless Google Chrome and visually reviewed. The User dashboard was also reviewed at a 480×1000 responsive viewport; a narrow-screen minimum-width rule is included for smaller devices. Automated JavaScript checks exercise theme switching and report interactions, but native Edge/Chrome review on Windows remains pending.

## Version 1.1.3

All 574 offline PowerShell checks and all ten demo dashboard checks passed. The live-entry regression check uses a mocked discovery job for Infrastructure and DNS, with and without Quiet. Windows PowerShell 5.1 and live AD collection were unavailable.


## Version 1.1.2

All 573 offline PowerShell checks passed on PowerShell 7.4.6 for Linux. Console checks exercised the repository banner, native progress records, controller coverage summary and Quiet. All ten regenerated demo reports passed data and JavaScript interaction checks. Windows PowerShell 5.1 and a live Active Directory domain were unavailable.

For version 1.1.1, all ten demo reports were regenerated. The dashboard checks verified that each sidebar section renders an inline SVG and avoids the generic list fallback. Forest and Group also passed checks for distinct icons on every section. Visual browser review remains pending.

## Version 1.1.0

The build uses the available module source archive and preserves the manifest GUID and eleven public commands.

- **568 PowerShell checks passed** on PowerShell 7.4.6 for Linux. The suite covers module parsing and exports, all ten sample inventories, collector mocks, cancellation, encoding and console output. The Group suite includes a single scoped identity scan and separate unknown membership counts. The Forest suite verifies unique server counts, relationship provenance and missing parent handling.
- All ten public inventory commands regenerated their fictional HTML, CSV, JSON and JSONL examples. HTML data and section schemas match the on-disk JSON.
- JavaScript execution checks with simulated DOM elements passed on all ten generated reports. These checks exercised section navigation, coverage filtering, record details, search, theme switching and export content. The browser could not launch in the validation environment. Actual desktop and mobile rendering and browser downloads remain to be validated.
- Reusing the previous partial group snapshot as a size comparison, compact JSON with successful resolution duplicates removed was about 25 MiB. The old HTML was about 96 MiB. This comparison does not measure live collection speed or size for a fully collected snapshot.

Native Windows PowerShell 5.1 and live Active Directory were unavailable. Validate paged LDAP collection, range continuation, identity resolution, AD permissions and forest relationships on Windows before release.

The redesigned group report distinguishes zero direct links from unavailable membership. Its coverage denominator excludes metadata enumeration and identity resolution. Successful member resolution status remains on the member rows. The separate resolution dataset lists exceptions. The forest report merges server references by name, retaining directory roles and reference sources. Parent relationships use directory evidence.
