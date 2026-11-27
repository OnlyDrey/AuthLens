import { test, expect, type Locator, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { goTo, headers, parseDelimited } from './support'
import { cleanup, seedGovernance, openSod, openReviews } from './sod-fixture'

/** TBL-04 canonical terminology and TBL-05 frozen SAP username column, asserted on geometry and the rendered labels. */
let directory = ''
test.beforeEach(async ({ request }) => { directory = await seedGovernance(request, 'static', undefined, true) })
test.afterEach(async ({ request }) => { await cleanup(request, directory) })

const LEGACY = ['SAP user', 'Username', 'Full name', 'User group', 'SAP User Group', 'Assigned role', 'Exact assigned role', 'Directory Department']
const headerTexts = (scope: Locator) => scope.locator('thead th').evaluateAll(cells => cells.map(cell => (cell.textContent || '').trim()).filter(Boolean))

test('TBL-04 tables across modules use the canonical field labels', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 900 })
  const seen: Record<string, string[]> = {}
  const visit = async (name: string, open: () => Promise<void>, table: string) => {
    await open()
    const scope = page.getByRole('table', { name: table, exact: true })
    await expect(scope).toBeVisible()
    seen[name] = await headerTexts(scope)
    expect(seen[name].filter(label => LEGACY.includes(label)), `${name} headers ${seen[name].join(', ')}`).toEqual([])
  }
  await page.goto('/#session=browser-test-session')
  await visit('Account Review', () => goTo(page, 'Account Review'), 'Account Review results')
  await visit('User Directory', () => goTo(page, 'Users'), 'User directory')
  await visit('Access Explorer', () => openSod(page, 'Access Explorer'), 'User risk table')
  await visit('Work Queue', () => openReviews(page, 'Work Queue'), 'SoD review work queue')
  // Semantically identical fields carry identical labels in every module
  for (const name of Object.keys(seen)) expect(seen[name], name).toContain('SAP username')
  expect(seen['Account Review']).toEqual(expect.arrayContaining(['Employee', 'SAP user group']))
  expect(seen['User Directory']).toEqual(expect.arrayContaining(['Employee', 'SAP user group', 'Department', 'Job title']))
  expect(seen['Access Explorer']).toContain('SAP user group')
})

test('TBL-04 renamed headers keep the saved column preferences, and report configuration shows canonical labels without changing CSV headers', async ({ page }) => {
  // A preference saved before the rename (key built from the earlier headers): the SAP User Group column hidden
  const legacyKey = 'authlens.table-columns.SAP username|Name|SAP User Group|Functional Group|Manager|SAP validity|SAP lock status|AD account status|Directory match|Review classification & evidence|Decision'
  await page.addInitScript(key => { if (!localStorage.getItem('authlens.table-columns')) localStorage.setItem('authlens.table-columns', JSON.stringify({ [key]: { order: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], hidden: [2], nowrap: true } })) }, legacyKey)
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Account Review')
  const table = page.getByRole('table', { name: 'Account Review results', exact: true })
  await expect(table.getByRole('columnheader', { name: 'Employee', exact: true })).toBeVisible()
  await expect(table.getByRole('columnheader', { name: 'SAP user group', exact: true })).toBeHidden() // the earlier preference still applies
  // Reports: the canonical label in the form, the export contract in the file
  await goTo(page, 'Review Reports')
  const report = page.getByRole('region', { name: 'Account Review report', exact: true })
  await expect(report.getByRole('checkbox', { name: 'SAP username (required)', exact: true })).toBeDisabled()
  await expect(report.getByRole('checkbox', { name: 'Employee', exact: true })).toBeVisible()
  await expect(report.getByRole('checkbox', { name: 'SAP user group', exact: true })).toBeVisible()
  const download = page.waitForEvent('download')
  await report.getByRole('button', { name: 'Generate CSV', exact: true }).click()
  const file = readFileSync((await (await download).path())!, 'utf8').replace(new RegExp(`^${String.fromCharCode(0xfeff)}`), '')
  expect(Object.keys(parseDelimited(file, ',')[0] ?? {}).slice(0, 3)).toEqual(['Username', 'User group', 'Full name']) // CSV headers unchanged
})

type Sticky = { regionLeft: number; header: { left: number; width: number }; cells: { left: number; width: number }[]; other: number; background: string; headerBackground: string; position: string; z: string }
const sticky = (region: Locator) => region.evaluate((element): Sticky => {
  const head = element.querySelector<HTMLElement>('thead [data-sticky-column="start"]')!
  const cells = [...element.querySelectorAll<HTMLElement>('tbody [data-sticky-column="start"]')].slice(0, 5)
  const other = element.querySelector<HTMLElement>('tbody tr:first-child td:not([data-sticky-column])')
  const r = element.getBoundingClientRect(), border = parseFloat(getComputedStyle(element).borderLeftWidth)
  const box = (e: HTMLElement) => { const b = e.getBoundingClientRect(); return { left: Math.round(b.left), width: Math.round(b.width) } }
  return { regionLeft: Math.round(r.left + border), header: box(head), cells: cells.map(box), other: other ? Math.round(other.getBoundingClientRect().left) : 0,
    background: getComputedStyle(cells[0]).backgroundColor, headerBackground: getComputedStyle(head).backgroundColor, position: getComputedStyle(cells[0]).position, z: getComputedStyle(cells[0]).zIndex }
})
const opaque = (color: string) => !/rgba\(.*,\s*0(\.\d+)?\)$/.test(color) && color !== 'transparent'

async function accountReview(page: Page, width: number, theme: 'light' | 'dark') {
  expect((await page.request.post('/api/configuration/theme', { headers, data: { theme } })).ok()).toBeTruthy()
  await page.setViewportSize({ width, height: 900 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Account Review')
  const region = page.getByRole('region', { name: 'Account review results', exact: true })
  await expect(region.getByRole('table')).toBeVisible()
  return region
}

for (const width of [375, 800, 1024, 1280, 1600]) for (const theme of ['light', 'dark'] as const)
  test(`TBL-05 the SAP username column stays frozen while the table scrolls at ${width} ${theme}`, { tag: '@visual' }, async ({ page }) => {
    const region = await accountReview(page, width, theme)
    const before = await sticky(region)
    expect(before.position).toBe('sticky')
    expect(opaque(before.background) && opaque(before.headerBackground), `${before.background} / ${before.headerBackground}`).toBe(true)
    expect(Math.abs(before.header.left - before.cells[0].left)).toBeLessThanOrEqual(1); expect(Math.abs(before.header.width - before.cells[0].width)).toBeLessThanOrEqual(1) // aligned
    // The identifier keeps its link and copy action inside the frozen cell
    const firstCell = region.locator('tbody tr').first().locator('[data-sticky-column="start"]')
    await expect(firstCell.getByRole('link').first()).toBeVisible()
    await expect(firstCell.getByRole('button', { name: /^Copy/ }).first()).toBeVisible()
    const overflow = await region.evaluate(element => element.scrollWidth - element.clientWidth)
    if (overflow > 40) {
      await region.evaluate(element => { element.scrollLeft = Math.min(240, element.scrollWidth) })
      await expect.poll(() => region.evaluate(element => element.scrollLeft)).toBeGreaterThan(20)
      const after = await sticky(region)
      for (const cell of [after.header, ...after.cells]) expect(Math.abs(cell.left - after.regionLeft)).toBeLessThanOrEqual(1) // frozen at the region's left edge
      expect(after.other).toBeLessThan(before.other - 20) // the other columns scrolled underneath
      // The frozen cell is on top of the cells scrolled underneath it (no bleed-through at its centre)
      const covered = await region.evaluate(element => { const cell = element.querySelector<HTMLElement>('tbody tr:first-child [data-sticky-column="start"]')!; cell.scrollIntoView({ block: 'center', inline: 'nearest' }); const b = cell.getBoundingClientRect(); const hit = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2); return !!hit && cell.contains(hit) ? true : `${hit?.tagName}.${String((hit as HTMLElement)?.className).slice(0, 60)} z=${hit ? getComputedStyle(hit).zIndex : ''} pos=${hit ? getComputedStyle(hit).position : ''} in=${hit?.closest('td,th')?.getAttribute('data-column-index')}` })
      expect(covered).toBe(true)
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
  })

test('TBL-05 only a first visible SAP username column is frozen, following column visibility and order', async ({ page }) => {
  const region = await accountReview(page, 800, 'light')
  const frozenLabel = () => region.locator('thead [data-sticky-column="start"]').allTextContents()
  expect(await frozenLabel()).toEqual(['SAP username'])
  const columns = page.getByRole('dialog', { name: 'Columns for Account Review results', exact: true })
  // Move SAP username down: the new first column (Employee) is not a username and is not frozen
  await page.getByRole('button', { name: 'Columns for Account Review results', exact: true }).click()
  await columns.getByRole('button', { name: 'Move SAP username down', exact: true }).click()
  await columns.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(region.locator('thead th').first()).toHaveText('Employee')
  expect(await frozenLabel()).toEqual([])
  // Reset restores the frozen first column
  await page.getByRole('button', { name: 'Columns for Account Review results', exact: true }).click()
  await columns.getByRole('button', { name: 'Reset columns', exact: true }).click(); await columns.getByRole('button', { name: 'Done', exact: true }).click()
  expect(await frozenLabel()).toEqual(['SAP username'])
  // Tables whose first column is not the SAP username freeze nothing (an unrelated first column is never frozen automatically)
  await openSod(page, 'Access Explorer'); await page.getByRole('tab', { name: 'Role conflicts', exact: true }).click().catch(() => undefined)
  await goTo(page, 'Release Access')
  await expect(page.getByRole('region', { name: 'Release role results', exact: true }).locator('[data-sticky-column]')).toHaveCount(0)
})
