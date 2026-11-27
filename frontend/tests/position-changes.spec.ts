import {expectReviewerProfile} from './reviewer-profile'
import { test, expect, type APIRequestContext } from '@playwright/test'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { headers, goTo, postConfiguration } from './support'
const columns = 'Site;Name;SamAccountName;UserPrincipalName;Mail;Department;Title;Enabled;DistinguishedName;ManagerDN;ManagerName;ManagerSamAccountName;ManagerMail;ManagerDepartment;ManagerTitle;ManagerLookupStatus'
const employees = (department: string, title: string, manager = 'Demo Manager') =>
  '﻿' + columns + '\n' +
  `North;Demo Mover;demo_mover;;mover@example.test;${department};${title};true;;;${manager};demo_manager;manager@example.test;Operations;Lead;Resolved\n` +
  'North;Demo Stayer;demo_stayer;;stayer@example.test;Finance;Accountant;true;;;;;;;;\n'
let directory: string, csv: string

const settings = async (request: APIRequestContext) => (await (await request.get('/api/configuration', { headers })).json()).settings
async function importDirectory(request: APIRequestContext) {
  const revision = (await settings(request)).revision
  const preview = await request.post('/api/employees/preview', { headers, data: { path: csv, revision } })
  expect(preview.ok()).toBeTruthy()
  expect((await request.post('/api/employees/import', { headers, data: { path: csv, revision, digest: (await preview.json()).digest } })).ok()).toBeTruthy()
}
test.beforeEach(async ({ request }) => {
  await request.post('/api/configuration/reset', { headers })
  directory = mkdtempSync(path.join(tmpdir(), 'authlens-position-'))
  csv = path.join(directory, 'employees.csv')
  const users = path.join(directory, 'users.csv')
  writeFileSync(users, 'USERNAME,ROLE_NAME,EMAIL,USER_GROUP,USER_VALID_FROM,USER_VALID_TO,ROLE_VALID_FROM,ROLE_VALID_TO\n' +
    'DEMO_MOVER,ZC:FI:VIEW,mover@example.test,DEMO,20200101,99991231,20200101,99991231\nDEMO_STAYER,ZC:FI:VIEW,stayer@example.test,DEMO,20200101,99991231,20200101,99991231\n')
  const current = await settings(request)
  current.data_csv_path = path.resolve('tests/fixtures/role-catalogue-minimal.csv'); current.user_csv_path = users
  current.features.employee_directory = true
  expect((await postConfiguration(request, current)).ok()).toBeTruthy()
  writeFileSync(csv, employees('Finance', 'Accountant'))
  await importDirectory(request)
})
test.afterEach(async ({ request }) => {
  await request.post('/api/configuration/reset', { headers })
  rmSync(directory, { recursive: true, force: true })
})
test('manager-only and formatting-only directory changes are not position changes', async ({ page, request }) => {
  writeFileSync(csv, employees(' finance ', 'ACCOUNTANT', 'Another Manager'))
  await importDirectory(request)
  await page.goto('/#session=browser-test-session')
  const tile = page.getByRole('region', { name: 'Directory & Data Health', exact: true }).getByRole('button', { name: 'Position changes', exact: true })
  await expect(tile).toContainText('0')
})

test('a department change is a priority review on the dedicated Position Changes page, using the existing Account Review decision', async ({ page, request }) => {
  writeFileSync(csv, employees('Procurement', 'Account Lead'))
  await importDirectory(request)
  await page.goto('/#session=browser-test-session')
  const tile = page.getByRole('region', { name: 'Directory & Data Health', exact: true }).getByRole('button', { name: 'Position changes', exact: true })
  await expect(tile).toContainText('1')
  await tile.click()
  await expect(page).toHaveURL(/#\/reviews\/position-changes$/)
  await expect(page.getByRole('heading', { name: 'Position Changes', level: 2 })).toBeVisible()
  const kpis = page.getByRole('region', { name: 'Position change key figures', exact: true })
  for (const [label, value] of [['Position changes', '1'], ['Department changes', '1'], ['Job title changes', '1'], ['Pending review', '1']]) await expect(kpis.getByRole('button', { name: new RegExp(`^${label}`) })).toContainText(value)
  await expect(page.getByText('changed both', { exact: false })).toContainText('1 changed both')   // department and job title overlap
  const queue = page.getByRole('region', { name: 'Position change review queue' })
  const row = queue.getByRole('row').filter({ hasText: 'DEMO_MOVER' })
  for (const name of ['Change type', 'Previous position', 'Current position', 'Priority', 'Review status']) await expect(queue.getByRole('columnheader', { name, exact: true })).toBeVisible()
  await expect(row.getByRole('cell').nth(2)).toHaveText('Department and job title')
  const [previous, current] = [row.getByRole('cell').nth(3), row.getByRole('cell').nth(4)]
  await expect(previous).toContainText('Finance'); await expect(current).toContainText('Procurement')
  await expect(current.locator('.position-line[data-changed]')).toHaveCount(2)
  await expect(row).toContainText('High'); await expect(row).toContainText('Pending review')
  await expect(queue.getByRole('row').filter({ hasText: 'DEMO_STAYER' })).toHaveCount(0)
  await expect(row.getByRole('link', { name: 'Open SAP user DEMO_MOVER' })).toHaveAttribute('href', '#/users/user/DEMO_MOVER')
  // The long explanation is contextual help, not page text.
  await expect(page.getByText('not evidence that access is inappropriate')).toHaveCount(0)
  await page.getByRole('button', { name: 'About position changes' }).click()
  await expect(page.getByText(/not evidence that access is inappropriate/)).toBeVisible()
  await page.keyboard.press('Escape')
  // Filters: change type and search.
  const filters = page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^(Hide )?[Ff]ilters/ })
  if ((await filters.getAttribute('aria-expanded')) !== 'true') await filters.click()
  const sidebar = page.getByRole('complementary', { name: 'Filters', exact: true })
  await sidebar.getByRole('combobox', { name: 'Change type', exact: true }).selectOption('department')
  await expect(row).toBeVisible()
  await sidebar.getByRole('searchbox', { name: 'Search position changes' }).fill('no-such-user')
  await expect(page.getByText('No position changes match the selected filters.')).toBeVisible()
  await sidebar.getByRole('searchbox', { name: 'Search position changes' }).fill('')
  // Review through the shared Account Review dialog, decision and history.
  await row.getByRole('button', { name: 'Review position change for DEMO_MOVER' }).click()
  const dialog = page.getByRole('dialog', { name: 'Review account · DEMO_MOVER' })
  for (const name of ['SAP identity', 'Review decision']) await expect(dialog.getByRole('region', { name, exact: true })).toBeVisible()
  await expect(dialog.getByRole('heading', { name: 'Organizational position changes' })).toBeVisible()
  await expectReviewerProfile(dialog.getByLabel('Reviewer', { exact: true }))
  await dialog.getByLabel('Rationale', { exact: true }).fill('Move confirmed with the line manager.')
  await dialog.getByLabel('Decision', { exact: true }).selectOption('No action required')
  await dialog.getByRole('button', { name: /Save/ }).click()
  await expect(dialog).toHaveCount(0)
  await expect(kpis.getByRole('button', { name: /^Pending review/ })).toContainText('0')
  await expect(kpis.getByRole('button', { name: /^Position changes/ })).toContainText('1')   // still detected, now reviewed
  await sidebar.getByRole('combobox', { name: 'Review status', exact: true }).selectOption('reviewed')
  await expect(queue.getByRole('row').filter({ hasText: 'DEMO_MOVER' })).toContainText('Reviewed')
  // Account Review keeps the metric (it now opens this page) and no longer shows the table.
  await page.goto('/#/reviews/account-review')
  await expect(page.getByRole('region', { name: 'Position changes priority queue' })).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Position change review queue' })).toHaveCount(0)
  const metric = page.getByRole('region', { name: 'Review attention', exact: true }).getByRole('button', { name: /^Position changes/ })
  await expect(metric).toContainText('0')
  await metric.click()
  await expect(page).toHaveURL(/#\/reviews\/position-changes$/)
  await expect(page.getByText('No position change is waiting for review.')).toBeVisible()
  await goTo(page, 'Dashboard')
  await expect(page.getByRole('region', { name: 'Directory & Data Health', exact: true }).getByRole('button', { name: 'Position changes', exact: true })).toContainText('0')
})

test('the Position Changes page is a Reviews navigation item and opens directly by URL and after a reload', async ({ page }) => {
  await page.goto('/#session=browser-test-session')
  await page.goto('/#/reviews/position-changes')
  await expect(page.getByRole('heading', { name: 'Position Changes', level: 2 })).toBeVisible()
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Position Changes', level: 2 })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Position Changes', exact: true }).first()).toHaveAttribute('aria-current', 'page')
  // Directory history survives the configuration reset, so an earlier test may leave a change: the page shows its table or the empty state.
  await expect(page.getByRole('region', { name: 'Position change review queue' }).or(page.getByText('No position change is waiting for review.'))).toBeVisible()
})

// TBL-01 (RC7 manual acceptance): the position columns kept a zero minimum width (grid minmax(0,1fr) under the table's one-line values), so long
// departments and job titles overflowed into Priority and Review status. Geometry: every value stays inside its own cell, the position columns
// keep their readable minimum, the changed value stays emphasised, and only the table region (never the page) scrolls horizontally.
const longDepartment = 'International Procurement and Operational Risk Coordination for Northern Regions'
const longTitle = 'Senior Regional Procurement Operations and Compliance Coordinator'
for (const width of [375, 800, 1024, 1280, 1600]) for (const theme of ['light', 'dark'] as const)
  test(`TBL-01 position values stay inside their columns with long text at ${width} ${theme}`, { tag: '@visual' }, async ({ page, request }) => {
    writeFileSync(csv, employees(longDepartment, longTitle))
    await importDirectory(request)
    expect((await request.post('/api/configuration/theme', { headers, data: { theme } })).ok()).toBeTruthy()
    await page.setViewportSize({ width, height: 900 })
    await page.goto('/#session=browser-test-session'); await goTo(page, 'Position Changes')
    await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
    const queue = page.getByRole('region', { name: 'Position change review queue' })
    const row = queue.getByRole('row').filter({ hasText: 'DEMO_MOVER' })
    await expect(row).toContainText(longDepartment)
    const geometry = await row.evaluate(element => {
      const cells = [...element.querySelectorAll<HTMLElement>('td')]
      const outside = cells.flatMap((cell, index) => {
        const box = cell.getBoundingClientRect()
        return [...cell.querySelectorAll<HTMLElement>('.position-line, .position-label, .position-value, .evidence-badge')]
          .filter(item => { const r = item.getBoundingClientRect(); return r.left < box.left - 1 || r.right > box.right + 1 || item.scrollWidth > item.clientWidth + 1 }).map(item => `${index}:${item.className}`)
      })
      const position = cells.filter(cell => cell.querySelector('.position-cell')).map(cell => Math.round(cell.getBoundingClientRect().width))
      const changed = [...element.querySelectorAll<HTMLElement>('.position-line[data-changed] .position-value')].map(value => getComputedStyle(value).fontWeight)
      const labels = [...element.querySelectorAll('.position-label')].map(label => label.textContent)
      const region = element.closest<HTMLElement>('[role="region"]')!
      return { outside, position, changed, labels, regionScrolls: region.scrollWidth > region.clientWidth, pageOverflow: document.documentElement.scrollWidth > innerWidth + 1 }
    })
    expect(geometry.outside).toEqual([]) // no value overflows into a neighbouring column
    for (const columnWidth of geometry.position) expect(columnWidth).toBeGreaterThanOrEqual(239) // 15rem readable minimum
    expect(geometry.labels).toEqual(['Department', 'Job title', 'Department', 'Job title'])
    expect(geometry.changed.length).toBeGreaterThan(0); for (const weight of geometry.changed) expect(Number(weight)).toBeGreaterThanOrEqual(700)
    expect(geometry.pageOverflow).toBe(false)
    if (width < 1280) expect(geometry.regionScrolls).toBe(true) // the table scrolls inside its region instead of squeezing the columns
    await expect(row.getByRole('button', { name: 'Review position change for DEMO_MOVER', exact: true })).toBeVisible()
  })
