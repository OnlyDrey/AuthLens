import { test, expect, type Locator, type Page } from '@playwright/test'
import { goTo, headers, pickMulti, seedSources, type SeededSources } from './support'

/** FLT-01 filter group order, FLT-02 collapsible sections and FLT-03 filter discovery, on the shared FilterLayout. */
const NL = String.fromCharCode(10)
const roles = ['FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE', 'MM,ZC:MM:A,Alpha,ZS:A,T01', 'FI,ZC:FI:B,Beta,ZS:B,T02', ''].join(NL)
const users = ['USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO', 'FP01,ZC:MM:A,G1,20200101,99991231', 'FP02,ZC:FI:B,G2,20200101,99991231',
  'FP03,ZO:MM:M:PR_REL_ST_E2_N1:ALL,G1,20200101,99991231', 'FP04,ZC:MM:A,G2,20200101,20210101', ''].join(NL)
let seeded: SeededSources
test.beforeEach(async ({ request }) => { seeded = await seedSources(request, { roles, users }) })
test.afterEach(async () => { await seeded.cleanup() })

const panel = (page: Page) => page.getByRole('complementary', { name: 'Filters', exact: true })
const toggle = (scope: Locator, title: string) => scope.getByRole('button', { name: new RegExp(`^${title}( \\d+ active)?$`) })
const headings = (scope: Locator) => scope.locator('.filter-section:not([hidden]) .filter-section-title').allTextContents()
const discovery = (scope: Locator) => scope.getByRole('searchbox', { name: 'Find a filter', exact: true })

test('FLT-01 workspaces order their groups Search, Population, Organization, Access, then page groups; Release Access leads with Release classification', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  await expect.poll(() => headings(panel(page))).toEqual(['Saved Filters', 'Search', 'Population', 'Organization', 'Access', 'Assignments'])
  await goTo(page, 'Account Review')
  await expect.poll(() => headings(panel(page))).toEqual(['Saved Filters', 'Search', 'Population', 'Organization', 'Review'])
  await goTo(page, 'Release Access')
  await expect.poll(() => headings(panel(page))).toEqual(['Saved Filters', 'Release classification', 'Assignment', 'Population'])
  const classification = panel(page).locator('[data-filter-section="release-classification"] .filter-section-body')
  const labels = await classification.locator(':scope > *').evaluateAll(fields => fields.map(field => field.querySelector('label, legend')?.textContent?.trim() ?? ''))
  expect(labels.slice(0, 5)).toEqual(['PR/PO', 'Release SAP user group', 'Release area', 'Release group', 'Release strategy'])
  await expect(toggle(panel(page), 'Release classification')).toHaveAttribute('aria-expanded', 'true') // the Release Access exception is expanded
  await expect(toggle(panel(page), 'Population')).toHaveAttribute('aria-expanded', 'false')
  await goTo(page, 'Role Lookup')
  await expect.poll(() => headings(panel(page))).toEqual(['Saved Filters', 'Search', 'Access', 'Role categories'])
})

test('FLT-02 sections collapse independently, remember their state per workspace and never clear a value', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  const sidebar = panel(page), rows = page.getByRole('region', { name: 'User directory table', exact: true }).locator('tbody tr')
  // defaults: primary groups expanded, the secondary Assignments group collapsed
  for (const title of ['Search', 'Population', 'Organization', 'Access']) await expect(toggle(sidebar, title)).toHaveAttribute('aria-expanded', 'true')
  await expect(toggle(sidebar, 'Assignments')).toHaveAttribute('aria-expanded', 'false')
  await expect(sidebar.getByLabel('Show expired assignments', { exact: true })).toBeHidden()
  // an active filter is counted in its header and survives collapsing
  await pickMulti(sidebar, 'SAP user group', 'G1', page)
  await expect(rows).toHaveCount(2)
  await expect(toggle(sidebar, 'Population')).toHaveAccessibleName('Population 1 active')
  await toggle(sidebar, 'Population').click()
  await expect(toggle(sidebar, 'Population')).toHaveAttribute('aria-expanded', 'false')
  await expect(sidebar.getByRole('combobox', { name: 'SAP user group', exact: true })).toBeHidden()
  await expect(rows).toHaveCount(2) // still filtered
  // several sections open at once; keyboard operable
  await toggle(sidebar, 'Assignments').focus(); await page.keyboard.press('Enter')
  await expect(toggle(sidebar, 'Assignments')).toHaveAttribute('aria-expanded', 'true')
  await expect(toggle(sidebar, 'Organization')).toHaveAttribute('aria-expanded', 'true')
  // Collapse all / Expand all
  await sidebar.getByRole('button', { name: 'Collapse all filter groups', exact: true }).click()
  for (const title of ['Search', 'Population', 'Organization', 'Access', 'Assignments']) await expect(toggle(sidebar, title)).toHaveAttribute('aria-expanded', 'false')
  await sidebar.getByRole('button', { name: 'Expand all filter groups', exact: true }).click()
  for (const title of ['Search', 'Population', 'Organization', 'Access', 'Assignments']) await expect(toggle(sidebar, title)).toHaveAttribute('aria-expanded', 'true')
  await expect(sidebar.getByRole('group', { name: /SAP user group/ }).or(sidebar.getByRole('button', { name: /^Remove SAP user group G1/ })).first()).toBeVisible() // the value is still there
  // the state is remembered for this workspace across navigation and reload, not shared with another workspace
  await toggle(sidebar, 'Organization').click()
  await goTo(page, 'Account Review'); await expect(toggle(panel(page), 'Organization')).toHaveAttribute('aria-expanded', 'true')
  await page.reload(); await goTo(page, 'Users')
  await expect(toggle(panel(page), 'Organization')).toHaveAttribute('aria-expanded', 'false')
  // Clear filters keeps the expansion (the reload opened the page fresh, so set a filter to clear first)
  await pickMulti(panel(page), 'SAP user group', 'G1', page)
  await panel(page).getByRole('button', { name: 'Clear filters', exact: true }).click()
  await expect(panel(page).getByRole('button', { name: /^Remove SAP user group/ })).toHaveCount(0)
  await expect(toggle(panel(page), 'Organization')).toHaveAttribute('aria-expanded', 'false')
})

test('FLT-02 a collapsed section that receives restored active filters opens, and can be collapsed again', async ({ page, request }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  const sidebar = panel(page), rows = page.getByRole('region', { name: 'User directory table', exact: true }).locator('tbody tr')
  // Save a filter with a SAP user group, then clear it and collapse Population
  await pickMulti(sidebar, 'SAP user group', 'G2', page)
  await expect(rows).toHaveCount(2)
  const bar = page.getByRole('dialog', { name: 'users saved filters', exact: true })
  await sidebar.locator('div.saved-filter-toolbar[aria-label="users saved filters"]').getByRole('button', { name: /Saved filters/ }).click()
  await bar.getByLabel('Saved filter name').fill('FLT group G2')
  await bar.getByRole('button', { name: 'Save as new', exact: true }).click()
  await expect(bar).toContainText('Saved filters updated.')
  await page.keyboard.press('Escape')
  await sidebar.getByRole('button', { name: 'Clear filters', exact: true }).click()
  await expect(rows).toHaveCount(4)
  await toggle(sidebar, 'Population').click()
  await expect(toggle(sidebar, 'Population')).toHaveAttribute('aria-expanded', 'false')
  // Loading the saved filter restores the group into the collapsed section: it opens to show it
  await sidebar.locator('div.saved-filter-toolbar[aria-label="users saved filters"]').getByRole('button', { name: /Saved filters/ }).click()
  const choice = bar.getByRole('combobox', { name: 'Saved filter', exact: true })
  await choice.click(); await choice.fill('FLT group G2') // the popover focuses the selector without opening it
  await page.getByRole('option').filter({ hasText: 'FLT group G2' }).first().click()
  await bar.getByRole('button', { name: 'Load', exact: true }).click()
  await page.keyboard.press('Escape')
  await expect(rows).toHaveCount(2)
  await expect(toggle(sidebar, 'Population')).toHaveAttribute('aria-expanded', 'true')
  await expect(toggle(sidebar, 'Population')).toHaveAccessibleName('Population 1 active')
  // The user may collapse it again; the filter stays applied
  await toggle(sidebar, 'Population').click()
  await expect(toggle(sidebar, 'Population')).toHaveAttribute('aria-expanded', 'false')
  await expect(rows).toHaveCount(2)
  // saved filters are user data outside the seeded sources: remove the one this test created
  for (const item of (await (await request.get('/api/saved-filters', { headers })).json()).items.filter((entry: { name: string }) => entry.name === 'FLT group G2'))
    await request.post('/api/saved-filters/delete', { headers, data: { id: item.id, expected: item.modified } })
})

test('FLT-03 filter discovery finds fields by name, section and alias, without requests or value changes', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  const sidebar = panel(page), rows = page.getByRole('region', { name: 'User directory table', exact: true }).locator('tbody tr')
  await pickMulti(sidebar, 'SAP user group', 'G1', page)
  await expect(rows).toHaveCount(2)
  const requests: string[] = []
  page.on('request', request => { if (new URL(request.url()).pathname.startsWith('/api/access/')) requests.push(request.url()) }) // dataset requests
  const find = discovery(sidebar)
  // a field name (partial, case-insensitive): only the matching field is shown; the collapsed Assignments group opens for it temporarily
  await find.fill('EXPIRED')
  await expect(sidebar.getByLabel('Show expired assignments', { exact: true })).toBeVisible()
  await expect(sidebar.getByRole('textbox', { name: 'Exact usernames', exact: true })).toBeHidden()
  expect(await headings(sidebar)).toEqual(['Population', 'Assignments']) // Population stays: it holds the active SAP user group filter
  // a section name shows the whole section
  await find.fill('organ')
  await expect(sidebar.getByRole('combobox', { name: 'Functional Group', exact: true })).toBeVisible()
  await expect(sidebar.getByRole('combobox', { name: 'Manager', exact: true })).toBeVisible()
  // an alias of a canonical term (TBL-04)
  await find.fill('user group')
  await expect(sidebar.getByRole('combobox', { name: 'SAP user group', exact: true })).toBeVisible()
  // no match
  await find.fill('zz-no-such-filter')
  await expect(sidebar.getByRole('status').filter({ hasText: 'No filters match' })).toBeVisible()
  // clearing restores the saved expansion; values and results are untouched; nothing was requested
  await sidebar.getByRole('button', { name: 'Clear filter search', exact: true }).click()
  await expect(toggle(sidebar, 'Assignments')).toHaveAttribute('aria-expanded', 'false')
  await expect(sidebar.getByRole('textbox', { name: 'Exact usernames', exact: true })).toBeVisible()
  await expect(rows).toHaveCount(2)
  expect(requests).toEqual([])
  // the discovery field is separate from the dataset search
  await expect(page.getByLabel('Search users', { exact: true })).toHaveValue('')
})

for (const theme of ['light', 'dark'] as const) test(`FLT-02/03 the mobile filter drawer offers the same sections and discovery (${theme})`, async ({ page }) => {
  await page.emulateMedia({ colorScheme: theme })
  await page.setViewportSize({ width: 375, height: 800 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Release Access')
  await page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^Filters/ }).click()
  const drawer = page.getByRole('dialog', { name: 'Filters', exact: true })
  await expect(toggle(drawer, 'Release classification')).toHaveAttribute('aria-expanded', 'true')
  await expect(toggle(drawer, 'Population')).toHaveAttribute('aria-expanded', 'false')
  await discovery(drawer).fill('strategy')
  await expect(drawer.getByRole('combobox', { name: 'Release strategy', exact: true })).toBeVisible()
  await expect(drawer.getByRole('combobox', { name: 'Release area', exact: true })).toBeHidden()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
})
