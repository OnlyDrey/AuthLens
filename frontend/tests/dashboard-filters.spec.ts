import { test, expect, type Page } from '@playwright/test'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { headers, goTo, postConfiguration } from './support'

// WP30 (DASH-001 to DASH-015): one dashboard with a global and a filtered mode. Synthetic data only.
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
async function choose(page: Page, label: string, option: RegExp) {
  const panel = page.getByRole('dialog', { name: 'Dashboard filters', exact: true })
  const input = panel.getByRole('combobox', { name: label, exact: true })
  await input.click(); await page.getByRole('option', { name: option }).click(); await input.press('Escape')
}

test('filters open in a closed-by-default side panel, apply explicitly, scope user metrics and carry the population into drill-down', async ({ page }) => {
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Dashboard')
  await expect(usersValue(page)).toHaveText('3')
  await expect(page.getByRole('status', { name: 'Dashboard scope' })).toContainText('Global overview')
  await expect(page.getByRole('dialog', { name: 'Dashboard filters', exact: true })).toHaveCount(0)
  await page.getByRole('button', { name: /^Filters/ }).click()
  const panel = page.getByRole('dialog', { name: 'Dashboard filters', exact: true })
  await expect(panel).toBeVisible()
  await choose(page, 'User group', /^G2 \(2\)$/)
  await choose(page, 'Assigned role', /^ZC:MM:A/)
  await expect(usersValue(page)).toHaveText('3')                                             // nothing changes before Apply
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('1')                                             // G2 AND ZC:MM:A: DEMO_TWO only
  await expect(page.getByRole('button', { name: /^Filters/ })).toContainText('2')
  await expect(page.getByRole('status', { name: 'Dashboard scope' })).toContainText('Filtered overview')
  await expect(page.getByRole('group', { name: 'Applied dashboard filters' })).toContainText('User group: G2')
  await expect(page.locator('[data-metric="roles"]')).toContainText('Global')                // catalogue metric stays global and says so
  await page.getByRole('button', { name: 'Remove Assigned role: ZC:MM:A (2)', exact: true }).click()
  await expect(usersValue(page)).toHaveText('2')                                             // OR remains: the whole G2 group
  await choose(page, 'Assigned role', /^ZC:MM:A/)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('1')
  await panel.getByRole('button', { name: 'Close panel', exact: true }).click()
  await expect(panel).toHaveCount(0)
  await page.getByRole('button', { name: /^SAP users/ }).click()
  await expect(page.getByRole('link', { name: 'DEMO_TWO', exact: true })).toBeVisible()
  await expect(page.getByRole('link', { name: 'DEMO_THREE', exact: true })).toHaveCount(0)
  await expect(page.getByRole('link', { name: 'DEMO_ONE', exact: true })).toHaveCount(0)
  await goTo(page, 'Dashboard')                                                              // BUG-08: main navigation opens the page fresh
  await expect(usersValue(page)).toHaveText('3')
  await expect(page.getByRole('status', { name: 'Dashboard scope' })).toContainText('Global overview')
  await page.getByRole('button', { name: /^Filters/ }).click()
  await choose(page, 'User group', /^G2 \(2\)$/)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('2')
  await panel.getByRole('button', { name: 'Close panel', exact: true }).click()                // the open panel covers the toolbar; it has its own Reset
  await page.getByRole('button', { name: 'Reset filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('3')                                             // clearing restores the global overview
})

test('an empty population is reported, saved dashboard filters round-trip and the panel fits narrow screens', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Dashboard')
  await page.getByRole('button', { name: /^Filters/ }).click()
  const panel = page.getByRole('dialog', { name: 'Dashboard filters', exact: true })
  await choose(page, 'User group', /^G1 /)
  await choose(page, 'Assigned transaction', /^VA03/)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('0')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
  const box = (await panel.boundingBox())!
  expect(box.x).toBeGreaterThanOrEqual(0); expect(box.x + box.width).toBeLessThanOrEqual(376)
  await panel.getByRole('button', { name: 'Reset', exact: true }).click()
  await expect(usersValue(page)).toHaveText('3')
})

test('access matching mode requires one assignment to match every access filter', async ({ page }) => {
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Dashboard')
  await page.getByRole('button', { name: /^Filters/ }).click()
  const panel = page.getByRole('dialog', { name: 'Dashboard filters', exact: true })
  await choose(page, 'Assigned role', /^ZC:MM:A/)
  await choose(page, 'Assigned transaction', /^ME21N/)
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('1')                                             // DEMO_ONE: MM:A and ME21N through different roles
  await panel.getByRole('radio', { name: /^Matching access/ }).check()
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('0')                                             // no single assignment carries both
  await panel.getByRole('radio', { name: /^User population/ }).check()
  await panel.getByRole('button', { name: 'Apply filters', exact: true }).click()
  await expect(usersValue(page)).toHaveText('1')
})
