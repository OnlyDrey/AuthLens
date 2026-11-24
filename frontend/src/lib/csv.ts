// Quote every field; neutralise spreadsheet formulas without changing normal SAP identifiers.
export function csvField(value: unknown): string {
  let text = value == null ? '' : String(value)
  // eslint-disable-next-line no-control-regex -- control characters before a formula marker must be caught too
  if (/^[\s\u0000-\u001f]*[=+@-]/u.test(text) || /^[\t\r\n]/u.test(text)) text = "'" + text
  return '"' + text.replace(/"/g, '""') + '"'
}

/** UI projections export only supplied rows/columns, in their supplied order. No network fetching or hidden cross-page scope. */
export function buildTableCSV(headers: readonly string[], rows: Iterable<readonly unknown[]>, maxBytes = 32 * 1024 * 1024): string {
  const encoder = new TextEncoder(), lines = [headers.map(csvField).join(',')]
  let bytes = 3 + encoder.encode(lines[0]).byteLength
  if (bytes > maxBytes) throw new Error('Export exceeds 32 MiB. Narrow the displayed data or selected columns.')
  for (const row of rows) {
    if (row.length !== headers.length) throw new Error('Table columns changed. Close the column menu and retry the export.')
    const line = row.map(csvField).join(',')
    bytes += 2 + encoder.encode(line).byteLength
    if (bytes > maxBytes) throw new Error('Export exceeds 32 MiB. Narrow the displayed data or selected columns.')
    lines.push(line)
  }
  return '\uFEFF' + lines.join('\r\n')
}
