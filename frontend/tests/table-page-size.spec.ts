import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { goTo, parseDelimited, seedSources, type SeededSources } from './support'

/** TBL-03 standard results per page: geometry-free interaction checks on the User Directory and Account Review, backed by the server. */
const NL = String.fromCharCode(10)
const roles = ['FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE', 'MM,ZC:MM:A,Alpha,ZS:A,T01', ''].join(NL)
const users = ['USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO',
  ...Array.from({ length: 30 }, (_, index) => `PS${String(index + 1).padStart(2, '0')},ZC:MM:A,G1,20200101,99991231`), ''].join(NL)
let seeded: SeededSources
test.beforeEach(async ({ request }) => { seeded = await seedSources(request, { roles, users }) })
test.afterEach(async () => { await seeded.cleanup() })

const directory = (page: Page) => page.getByRole('region', { name: 'User directory table', exact: true })
const rows = (page: Page) => directory(page).locator('tbody tr')
const range = (page: Page) => page.getByRole('navigation', { name: 'User pages', exact: true }).getByRole('status')
const size = (page: Page) => page.getByRole('combobox', { name: 'User pages: rows per page', exact: true })

test('TBL-03 the page size is standard, server side, remembered per table and resets the page', async ({ page }) => {
  const limits: string[] = []
  page.on('request', request => { const url = new URL(request.url()); if (url.pathname === '/api/access/users') limits.push(url.searchParams.get('limit') ?? '') })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  await expect(size(page).locator('option')).toHaveText(['10', '25', '50', '100', '250'])
  await expect(size(page)).toHaveValue('25')
  await expect(rows(page)).toHaveCount(25); await expect(range(page)).toHaveText('1–25 of 30')
  // The selector sits in the table toolbar with the Columns control, above the table
  const [control, columns, table] = [(await size(page).boundingBox())!, (await page.getByRole('button', { name: 'Columns for User directory', exact: true }).boundingBox())!, (await directory(page).boundingBox())!]
  expect(Math.abs(control.y + control.height / 2 - (columns.y + columns.height / 2))).toBeLessThan(12); expect(control.y + control.height).toBeLessThanOrEqual(table.y + 1)
  await page.getByRole('navigation', { name: 'User pages', exact: true }).getByRole('button', { name: 'Next' }).click()
  await expect(range(page)).toHaveText('26–30 of 30')
  await size(page).selectOption('10') // a new page size starts at the first page
  await expect(range(page)).toHaveText('1–10 of 30'); await expect(rows(page)).toHaveCount(10)
  expect(limits.at(-1)).toBe('10') // paged by the server
  await size(page).selectOption('250')
  await expect(rows(page)).toHaveCount(30); expect(limits.at(-1)).toBe('250')
  await size(page).selectOption('10')
  // A filter change returns to the first page
  await page.getByRole('navigation', { name: 'User pages', exact: true }).getByRole('button', { name: 'Next' }).click()
  await expect(range(page)).toHaveText('11–20 of 30')
  await page.getByLabel('Search users', { exact: true }).fill('PS1')
  await expect(range(page)).toHaveText(/^1–/)
  await page.getByLabel('Search users', { exact: true }).fill('')
  // Remembered for this table across a reload; other tables keep their own size
  await page.reload(); await goTo(page, 'Users')
  await expect(size(page)).toHaveValue('10'); await expect(rows(page)).toHaveCount(10)
  await goTo(page, 'Account Review')
  await expect(page.getByRole('combobox', { name: 'Account review pages: rows per page', exact: true })).toHaveValue('25')
})

test('TBL-03 sorting, export and selection work on the complete matching population, not the page', async ({ page }) => {
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  await size(page).selectOption('10')
  // Sorting is applied by the server to every matching user: descending starts with the last username of all 30
  await page.getByRole('button', { name: 'Ascending order, switch to descending', exact: true }).click()
  await expect(rows(page).first()).toContainText('PS30')
  // Export scope is independent of the page size
  const download = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Export CSV', exact: true }).click()
  const file = readFileSync((await (await download).path())!, 'utf8').replace(new RegExp(`^${String.fromCharCode(0xfeff)}`), '')
  expect(new Set(parseDelimited(file, ';').map(row => row.USERNAME)).size).toBe(30)
  // Page selection and full-result selection stay distinct
  await page.getByRole('checkbox', { name: 'Select all users on this page', exact: true }).check()
  await expect(page.getByRole('heading', { name: /User directory/ })).toContainText('10 selected')
  await page.getByRole('button', { name: 'Select all 30 matching', exact: true }).click()
  await expect(page.getByRole('heading', { name: /User directory/ })).toContainText('30 selected')
})
