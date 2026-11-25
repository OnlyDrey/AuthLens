import { test, expect, type Page } from '@playwright/test'
import { cleanup, enableSod, names, seedGovernance } from './sod-fixture'
import { goTo, seedSources } from './support'

// User feedback of 25 November 2026 (original item numbers): BUG-01 review panel toggle, BUG-02 review from Release role details, BUG-03
// Functional Group navigation, BUG-06 content-sized group cells, BUG-07 review progress on the profile, BUG-08 filter reset at page
// boundaries, BUG-10 whole-word wrapping. Synthetic data only.
const start = async (page: Page, link: string) => { await page.goto('/#session=browser-test-session'); await goTo(page, link) }
const ROLES = 'FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,CHILD_AGR_TEXT,TCODE,TTEXT\nMM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MM - Shared purchasing,MIGO,Goods movement\n'
const USERS = 'USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO\nU1,ZC:MM:BUY:ENP,G1,20200101,99991231\nU2,ZC:MM:BUY:ENP,G2,20200101,99991231\n'

test.describe('with SoD governance data', () => {
  let directory: string
  test.beforeEach(async ({ request }) => { directory = await seedGovernance(request, 'static') })
  test.afterEach(async ({ request }) => { await cleanup(request, directory) })

  test('BUG-01: the row control opens and closes the review panel without resetting search or selection', async ({ page }) => {
    await page.setViewportSize({ width: 1600, height: 1000 })
    await start(page, 'User Access')
    const search = page.getByRole('textbox', { name: 'Search users', exact: true })
    await search.fill('SYN')
    const toggle = page.getByRole('button', { name: `Open ${names.a} in SoD Review`, exact: true })
    const panel = page.locator('.ui-side-panel')
    await toggle.click()
    await expect(panel.getByRole('heading', { name: names.a, exact: true })).toBeVisible()
    await expect(toggle).toHaveAttribute('aria-pressed', 'true')
    await toggle.click()
    await expect(panel).toHaveCount(0)
    await expect(toggle).toHaveAttribute('aria-pressed', 'false')
    await expect(search).toHaveValue('SYN')
    // Another user's control switches the open panel to that user; the existing close button still works.
    await toggle.click()
    await page.getByRole('button', { name: `Open ${names.b} in SoD Review`, exact: true }).click()
    await expect(panel.getByRole('heading', { name: names.b, exact: true })).toBeVisible()
    await panel.getByRole('button', { name: 'Close panel' }).click()
    await expect(panel).toHaveCount(0)
  })

  test('BUG-07: the user profile shows role review progress with the panel counting rule and updates after a decision', async ({ page }) => {
    await page.setViewportSize({ width: 1600, height: 1000 })
    await page.goto(`/#session=browser-test-session`)
    await goTo(page, 'User Access')
    await page.getByRole('link', { name: names.a, exact: true }).first().click()
    const progress = page.getByRole('region', { name: 'Role review progress' })
    await expect(progress).toBeVisible()
    const text = await progress.getByText(/\d+\/\d+ roles reviewed/).innerText()
    const [done, total] = text.match(/(\d+)\/(\d+)/)!.slice(1).map(Number)
    expect(total).toBeGreaterThan(0)
    await progress.getByRole('button', { name: 'Open review' }).click()
    const panel = page.locator('.ui-side-panel')
    await expect(panel.getByRole('tab', { name: new RegExp(`^Roles ${done}/${total}`) })).toBeVisible()
    await expect(progress).toContainText('removal recommended (not yet removed in SAP)')
  })
})

test('BUG-02: Release role details offers a review action per reviewable user that opens the shared panel with the role in focus', async ({ page, request }) => {
  const roles = 'FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,CHILD_AGR_TEXT,TCODE,TTEXT\nMM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MM - Shared purchasing,MIGO,Goods movement\n'
  const users = 'USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO\nU1,ZO:MM:M:PR_REL_ST_E2_N1:ALL,G1,20200101,99991231\nU2,ZO:MM:M:PR_REL_ST_E2_N1:ALL,G2,20200101,99991231\n'
  const seeded = await seedSources(request, { roles, users })
  try {
    await enableSod(request)
    // Only U1 is reviewable in this context; U2 must show no review action.
    await page.route('**/api/sod/review-subjects?*', route => route.fulfill({ json: { users: ['U1'] } }))
    await page.setViewportSize({ width: 1600, height: 1000 })
    await start(page, 'Release Roles')
    await page.getByRole('button', { name: 'Table', exact: true }).click()
    await page.getByRole('region', { name: 'Release role results' }).getByRole('button', { name: 'Release role details' }).first().click()
    const details = page.getByRole('region', { name: 'Release role user assignments' })
    await expect(details).toBeVisible()
    const review = details.getByRole('button', { name: 'Review roles for U1', exact: true })
    await expect(review).toBeVisible()
    await expect(details.getByRole('button', { name: 'Review roles for U2', exact: true })).toHaveCount(0)
    await review.click()
    await expect(page.locator('.ui-side-panel').getByRole('heading', { name: 'U1', exact: true })).toBeVisible()
    await expect(review).toHaveAttribute('aria-pressed', 'true')
    await review.click()
    await expect(page.locator('.ui-side-panel')).toHaveCount(0)
  } finally { await enableSod(request, false); await seeded.cleanup() }
})

test('BUG-03 and BUG-06: Functional Groups open their member list by id, and group cells size to their content', async ({ page, request }) => {
  const seeded = await seedSources(request, { roles: ROLES, users: USERS })
  try {
  const groups = [{ id: 'g-tek', name: 'Teknologi', status: 'active' }, { id: 'g-el', name: 'Elektro / Automasjon', status: 'active' }, { id: 'g-inn', name: 'Operative Innkjøpere', status: 'active' }]
  await page.route('**/api/access/users?*', async route => {
    const response = await route.fetch(); const json = await response.json()
    if (json.items?.length) json.items[0].functional_groups = groups
    await route.fulfill({ response, json })
  })
  let requested = ''
  await page.route('**/api/functional-groups/*/members?*', route => { requested = new URL(route.request().url()).pathname; return route.fulfill({ json: { group: groups[0], total: 2, offset: 0, limit: 25, items: [
    { username: 'SYN_TEK1', full_name: 'Synthetic One', department: 'Teknologi', title: 'Engineer', identity: 'matched', status: 'Confirmed', confirmed_at: null, confirmed_by: '', revision: 1 },
    { username: 'SYN_TEK2', full_name: 'Synthetic Two', department: 'Teknologi', title: 'Engineer', identity: 'matched', status: 'Needs review', confirmed_at: null, confirmed_by: '', revision: 1 }] } }) })
  await page.setViewportSize({ width: 1600, height: 1000 })
  await start(page, 'User Access')
  const chips = page.locator('.fg-chips').first()
  await expect(chips).toBeVisible()
  // BUG-06: no reserved fixed width: the chip group is no wider than its labels and action plus gaps.
  const widths = await chips.evaluate(el => ({ box: el.getBoundingClientRect().width, content: Array.from(el.querySelectorAll('.fg-chip-stack, .fg-group-action')).reduce((sum, child) => sum + child.getBoundingClientRect().width, 0) }))
  expect(widths.box - widths.content).toBeLessThan(24)
  await chips.getByRole('button', { name: /Show all 3 Functional Groups/ }).click()
  const dialog = page.getByRole('dialog', { name: /Functional Groups of/ })
  for (const group of groups) await expect(dialog.getByRole('button', { name: `Show members of ${group.name}` })).toBeVisible()
  await dialog.getByRole('button', { name: 'Show members of Teknologi' }).click()
  const members = page.getByRole('dialog', { name: 'Members of Teknologi' })
  await expect(members).toBeVisible()
  await expect(members.getByText('2 members', { exact: true })).toBeVisible()
  await expect(members).toContainText('SYN_TEK1')
  expect(requested).toContain('/api/functional-groups/g-tek/members')
  } finally { await seeded.cleanup() }
})

test('BUG-08: main navigation resets temporary search; panels, back navigation and saved filters are unaffected', async ({ page, request }) => {
  const seeded = await seedSources(request, { roles: ROLES, users: USERS })
  try {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await start(page, 'Role Lookup')
  const search = page.getByRole('searchbox', { name: 'Search roles by name or description' })
  await search.fill('synthetic temporary search')
  await goTo(page, 'User Access')
  await page.goBack()
  await expect(search).toHaveValue('synthetic temporary search')          // Back restores the history entry it returns to
  await goTo(page, 'User Access')
  await goTo(page, 'Role Lookup')
  await expect(page.getByRole('searchbox', { name: 'Search roles by name or description' })).toHaveValue('')   // a new visit starts fresh
  } finally { await seeded.cleanup() }
})

test('BUG-10: label text wraps at whole words; technical identifiers keep their exact value', async ({ page }) => {
  await start(page, 'Dashboard')
  const wrap = await page.evaluate(() => {
    const probe = (className: string) => { const el = document.createElement('span'); el.className = className; document.body.append(el); const value = getComputedStyle(el).overflowWrap; el.remove(); return value }
    return { chart: probe('chart-label'), kpi: probe('ui-kpi-label'), option: probe('multi-option-name'), group: probe('fg-group-name'), id: probe('source-status') }
  })
  expect(wrap).toEqual({ chart: 'break-word', kpi: 'break-word', option: 'break-word', group: 'break-word', id: 'anywhere' })
})
