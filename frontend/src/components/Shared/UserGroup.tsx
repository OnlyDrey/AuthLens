/** The SAP user group(s) of a record as plain text, joined for several groups. Empty when the data carries none. */
export const groupText = (groups?: string[] | string | null) => (Array.isArray(groups) ? groups.filter(Boolean).join(', ') : groups || '')

/**
 * One presentation of a SAP user group for every table that has a dedicated "SAP user group" column: compact single-line text (the complete value
 * stays in the tooltip when the column is narrow) and a muted dash with an accessible "No SAP user group" for records that have none.
 */
export function UserGroupCell({ groups }: { groups?: string[] | string | null }) {
  const text = groupText(groups)
  return text
    ? <span className="user-group-text" title={`SAP user group: ${text}`}>{text}</span>
    : <span className="user-group-text" data-missing="true" title="No SAP user group in the imported data"><span aria-hidden="true">—</span><span className="sr-only">No SAP user group</span></span>
}
