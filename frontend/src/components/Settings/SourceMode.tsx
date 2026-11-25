import { FormField } from '@/components/Shared/Controls'
import { Select } from '@/components/Shared/Select'

/** WP33 (FILE-006): the update mode is independent of the file location and can change before or after validation and import. Changing it keeps
 * the configured file and the active dataset; saving affects future refreshes only (nothing is read when the setting is saved). */
export function SourceMode({
  value,
  onChange,
  disabled=false,
  location='host',
  saved,
}: {
  disabled?:boolean
  value: 'static' | 'dynamic'
  onChange: (value: 'static' | 'dynamic') => void
  location?: 'upload' | 'host' | 'desktop'
  saved?: string
}) {
  const changed = saved !== undefined && saved !== value
  return (
    <div className="source-mode-row">
      <FormField label="Update mode">
        <Select
          disabled={disabled}
          className="ui-control"
          value={value}
          onChange={(e) => onChange(e.target.value as 'static' | 'dynamic')}
        >
          <option value="static">Static: replace manually</option>
          <option value="dynamic">Dynamic: refresh from the file</option>
        </Select>
      </FormField>
      <p className="text-sm text-[var(--muted)]">
        {value === 'static'
          ? 'The imported data stays until you replace it. Global Refresh and scheduled refresh skip this source; the configured file is kept, so switching back to Dynamic needs no new selection.'
          : location === 'upload'
            ? 'An uploaded copy cannot follow changes on the device it came from. Choose "File on the AuthLens host" to refresh automatically; the current data stays active until a new file imports.'
            : 'Global Refresh and scheduled refresh reread the configured file and replace the data only after a complete, valid read. A missing, unreadable, invalid or empty file keeps the last valid data.'}
      </p>
      {changed && <p role="status" className="text-sm">Save settings to apply the mode change. Saving reads nothing now and keeps the active data; {value === 'dynamic' ? 'the next Global or scheduled refresh reads the file (or use Refresh source).' : 'later refreshes leave this source unchanged.'}</p>}
    </div>
  )
}
