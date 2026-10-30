# JP branding

PSInsightInventory reuses the JP monogram from the user's PSInsightExpl 0.6.0 package.
The mark is HTML/CSS, not a separate bitmap file. Its purple background, white JP lettering,
rounded shape, font weight and letter spacing are retained. The inventory console keeps its own layout.

Source files consulted: `Templates/Layout/report-shell.js` and `Templates/Layout/report.css`.
The source module was read only. PSInsightInventory has no runtime dependency on PSInsightExpl.

Source report-shell.js SHA-256: `a9e7297bb50b9fe217c7f4f40f394a49896aac14539046b9d85d4410fc60c2e5`
Source report.css SHA-256: `65d47d91247dcb4d36134b7a186d78222ae7036bfd9decdc2b5d8ec6ea60cfbb`
JP style declarations are bundled in `Assets/JP.brand.css` and embedded in each generated report.
