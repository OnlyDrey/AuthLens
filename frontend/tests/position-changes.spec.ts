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

// TBL-01 / TBL-06: shared table cell spacing and long-text containment on Position Changes.
// Realistic long department names, long job titles and an unbroken token stay strictly inside each cell's padding box with visible
// separation between adjacent columns, aligned headers and body cells, natural row-height wrapping without redundant tooltips,
// frozen SAP username, sticky top scrollbar on overflow and zero page-level horizontal overflow.
const prevDepartment = 'Group Finance Shared Services Accounts Payable and Receivable Operations'
const prevTitle = 'Senior Accounts Payable Specialist and Vendor Master Data Steward'
const longDepartment = 'International Procurement and Operational Risk Coordination for Northern Regions (EMEA-NORDIC-OPS-2026)'
const longTitle = 'Senior Regional Procurement Operations and Compliance Coordinator — SupplyChainGovernanceLead'
for (const width of [375, 800, 1024, 1280, 1600]) for (const theme of ['light', 'dark'] as const)
  test(`TBL-06 position cell spacing, containment, alignment and scroll behavior at ${width} ${theme}`, { tag: '@visual' }, async ({ page, request }) => {
    writeFileSync(csv, employees(prevDepartment, prevTitle))
    await importDirectory(request)
    writeFileSync(csv, employees(longDepartment, longTitle))
    await importDirectory(request)
    expect((await request.post('/api/configuration/theme', { headers, data: { theme } })).ok()).toBeTruthy()
    await page.setViewportSize({ width, height: 900 })
    await page.goto('/#session=browser-test-session'); await goTo(page, 'Position Changes')
    await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
    const queue = page.getByRole('region', { name: 'Position change review queue' })
    const row = queue.getByRole('row').filter({ hasText: 'DEMO_MOVER' })
    await expect(row).toContainText(longDepartment)
    await expect(row).toContainText(prevDepartment)
    const geometry = await queue.evaluate(region => {
      const table = region.querySelector('table')!
      const ths = [...table.querySelectorAll<HTMLElement>('thead th:not([hidden])')]
      const rowEl = [...table.querySelectorAll<HTMLTableRowElement>('tbody tr')].find(tr => tr.textContent?.includes('DEMO_MOVER'))!
      const tds = [...rowEl.querySelectorAll<HTMLElement>('td:not([hidden])')]
      const textBounds = (cell: HTMLElement) => {
        const range = document.createRange(); range.selectNodeContents(cell)
        const rects = [...range.getClientRects()].filter(r => r.width > 0 && r.height > 0)
        return rects.length ? { left: Math.min(...rects.map(r => r.left)), right: Math.max(...rects.map(r => r.right)) } : null
      }
      const headerMismatch = ths.map((th, i) => {
        const hb = th.getBoundingClientRect(), cb = tds[i].getBoundingClientRect()
        return Math.abs(hb.left - cb.left) > 1.5 || Math.abs(hb.width - cb.width) > 1.5 ? `${i}:${Math.round(hb.left)}/${Math.round(cb.left)}` : null
      }).filter(Boolean)
      const paddingViolations = [...ths, ...tds].filter(cell => {
        const s = getComputedStyle(cell)
        return parseFloat(s.paddingLeft) < 15.5 || parseFloat(s.paddingRight) < 15.5
      }).length
      const contentOverflow = tds.flatMap((cell, i) => {
        const box = cell.getBoundingClientRect(), s = getComputedStyle(cell)
        const minLeft = box.left + parseFloat(s.paddingLeft) - 1.5
        const maxRight = box.right - parseFloat(s.paddingRight) + 1.5
        const items = [...cell.querySelectorAll<HTMLElement>('.position-cell, .position-line, .position-label, .position-value, .evidence-badge')]
        const bad = items.filter(el => { const r = el.getBoundingClientRect(); return r.left < minLeft || r.right > maxRight || el.scrollWidth > el.clientWidth + 1.5 }).map(el => `${i}:${el.className}`)
        const tb = textBounds(cell)
        if (tb && (tb.left < minLeft || tb.right > maxRight)) bad.push(`${i}:text-bounds`)
        return bad
      })
      const adjacentGaps = tds.slice(0, -1).map((cell, i) => {
        const a = textBounds(cell), b = textBounds(tds[i + 1])
        return a && b ? Math.round(b.left - a.right) : 999
      })
      const positionWidths = tds.filter(cell => cell.querySelector('.position-cell')).map(cell => Math.round(cell.getBoundingClientRect().width))
      const wrappedValues = [...rowEl.querySelectorAll<HTMLElement>('.position-value')].map(el => {
        const range = document.createRange(); range.selectNodeContents(el)
        const lines = [...range.getClientRects()].filter(r => r.width > 0 && r.height > 0).length
        return { lines, height: Math.round(el.getBoundingClientRect().height), hasTitle: el.hasAttribute('title') }
      })
      const changed = [...rowEl.querySelectorAll<HTMLElement>('.position-line[data-changed] .position-value')].map(value => getComputedStyle(value).fontWeight)
      const labels = [...rowEl.querySelectorAll('.position-label')].map(label => label.textContent)
      const stickyHead = table.querySelector<HTMLElement>('thead [data-sticky-column="start"]')?.textContent?.trim() ?? ''
      const topBar = region.closest('.table-frame')?.querySelector<HTMLElement>('[data-testid="table-top-scroll"]')
      return {
        headerMismatch, paddingViolations, contentOverflow, adjacentGaps, positionWidths, wrappedValues, changed, labels, stickyHead,
        rowHeight: Math.round(rowEl.getBoundingClientRect().height),
        regionScrolls: region.scrollWidth > region.clientWidth + 1,
        topBarVisible: !!topBar && !topBar.hidden,
        pageOverflow: document.documentElement.scrollWidth > innerWidth + 1,
      }
    })
    expect(geometry.headerMismatch).toEqual([])
    expect(geometry.paddingViolations).toBe(0)
    expect(geometry.contentOverflow).toEqual([])
    for (const gap of geometry.adjacentGaps) expect(gap).toBeGreaterThanOrEqual(28) // >= 2 * --space-4 (32px nominal) separation
    for (const columnWidth of geometry.positionWidths) expect(columnWidth).toBeGreaterThanOrEqual(286) // 18rem readable minimum
    expect(geometry.wrappedValues.every(v => v.lines >= 2 && !v.hasTitle)).toBe(true) // wraps naturally, no redundant tooltip
    expect(geometry.rowHeight).toBeGreaterThan(80) // row grows to fit wrapped department and job title
    expect(geometry.labels).toEqual(['Department', 'Job title', 'Department', 'Job title'])
    expect(geometry.changed.length).toBeGreaterThan(0); for (const weight of geometry.changed) expect(Number(weight)).toBeGreaterThanOrEqual(700)
    expect(geometry.stickyHead).toBe('SAP username') // TBL-05 frozen username preserved
    expect(geometry.pageOverflow).toBe(false)
    if (geometry.regionScrolls) expect(geometry.topBarVisible).toBe(true) // TBL-02 sticky top scrollbar shown on overflow
    if (width < 1600) expect(geometry.regionScrolls).toBe(true)
    await expect(row.getByRole('button', { name: 'Review position change for DEMO_MOVER', exact: true })).toBeVisible()
  })
