import { useLocalPreference } from './localPreference'

/** TBL-03 standard result-table page sizes; the server pages tables up to 250 rows. */
export const PAGE_SIZES = [10, 25, 50, 100, 250] as const
export const DEFAULT_PAGE_SIZE = 25

/**
 * The page size of one result table, remembered per browser and table (a presentation preference, like column order; never evidence).
 * An unknown or outdated stored value falls back to the default.
 */
export function usePageSize(table: string, fallback: number = DEFAULT_PAGE_SIZE): [number, (size: number) => void] {
  const [stored, setStored] = useLocalPreference(`authlens.page-size.${table}`, String(fallback))
  const value = Number(stored)
  return [(PAGE_SIZES as readonly number[]).includes(value) ? value : fallback, (size: number) => setStored(String(size))]
}
