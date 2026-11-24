# Report rendering and image processing

AuthLens renders PDF and DOCX in `AuthLens.Documents`. The API constructs one frozen report model and supplies it with an already validated logo.
Renderers receive no database connection, mutable review context or HTTP request. Business evidence and decisions are computed before rendering.

| Capability | Implementation |
| --- | --- |
| PDF | `PdfReportRenderer`, SkiaSharp PDF output and bundled fonts |
| DOCX | Open XML document rendering |
| Images | `ImageSanitizer`, bounded decoding and normalized image bytes |

## Evidence and layout

SoD reports use the selected immutable period/evidence model. Rendering does not recalculate decisions or modify approvals, snapshots or history.
Headers, metadata, table headings, coverage limitations and footer/page numbering derive from the same frozen model. Multi-page tables repeat
headers. Unknown and incomplete source evidence remains explicit in the report.

Logos and other uploaded images pass format, size, dimensions and decode validation before use. Do not accept an extension as proof of format,
load external URLs or embed executable vector content. PDF text must fit supported embedded fonts; unsupported content fails explicitly.
Keep the existing document-size and resource bounds rather than retrying with weaker validation.

## Validation

Focused reporting and image tests cover document structure, metadata, pagination, Unicode/fonts and image accept/refuse behavior using synthetic
fixtures. Native/platform rendering and exported-document visual checks remain separate. See [development](../development/README.md),
[SoD reports](../features/SOD.md) and [branding](DESIGN_SYSTEM.md#branding-source-assets).
