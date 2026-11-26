import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { cleanup, decide, names, openReviews, seedGovernance } from './sod-fixture'
import { headers } from './support'

// Configurable Work Queue export. Fixture: SYN_A has several role assignments; SYN_B has a conflict through one role.
let directory: string
test.beforeEach(async ({ request }) => { directory = await seedGovernance(request) })
test.afterEach(async ({ request }) => { await cleanup(request, directory) })

type Item = { key: string; user: string; ref: string; evidence_version: string; kind: string }
async function openExport(page: Page) {
  await page.goto('/#session=browser-test-session')
  await page.evaluate(() => localStorage.removeItem('authlens-queue-export'))
  await openReviews(page, 'Work Queue')
  await page.getByRole('button', { name: 'Export CSV', exact: true }).click()
  return page.getByRole('dialog', { name: 'Export review CSV', exact: true })
}
async function download(page: Page, dialog: ReturnType<Page['getByRole']>) {
  const waiting = page.waitForEvent('download')
  await dialog.getByRole('button', { name: 'Export', exact: true }).click()
  const file = await waiting
  return { name: file.suggestedFilename(), text: readFileSync((await file.path())!, 'utf8').replace(/^\ufeff/, '') }
}

test('the role removal preset exports only the exact roles decided Remove, as SAP username and role name', async ({ page, request }) => {
  const assignments = (await (await request.get('/api/sod/queue', { headers, params: { context: 'current', kind: 'assignment', limit: 200 } })).json()).items as Item[]
  const mine = assignments.filter(item => item.user === names.a)
  const roles = [...new Set(mine.map(item => item.ref))]
  expect(roles.length).toBeGreaterThanOrEqual(3)
  const keep = mine.find(item => item.ref === roles[0])!, remove = mine.filter(item => item.ref === roles[1])
  await decide(request, 'assignment', 'current', [{ key: keep.key, user: keep.user, ref: keep.ref, evidence_version: keep.evidence_version }], 'Keep')
  await decide(request, 'assignment', 'current', remove.map(item => ({ key: item.key, user: item.user, ref: item.ref, evidence_version: item.evidence_version })), 'Remove')
  const activity = ((await (await request.get('/api/sod/queue', { headers, params: { context: 'current', kind: 'activity', limit: 200 } })).json()).items as Item[]).find(item => item.user === names.b)!
  await decide(request, 'activity', 'current', [{ key: activity.key, user: activity.user, ref: activity.ref, evidence_version: activity.evidence_version }], 'Remove')
  const dialog = await openExport(page)
  await expect(dialog.getByRole('combobox', { name: 'Export preset', exact: true })).toHaveValue('role_removal')
  // Preview and file use the same rule: USER / ROLE_B only (not the kept or pending roles, not SYN_B's activity removal).
  await expect(dialog.getByRole('status', { name: 'Export preview counts' })).toContainText('1 role assignments for 1 user')
  await expect(dialog.getByRole('region', { name: 'Export preview rows' })).toContainText(roles[1])
  const file = await download(page, dialog)
  expect(file.name).toMatch(/^authlens-sod-role-removal-\d{4}-\d{2}-\d{2}\.csv$/)
  expect(file.text).toBe(`SAP username;Role name\r\n${names.a};${roles[1]}\r\n`)
})

test('custom columns keep their order, the comma delimiter applies, the configuration is remembered and no columns disables export', async ({ page }) => {
  const dialog = await openExport(page)
  await dialog.getByRole('combobox', { name: 'Export preset', exact: true }).selectOption('pending')
  await expect(dialog.getByRole('status', { name: 'Export preview counts' })).toContainText('review items')
  await dialog.getByRole('button', { name: 'Move Review item up', exact: true }).click()
  await dialog.getByRole('combobox', { name: 'CSV delimiter', exact: true }).selectOption('comma')
  const order = dialog.getByRole('list', { name: 'Column order', exact: true }).getByRole('listitem')
  await expect(order).toHaveText([/1\. SAP username/, /2\. Review item/, /3\. Review type/, /4\. Review status/])
  const file = await download(page, dialog)
  expect(file.name).toMatch(/^authlens-sod-review-items-/)
  expect(file.text.split('\r\n')[0]).toBe('SAP username,Review item,Review type,Review status')
  expect(file.text.split('\r\n').filter(line => line).slice(1).every(line => /,(Pending|Outdated|Investigate)$/.test(line))).toBe(true)
  // Remembered for the next export; Clear leaves nothing to export.
  await page.getByRole('button', { name: 'Export CSV', exact: true }).click()
  const again = page.getByRole('dialog', { name: 'Export review CSV', exact: true })
  await expect(again.getByRole('combobox', { name: 'CSV delimiter', exact: true })).toHaveValue('comma')
  await again.getByRole('button', { name: 'Clear', exact: true }).click()
  await expect(again.getByRole('button', { name: 'Export', exact: true })).toBeDisabled()
  await expect(again.getByRole('alert')).toContainText('Select at least one column')
  await again.getByRole('button', { name: 'Cancel', exact: true }).click()
  await expect(again).toHaveCount(0)
})
