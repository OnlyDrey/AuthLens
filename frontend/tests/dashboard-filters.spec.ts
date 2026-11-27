import { test, expect, type Page, type Locator } from '@playwright/test'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { headers, expandFilterSection, goTo, postConfiguration } from './support'

// WP30 (DASH-001 to DASH-015): one dashboard with a global and a filtered mode. BUG-014: its filters use the shared FilterLayout (integrated
// left sidebar on wide screens, the shared drawer on narrow ones) like User Access. Synthetic data only.
let directory: string
const roles = 'FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE\nMM,ZC:MM:A,Demo purchasing,ZS:A,MIGO\nFI,ZC:FI:B,Demo finance,ZS:B,ME21N\nSD,ZC:SD:C,Demo sales,ZS:C,VA03\n'
const users = 'USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO\nDEMO_ONE,ZC:MM:A,G1,20200101,99991231\nDEMO_ONE,ZC:FI:B,G1,20200101,99991231\nDEMO_TWO,ZC:MM:A,G2,20200101,99991231\nDEMO_THREE,ZC:SD:C,G2,20200101,99991231\n'
test.beforeEach(async ({ request }) => {
  await request.post('/api/configuration/reset', { headers })
  directory = mkdtempSync(path.join(tmpdir(), 'authlens-dashboard-filters-'))
  const rolePath = path.join(directory, 'roles.csv'), userPath = path.join(directory, 'users.csv')
  writeFileSync(rolePath, roles); writeFileSync(userPath, users)
  const settings = (await (await request.get('/api/configuration', { headers })).json()).settings
  settings.data_csv_path = rolePath; settings.user_csv_path = userPath
  expect((await postConfiguration(request, settings)).ok()).toBeTruthy()
})
test.afterEach(async ({ request }) => {
  await request.post('/api/configuration/reset', { headers })
  rmSync(directory, { recursive: true, force: true })
})
const usersValue = (page: Page) => page.locator('[data-metric="users"] .info-row-value')
const sidebar = (page: Page) => page.getByRole('complementary', { name: 'Filters', exact: true })
const toggle = (page: Page) => page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^(Hide )?[Ff]ilters/ })
// Card columns follow the width the workspace actually has (container query) within the viewport breakpoints; no card gets cramped.
const layout = (page: Page) => page.locator('.dashboard-workspace').evaluate(el => {
  const cards = el.querySelector('.dashboard-cards')!, width = el.getBoundingClientRect().width
  const columns = getComputedStyle(cards).gridTemplateColumns.split(' ').length
  const expected = Math.min(innerWidth <= 700 ? 1 : innerWidth <= 1199 ? 2 : 3, width <= 640 ? 1 : width <= 1040 ? 2 : 3)
  const narrowest = Math.min(...Array.from(cards.children).map(card => card.getBoundingClientRect().width))
  return { width, columns, expected, narrowest }
})
const noPageOverflow = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)
async function choose(scope: Locator, page: Page, label: string, option: RegExp) {
  const input = scope.getByRole('combobox', { name: label, exact: true })
  await input.click(); await page.getByRole('option', { name: option }).click(); await input.press('Escape')
}
async function open(page: Page) {
  await page.goto('/#session=browser-test-session')
  await page.evaluate(() => localStorage.removeItem('authlens-dashboard-filter-sidebar'))
  await goTo(page, 'Dashboard')
  await expect(usersValue(page)).toHaveText('3')
}

for (const scheme of ['light', 'dark'] as const) test(`desktop: the left sidebar is integrated, closed by default, reflows the cards and keeps applied filters (${scheme})`, async ({ page }) => {
  await page.emulateMedia({ colorScheme: scheme })
  await page.setViewportSize({ width: 1280, height: 1000 })
  const requests: string[] = []
  page.on('request', request => { if (new URL(request.url()).pathname === '/api/dashboard') requests.push(request.url()) })
  await open(page)
  await expect(page.getByRole('status', { name: 'Dashboard scope' })).toContainText('Global overview')
  await expect(toggle(page)).toHaveAttribute('aria-expanded', 'false')                      // closed by default
  await expect(sidebar(page)).toBeHidden()
  const full = await layout(page)
  expect(full.columns).toBe(full.expected)                                                   // filters hidden: the cards use the full width
  await toggle(page).click()
  const panel = sidebar(page)
  await expect(panel).toBeVisible()
  await expect(toggle(page)).toHaveText(/^Hide filters/)
  await expect(page.getByRole('dialog')).toHaveCount(0)                                      // no modal, backdrop or focus trap on desktop
  const aside = (await panel.boundingBox())!, cards = (await page.locator('.dashboard-workspace').boundingBox())!
  expect(aside.x + aside.width).toBeLessThanOrEqual(cards.x)                                 // left of the cards, never over them
  const beside = await layout(page)
  expect(beside.width).toBeLessThan(full.width - 200)                                        // the sidebar takes layout space instead of overlaying
  expect(beside.columns).toBe(beside.expected)                                               // the cards reflow beside the sidebar
  expect(beside.columns).toBeLessThan(full.columns + 1)
  expect(beside.narrowest).toBeGreaterThanOrEqual(260)
  expect(await noPageOverflow(page)).toBe(true)
  await choose(panel, page, 'SAP user group', /^G2 \(2\)$/)
  await choose(panel, page, 'Role name', /^ZC:MM:A/)
  await expect(usersValue(page)).toHaveText('3')                                             // nothing changes before Apply
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('1')                                             // G2 AND ZC:MM:A: DEMO_TWO only
  await expect(toggle(page)).toContainText('2')
  await expect(page.getByRole('status', { name: 'Dashboard scope' })).toContainText('Filtered overview')
  await expect(page.getByRole('group', { name: 'Applied dashboard filters' })).toContainText('SAP user group: G2')
  await expect(page.locator('[data-metric="roles"]')).toContainText('Global')                // catalogue metric stays global and says so
  const before = requests.length
  await toggle(page).click(); await expect(sidebar(page)).toBeHidden()
  expect((await layout(page)).width).toBe(full.width)                                        // hidden again: full width
  await toggle(page).click(); await expect(sidebar(page)).toBeVisible()
  await expect(usersValue(page)).toHaveText('1')                                             // toggling keeps the applied filters
  expect(requests.length).toBe(before)                                                       // and requests no dashboard data
  await page.getByRole('button', { name: 'Remove Role name: ZC:MM:A (2)', exact: true }).click()
  await expect(usersValue(page)).toHaveText('2')                                             // OR remains: the whole G2 group
  await choose(panel, page, 'Role name', /^ZC:MM:A/)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('1')
  await page.getByRole('button', { name: /^SAP users/ }).click()
  await expect(page.getByRole('link', { name: 'DEMO_TWO', exact: true })).toBeVisible()      // drill-down carries the population
  await expect(page.getByRole('link', { name: 'DEMO_THREE', exact: true })).toHaveCount(0)
  await goTo(page, 'Dashboard')                                                              // BUG-08: main navigation opens the page fresh
  await expect(usersValue(page)).toHaveText('3')
  await expect(sidebar(page)).toBeVisible()                                                  // the dashboard remembers its own open/closed choice
  await choose(sidebar(page), page, 'SAP user group', /^G2 \(2\)$/)
  await sidebar(page).getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('2')
  await page.getByRole('button', { name: 'Reset filters', exact: true }).click()             // toolbar Reset
  await expect(usersValue(page)).toHaveText('3')
  await choose(sidebar(page), page, 'SAP user group', /^G2 \(2\)$/)
  await sidebar(page).getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('2')
  await sidebar(page).getByRole('button', { name: 'Reset dashboard filters', exact: true }).click()   // sidebar Clear
  await expect(usersValue(page)).toHaveText('3')
  await page.screenshot({ path: `../build/test-artifacts/dashboard-filters/desktop-${scheme}.png` })
})

test('saved dashboard filters round-trip through the integrated sidebar', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await open(page)
  await toggle(page).click()
  const panel = sidebar(page), name = `Dashboard G1 ${Date.now()}`
  await choose(panel, page, 'SAP user group', /^G1 /)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('1')                                             // G1: DEMO_ONE
  await panel.getByRole('button', { name: /^Saved filters/ }).click()
  const menu = page.getByRole('dialog', { name: 'dashboard saved filters', exact: true })
  await menu.getByLabel('Saved filter name', { exact: true }).fill(name)
  await menu.getByRole('button', { name: 'Save as new', exact: true }).click()
  await expect(menu).toContainText('Saved filters updated.')
  await page.keyboard.press('Escape')
  await panel.getByRole('button', { name: 'Reset dashboard filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('3')
  await panel.getByRole('button', { name: /^Saved filters/ }).click()
  const saved = menu.getByRole('combobox', { name: 'Saved filter', exact: true })
  await saved.click(); await saved.fill(name); await page.getByRole('option').filter({ hasText: name }).first().click()
  await menu.getByRole('button', { name: 'Load', exact: true }).click()
  await page.keyboard.press('Escape')
  await expect(usersValue(page)).toHaveText('1')                                             // G1: DEMO_ONE
  await expect(page.getByRole('group', { name: 'Applied dashboard filters' })).toContainText('SAP user group: G1')
  expect(await noPageOverflow(page)).toBe(true)
})

for (const scheme of ['light', 'dark'] as const) test(`mobile: filters use the shared drawer like other modules, an empty population is reported and nothing overflows (${scheme})`, async ({ page }) => {
  await page.emulateMedia({ colorScheme: scheme })
  await page.setViewportSize({ width: 375, height: 812 })
  await open(page)
  await expect(sidebar(page)).toHaveCount(0)
  await toggle(page).click()
  const drawer = page.getByRole('dialog', { name: 'Filters', exact: true })
  await expect(drawer).toBeVisible()
  await choose(drawer, page, 'SAP user group', /^G1 /)
  await choose(drawer, page, 'Assigned transaction', /^VA03/)
  await drawer.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('0')
  const box = (await drawer.boundingBox())!
  expect(box.x).toBeGreaterThanOrEqual(0); expect(box.x + box.width).toBeLessThanOrEqual(376)
  await drawer.getByRole('button', { name: 'Show results', exact: true }).click()
  await expect(drawer).toHaveCount(0)
  await expect(usersValue(page)).toHaveText('0')                                             // closing the drawer keeps the applied filters
  expect(await noPageOverflow(page)).toBe(true)
  await toggle(page).click()
  await page.getByRole('dialog', { name: 'Filters', exact: true }).getByRole('button', { name: 'Reset dashboard filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('3')
})

test('access matching mode requires one assignment to match every access filter', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await open(page)
  await toggle(page).click()
  const panel = sidebar(page)
  await choose(panel, page, 'Role name', /^ZC:MM:A/)
  await choose(panel, page, 'Assigned transaction', /^ME21N/)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('1')                                             // DEMO_ONE: MM:A and ME21N through different roles
  await expandFilterSection(panel, 'Access matching') // FLT-02: a secondary group, collapsed by default
  await panel.getByRole('radio', { name: /^Matching access/ }).check()
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('0')                                             // no single assignment carries both
  await panel.getByRole('radio', { name: /^User population/ }).check()
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).first().click()
  await expect(usersValue(page)).toHaveText('1')
})
