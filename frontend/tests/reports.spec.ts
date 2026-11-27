import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { goTo, headers, mainNavigation, seedSources, type SeededSources } from './support'

/** NAV-4: the Reports module. Availability comes from the backend per report; SoD off still offers the account and access reports. */
const roles = `FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,CHILD_AGR_TEXT,TCODE,TTEXT
MM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MM - Shared purchasing,MIGO,Goods movement
`
const users = `USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO
SYN_REP_A,ZC:MM:BUY:ENP,G1,20200101,99991231
SYN_REP_B,ZC:MM:BUY:ENP,G2,20200101,99991231
`
let seeded: SeededSources
test.beforeEach(async ({ request }) => { seeded = await seedSources(request, { roles, users }) })
test.afterEach(async () => { await seeded.cleanup() })

test('Reports opens its first available page and generates configurable reports with preview', { tag: '@workflow' }, async ({ page, request }) => {
  const availability = await (await request.get('/api/reports/availability', { headers })).json()
  expect(availability.sod_enabled).toBe(false)
  expect(availability.pages).toEqual(['review', 'access'])
  await page.goto('/#session=browser-test-session')
  await expect(mainNavigation(page).getByRole('link')).toHaveText(['Dashboard', 'Role Lookup', 'Users', 'Reviews', 'Reports'])
  await mainNavigation(page).getByRole('link', { name: 'Reports', exact: true }).click()
  await expect(page).toHaveURL(/#\/reports\/review$/) // Review Reports is the default landing page
  const views = page.getByRole('navigation', { name: 'Report views', exact: true })
  await expect(views.getByRole('link')).toHaveText(['Review Reports', 'Access Reports']) // SoD reports and Evidence follow the SoD switch
  // Account Review: columns with the required username, a preview of the matching rows and a download.
  const review = page.getByRole('region', { name: 'Account Review report', exact: true })
  await expect(review.getByRole('checkbox', { name: 'SAP username (required)', exact: true })).toBeDisabled()
  await review.getByRole('checkbox', { name: 'Employee', exact: true }).uncheck()
  await review.getByRole('button', { name: 'Preview', exact: true }).click()
  await expect(review.getByRole('status')).toContainText('2 rows match')
  await expect(review.getByRole('table', { name: 'Account Review preview' }).getByRole('columnheader').first()).toHaveText('SAP username')
  await expect(review.getByRole('table', { name: 'Account Review preview' }).getByRole('columnheader', { name: 'Employee', exact: true })).toHaveCount(0)
  const download = page.waitForEvent('download')
  await review.getByRole('button', { name: 'Generate CSV', exact: true }).click()
  expect((await download).suggestedFilename()).toMatch(/^authlens-account-review-review-\d{4}-\d{2}-\d{2}\.csv$/)
  // Position Changes is listed with the reason it is not available (no Employee Directory import).
  await expect(page.getByRole('region', { name: 'Position Changes report', exact: true })).toContainText('Employee Directory')
  // Access Reports: Compare Users needs both users before it can run.
  await views.getByRole('link', { name: 'Access Reports', exact: true }).click()
  const compare = page.getByRole('region', { name: 'Compare Users report', exact: true })
  await expect(compare.getByRole('button', { name: 'Generate CSV', exact: true })).toBeDisabled()
  await compare.getByRole('textbox', { name: 'User A', exact: true }).fill('SYN_REP_A')
  await compare.getByRole('textbox', { name: 'User B', exact: true }).fill('SYN_REP_B')
  await compare.getByRole('button', { name: 'Preview', exact: true }).click()
  await expect(compare.getByRole('status')).toContainText('2 rows match') // one shared role, one assignment row per user
  // A page the account may not use resolves to an available one.
  await page.goto('/#/reports/sod')
  await expect(page).toHaveURL(/#\/reports\/review$/)
})

// #35: Access Reports offers the same export scope as the User Directory, on the same endpoint; preview and file agree.
test('User Directory report exports matching role assignments or all assignments of the matching users', { tag: '@workflow' }, async ({ page, request }) => {
  await seeded.cleanup()
  seeded = await seedSources(request, { roles: `${roles}FI,ZC:FI:B,Beta,ZS:B,FI - Accounting,FB03,Display document\n`, users: `${users}SYN_REP_A,ZC:FI:B,G1,20200101,99991231\nSYN_REP_C,ZC:FI:B,G1,20200101,99991231\n` })
  await page.goto('/#session=browser-test-session')
  await goTo(page, 'Access Reports')
  const report = page.getByRole('region', { name: 'User Directory report', exact: true })
  await report.getByRole('textbox', { name: 'Role', exact: true }).fill('ZC:MM:BUY:ENP')
  const scope = report.getByLabel('Assignment rows', { exact: true })
  await expect(scope).toHaveValue('matching')
  await report.getByRole('button', { name: 'Preview', exact: true }).click()
  await expect(report.getByRole('status')).toContainText('2 rows match') // SYN_REP_A and SYN_REP_B, the role only
  await scope.selectOption('all_assignments')
  await report.getByRole('button', { name: 'Preview', exact: true }).click()
  await expect(report.getByRole('status')).toContainText('3 rows match') // plus SYN_REP_A's other role; SYN_REP_C is outside the population
  const download = page.waitForEvent('download')
  await report.getByRole('button', { name: 'Generate CSV', exact: true }).click()
  const file = await download
  const lines = readFileSync((await file.path())!, 'utf8').replace(new RegExp(`^${String.fromCharCode(0xfeff)}`), '').trim().split(/\r?\n/).slice(1)
  expect(lines).toHaveLength(3)
  expect(lines.some(line => line.includes('SYN_REP_C'))).toBe(false)
  expect(lines.filter(line => line.includes('ZC:FI:B'))).toHaveLength(1)
})

test('legacy report routes open Review Reports and Goto opens the first available page', async ({ page }) => {
  await page.goto('/#session=browser-test-session')
  await goTo(page, 'Access Reports')
  await expect(page).toHaveURL(/#\/reports\/access$/)
  await page.goto('/#/reviews/reports')
  await expect(page).toHaveURL(/#\/reports\/review$/)
  await page.goto('/#/reports')
  await expect(page).toHaveURL(/#\/reports\/review$/)
})
