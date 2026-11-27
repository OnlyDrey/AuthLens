import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { cleanup, names, openSod, seedGovernance } from './sod-fixture'

// BUG-015: the SAP User Group heatmap follows the SoD Overview population (the same server resolver as the key figures), in Risks and
// Activities mode, in its CSV export and in the Risk Matrix drill-down. Fixture: SYN_A (FIN) has R1 and R2, SYN_B (P2P) has R1, SYN_C (P2P) none.
let directory: string
test.beforeEach(async ({ request }) => { directory = await seedGovernance(request, 'static') })
test.afterEach(async ({ request }) => { await cleanup(request, directory) })

const heatmap = (page: Page) => page.getByRole('region', { name: 'SAP User Group heatmap', exact: true })
const distinct = (page: Page) => heatmap(page).getByRole('table').getByRole('row', { name: /^Distinct users/ })
const groupRows = (page: Page) => heatmap(page).locator('tbody th').allInnerTexts()
const kpi = (page: Page) => page.getByRole('region', { name: 'Conflicts', exact: true }).getByRole('button', { name: /Users with potential conflicts/ })
async function exact(page: Page, value: string) {
  const filters = page.getByRole('complementary', { name: 'Filters', exact: true })
  const toggle = page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^(Hide )?[Ff]ilters/ })
  await expect(toggle).toBeVisible()
  if ((await toggle.getAttribute('aria-expanded')) !== 'true') await toggle.click()
  await filters.getByRole('textbox', { name: 'Exact usernames', exact: true }).fill(value)
  await filters.getByRole('button', { name: 'Apply exact usernames', exact: true }).click()
}

test('filtered key figures and the heatmap count the same population in both modes, and clearing restores the global view', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  const heatRequests: string[] = []
  page.on('request', request => { const url = new URL(request.url()); if (/^\/api\/sod\/matrix\/(risk|activity)$/.test(url.pathname) && url.searchParams.get('group_by') === 'group') heatRequests.push(url.search) })
  await openSod(page)
  await expect(kpi(page)).toContainText('2')
  await expect(distinct(page)).toContainText('2')                                            // unfiltered: global population
  await expect(heatmap(page).getByRole('status', { name: 'Heatmap population' })).toContainText('Global')
  await expect.poll(() => groupRows(page)).toEqual(expect.arrayContaining(['FIN', 'P2P']))
  await exact(page, names.a)
  await expect(kpi(page)).toContainText('1')
  await expect(distinct(page)).toContainText('1')                                            // the reported discrepancy: KPI and heatmap agree
  await expect(heatmap(page).getByRole('status', { name: 'Heatmap population' })).toContainText('Filtered')
  await expect.poll(() => groupRows(page)).toEqual(['FIN'])
  await expect(heatmap(page).getByRole('row', { name: /^FIN\b/ }).getByRole('button', { name: /with R2/ })).toBeVisible()   // the user keeps every conflict
  expect(heatRequests.at(-1)).toContain('population=overview')
  await heatmap(page).getByRole('button', { name: 'Activities', exact: true }).click()
  await expect(distinct(page)).toContainText('1')
  await expect.poll(() => groupRows(page)).toEqual(['FIN'])
  await exact(page, names.c)                                                                 // a population without conflicts is empty, not global
  await expect(kpi(page)).toContainText('0')
  await expect(heatmap(page)).toContainText('No potential conflicts')
  await exact(page, '')                                                                       // clearing restores the global view
  await expect(distinct(page)).toContainText('2')
  await expect.poll(() => groupRows(page)).toEqual(expect.arrayContaining(['FIN', 'P2P']))
})

test('the filtered heatmap exports its population and drills into the Risk Matrix with the filters kept', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await openSod(page)
  await exact(page, names.b)
  await expect(distinct(page)).toContainText('1')
  await expect.poll(() => groupRows(page)).toEqual(['P2P'])
  const download = page.waitForEvent('download')
  await heatmap(page).getByRole('button', { name: /Export heatmap CSV/ }).click()
  const csv = readFileSync((await (await download).path())!, 'utf8').replace(/^\ufeff/, '')
  const groups = csv.trim().split(/\r?\n/).slice(1).map(line => line.split(';')[0].replace(/"/g, ''))
  expect(new Set(groups)).toEqual(new Set(['P2P']))                                          // only the filtered population is exported
  await heatmap(page).getByRole('row', { name: /^P2P\b/ }).getByRole('button', { name: /with R1/ }).click()
  await expect(page).toHaveURL(/#\/sod\/risk-matrix/)
  const sidebar = page.getByRole('complementary', { name: 'Filters', exact: true })
  await expect(sidebar.getByRole('button', { name: 'Remove SAP User Group P2P', exact: true })).toBeVisible()
  await expect(sidebar.getByRole('button', { name: 'Remove Risk ID R1', exact: true })).toBeVisible()
  await expect(sidebar.getByRole('status').filter({ hasText: '1 exact usernames selected' })).toBeVisible()   // the overview population is kept
  await expect(page.locator('tbody th.matrix-row-head code')).toHaveText([names.b])
})
