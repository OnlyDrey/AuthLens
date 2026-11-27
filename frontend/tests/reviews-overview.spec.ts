import { test, expect, type Page, type Locator } from '@playwright/test'
import { cleanup, createPeriod, decide, names, openReviews, seedGovernance, uniqueName } from './sod-fixture'
import { headers } from './support'

// WP37: the Reviews Overview as an operational dashboard. Fixture: SYN_A (FIN) has R1 and R2, SYN_B (P2P) has R1, SYN_C (P2P) no conflict but
// role assignments, so all three are in the access-review population (as in the Work Queue).
let directory: string
test.beforeEach(async ({ request }) => { directory = await seedGovernance(request) })
test.afterEach(async ({ request }) => { await cleanup(request, directory) })

const card = (page: Page, name: string) => page.getByRole('region', { name, exact: true })
// A row's label span also holds its note, so match the label at the start.
const metric = (scope: Locator, label: string) => scope.locator('.info-row').filter({ has: scope.page().locator('.info-row-label', { hasText: new RegExp(`^${label}`) }) }).first().locator('.info-row-value')
const queueTile = (page: Page, label: string) => page.getByRole('region', { name: 'Review progress', exact: true }).getByRole('button', { name: new RegExp(`^${label}`) })
const noPageOverflow = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)
async function openFilters(page: Page) {
  const toggle = page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^(Hide )?[Ff]ilters/ })
  await expect(toggle).toBeVisible()
  if ((await toggle.getAttribute('aria-expanded')) !== 'true') await toggle.click()
  return page.getByRole('complementary', { name: 'Filters', exact: true })
}
async function open(page: Page) {
  await page.goto('/#session=browser-test-session')
  await page.evaluate(() => localStorage.removeItem('authlens-reviews-overview-filter-sidebar'))
  await openReviews(page)
  await expect(card(page, 'Access Review Progress')).toBeVisible()
}

for (const scheme of ['light', 'dark'] as const) test(`KPI cards reconcile with the Work Queue, the sidebar is integrated and closed by default, and drill-down keeps the filters (${scheme})`, async ({ page }) => {
  await page.emulateMedia({ colorScheme: scheme })
  await page.setViewportSize({ width: 1440, height: 1000 })
  await open(page)
  const progress = card(page, 'Access Review Progress')
  await expect(metric(progress, 'Users in scope')).toHaveText('3')
  await expect(metric(progress, 'Users requiring review')).toHaveText('3')
  await expect(metric(progress, 'Users with completed reviews')).toHaveText('0')
  await expect(page.getByRole('complementary', { name: 'Filters', exact: true })).toBeHidden()  // closed by default
  for (const name of ['Review Coverage', 'Review Workload', 'Review Decisions', 'Remediation', 'Review Periods']) await expect(card(page, name)).toBeVisible()
  await expect(card(page, 'Review Periods')).toContainText('Global')
  expect(await noPageOverflow(page)).toBe(true)
  // Integrated left sidebar: no dialog, cards beside it; an exact-username filter scopes every population metric.
  const filters = await openFilters(page)
  await expect(page.getByRole('dialog')).toHaveCount(0)
  expect((await filters.boundingBox())!.x + (await filters.boundingBox())!.width).toBeLessThanOrEqual((await progress.boundingBox())!.x)
  await filters.getByRole('textbox', { name: 'Exact usernames', exact: true }).fill(names.a)
  await filters.getByRole('button', { name: 'Apply exact usernames', exact: true }).click()
  await expect(metric(progress, 'Users in scope')).toHaveText('1')
  // Drill-down: the Work Queue opens with the same filters and the matching progress tile; its count equals the KPI.
  await progress.getByRole('button', { name: /^Users requiring review/ }).click()
  await expect(page).toHaveURL(/#\/reviews\/queue/)
  await expect(queueTile(page, 'Needs review')).toHaveAttribute('aria-pressed', 'true')
  await expect(queueTile(page, 'Needs review')).toContainText('1')
  await expect(page.getByRole('complementary', { name: 'Filters', exact: true }).getByRole('status').filter({ hasText: '1 exact usernames selected' })).toBeVisible()
  await page.screenshot({ path: `../build/test-artifacts/reviews-overview/queue-drill-${scheme}.png` })
})

test('decisions move coverage, workload, decisions and remediation consistently; the removal recommendation is not shown as a removal', async ({ page, request }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const assignments = (await (await request.get('/api/sod/queue', { headers, params: { context: 'current', kind: 'assignment', limit: 200 } })).json()).items as { key: string; user: string; ref: string; evidence_version: string }[]
  const target = assignments.find(item => item.user === names.b)!
  await decide(request, 'assignment', 'current', [{ key: target.key, user: target.user, ref: target.ref, evidence_version: target.evidence_version }], 'Remove')
  await open(page)
  const decisions = card(page, 'Review Decisions'), remediation = card(page, 'Remediation'), coverage = card(page, 'Review Coverage')
  await expect(decisions.getByRole('list', { name: 'Role reviews decisions' }).locator('.info-row').filter({ hasText: 'Removal recommended' }).locator('.info-row-value')).toHaveText('1')
  await expect(metric(remediation, 'Assignments recommended for removal')).toHaveText('1')
  await expect(metric(remediation, 'Awaiting a remediation action')).toHaveText('1')
  await expect(metric(remediation, 'Removals confirmed by SAP evidence')).toHaveText('0')
  await expect(remediation).toContainText('A recommendation, not proof of removal.')
  await expect(coverage).toContainText('Role reviews')
  await expect(metric(card(page, 'Access Review Progress'), 'Users with removal recommendations')).toHaveText('1')
  await remediation.getByRole('button', { name: /^Awaiting a remediation action/ }).click()
  await expect(page).toHaveURL(/#\/reviews\/remediation/)
  await expect(page.getByRole('button', { name: 'Awaiting action', exact: true })).toHaveAttribute('aria-pressed', 'true')
})

test('organizational progress groups by SAP User Group with distinct totals, sorts, opens the Work Queue per group, and is limited for frozen periods', async ({ page, request }) => {
  await page.setViewportSize({ width: 1280, height: 1000 })
  const id = await createPeriod(request, uniqueName('Synthetic overview period'))
  await open(page)
  const section = card(page, 'Organizational review progress')
  const table = section.getByRole('table')
  await expect(table.locator('tbody th')).toHaveText(['FIN', 'P2P'])
  await expect(section).toContainText('3 distinct users')
  await section.getByRole('combobox', { name: 'Sort groups' }).selectOption('users')
  await section.getByRole('button', { name: /Ascending order/ }).click()
  await expect(table.locator('tbody th').first()).toBeVisible()
  await section.getByRole('combobox', { name: 'Group by', exact: true }).selectOption('functional_group')
  await expect(table.locator('tbody th')).toHaveText(['Unassigned'])                      // users without a Functional Group are listed
  await section.getByRole('combobox', { name: 'Group by', exact: true }).selectOption('department')
  await expect(section.getByRole('status')).toContainText('Employee Directory')             // unavailable, never invented
  await section.getByRole('combobox', { name: 'Group by', exact: true }).selectOption('sap_user_group')
  await table.getByRole('button', { name: 'Open the Work Queue for FIN', exact: true }).click()
  await expect(page).toHaveURL(/#\/reviews\/queue/)
  await expect(queueTile(page, 'All users')).toContainText('1')                              // FIN: SYN_A only
  // A frozen period: SAP User Groups from its evidence; other dimensions are not substituted from current data.
  await openReviews(page)
  await page.getByRole('combobox', { name: 'Review context', exact: true }).selectOption(id)
  await section.getByRole('combobox', { name: 'Group by', exact: true }).selectOption('functional_group')
  await expect(section.getByRole('status')).toContainText('never substituted')
  await page.setViewportSize({ width: 375, height: 812 })
  expect(await noPageOverflow(page)).toBe(true)
})
