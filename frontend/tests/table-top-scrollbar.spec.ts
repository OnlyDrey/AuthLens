import { test, expect, type Locator, type Page } from '@playwright/test'
import { goTo, headers, seedSources, type SeededSources } from './support'

/** TBL-02 shared sticky top horizontal scrollbar (TableRegion): geometry and interaction, not screenshots. */
const roles = `FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE
MM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MIGO
`
// 40 strategy keys: the Release Access matrix is wider than any viewport; 80 users make the User Directory taller than the viewport
const keys = ['S', 'T', 'U', 'V'].flatMap(letter => Array.from({ length: 10 }, (_, digit) => `${letter}${digit}`))
const users = 'USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO\n'
  + keys.map((key, index) => `TS${String(index).padStart(2, '0')},ZO:MM:M:${index % 2 ? 'PO' : 'PR'}_REL_ST_E${index % 3}_${key}:ALL,G1,20200101,99991231`).join('\n') + '\n'
  + Array.from({ length: 80 }, (_, index) => `TALL${String(index).padStart(2, '0')},ZC:MM:BUY:ENP,G2,20200101,99991231`).join('\n') + '\n'
const few = `USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO
U1,ZO:MM:M:PR_REL_ST_E2_N1:ALL,G1,20200101,99991231
`
let seeded: SeededSources
test.afterEach(async () => { await seeded.cleanup() })

const frameOf = (region: Locator) => region.locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " table-frame ")][1]')
type Geometry = { overflow: boolean; barVisible: boolean; barTop: number; barBottom: number; barLeft: number; barWidth: number; regionTop: number; regionLeft: number; regionWidth: number;
  toolbarBottom: number | null; barRange: number; regionRange: number; bottomBar: number; vertical: boolean; headerBottom: number; pageOverflow: boolean }
const measure = (region: Locator) => region.evaluate((element): Geometry => {
  const frame = element.closest('.table-frame')!, bar = frame.querySelector<HTMLElement>('.table-top-scroll')!, toolbar = frame.querySelector('.table-presentation-controls')
  const r = element.getBoundingClientRect(), b = bar.getBoundingClientRect(), style = getComputedStyle(element)
  const borders = parseFloat(style.borderTopWidth) + parseFloat(style.borderBottomWidth)
  return {
    overflow: element.scrollWidth > element.clientWidth + 1, barVisible: !bar.hidden && b.height > 0, barTop: b.top, barBottom: b.bottom, barLeft: b.left, barWidth: b.width,
    regionTop: r.top, regionLeft: r.left, regionWidth: r.width, toolbarBottom: toolbar ? toolbar.getBoundingClientRect().bottom : null,
    barRange: bar.scrollWidth - bar.clientWidth, regionRange: element.scrollWidth - element.clientWidth,
    bottomBar: Math.round(element.offsetHeight - element.clientHeight - borders), vertical: element.scrollHeight > element.clientHeight + 1,
    headerBottom: document.querySelector('header[role="banner"]')!.getBoundingClientRect().bottom, pageOverflow: document.documentElement.scrollWidth > innerWidth + 1,
  }
})
const expectTopScrollbar = (g: Geometry) => {
  expect(g.overflow).toBe(true)
  expect(g.barVisible).toBe(true)
  expect(g.barBottom).toBeLessThanOrEqual(g.regionTop + 1) // above the table header ...
  if (g.toolbarBottom !== null) expect(g.barTop).toBeGreaterThanOrEqual(g.toolbarBottom - 1) // ... directly below the table toolbar
  expect(Math.abs(g.barLeft - g.regionLeft)).toBeLessThanOrEqual(1); expect(Math.abs(g.barWidth - g.regionWidth)).toBeLessThanOrEqual(1)
  expect(Math.abs(g.barRange - g.regionRange)).toBeLessThanOrEqual(1) // one scroll range
  if (!g.vertical) expect(g.bottomBar).toBe(0) // the region's own horizontal scrollbar is replaced, not duplicated
  expect(g.pageOverflow).toBe(false)
}
const scrollBar = (region: Locator, left: number) => region.evaluate((element, left) => { const bar = element.closest('.table-frame')!.querySelector<HTMLElement>('.table-top-scroll')!; bar.scrollLeft = left }, left)
const positions = (region: Locator) => region.evaluate(element => ({ region: Math.round(element.scrollLeft), bar: Math.round(element.closest('.table-frame')!.querySelector<HTMLElement>('.table-top-scroll')!.scrollLeft) }))

async function openMatrix(page: Page, width: number, theme: 'light' | 'dark', data = users) {
  seeded = await seedSources(page.request, { roles, users: data })
  expect((await page.request.post('/api/configuration/theme', { headers, data: { theme } })).ok()).toBeTruthy()
  await page.setViewportSize({ width, height: 800 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Release Access')
  await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
  await page.getByRole('button', { name: 'Matrix', exact: true }).click()
  const region = page.getByRole('region', { name: 'release matrix scroll area', exact: true })
  await expect(region.getByRole('table', { name: 'release matrix', exact: true })).toBeVisible()
  return region
}

for (const width of [375, 800, 1024, 1280, 1600]) for (const theme of ['light', 'dark'] as const)
  test(`TBL-02 the top scrollbar mirrors a wide matrix in both directions at ${width} ${theme}`, { tag: '@visual' }, async ({ page }) => {
    const region = await openMatrix(page, width, theme)
    const g = await measure(region); expectTopScrollbar(g)
    // top scrollbar -> region
    await scrollBar(region, 240); await expect.poll(() => positions(region)).toEqual({ region: 240, bar: 240 })
    // region (keyboard on the focusable region) -> top scrollbar
    await region.focus(); await page.keyboard.press('ArrowRight', { delay: 20 }); await page.keyboard.press('ArrowRight')
    await expect.poll(async () => { const p = await positions(region); return p.region > 240 && p.region === p.bar }).toBe(true)
    await scrollBar(region, 0); await expect.poll(() => positions(region)).toEqual({ region: 0, bar: 0 })
    await page.keyboard.press('ArrowRight'); await expect.poll(async () => { const p = await positions(region); return p.region > 0 && p.region === p.bar }).toBe(true)
    await scrollBar(region, 0); await expect.poll(() => positions(region)).toEqual({ region: 0, bar: 0 })
    // region (wheel / trackpad) -> top scrollbar
    const box = (await region.boundingBox())!
    await page.mouse.move(box.x + box.width / 2, box.y + Math.min(box.height / 2, 60)); await page.mouse.wheel(300, 0)
    await expect.poll(async () => { const p = await positions(region); return p.region > 0 && p.region === p.bar }).toBe(true)
    // The bar's own colour comes from the theme tokens (no hard-coded light track in dark mode)
    const [track, token] = await region.evaluate(element => {
      const probe = document.body.appendChild(Object.assign(document.createElement('div'), { style: 'background:var(--scrollbar-track)' }))
      const values = [getComputedStyle(element.closest('.table-frame')!.querySelector('.table-top-scroll')!).backgroundColor, getComputedStyle(probe).backgroundColor]
      probe.remove(); return values
    })
    expect(track).toBe(token)
  })

test('TBL-02 the top scrollbar is shown only while the table overflows, and follows column visibility and the filter sidebar', async ({ page }) => {
  const region = await openMatrix(page, 1280, 'light')
  const open = await measure(region); expectTopScrollbar(open)
  // Filter sidebar closed: the region widens and the scroll range is recalculated
  await page.getByRole('button', { name: /^Hide filters/ }).click()
  await expect.poll(async () => (await measure(region)).regionWidth).toBeGreaterThan(open.regionWidth + 100)
  const closed = await measure(region); expectTopScrollbar(closed); expect(closed.barRange).toBeLessThan(open.barRange)
  await page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^Filters/ }).click()
  await expect.poll(async () => Math.round((await measure(region)).regionWidth)).toBe(Math.round(open.regionWidth))
  // Hide strategy columns until the matrix fits: the top scrollbar disappears; show them again: it returns
  await page.getByRole('button', { name: 'Columns for release matrix', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Columns for release matrix', exact: true })
  for (const key of keys.slice(4)) await dialog.getByRole('checkbox', { name: key, exact: true }).uncheck()
  await dialog.getByRole('button', { name: 'Done', exact: true }).click()
  await expect.poll(async () => (await measure(region)).barVisible).toBe(false)
  expect((await measure(region)).overflow).toBe(false)
  await page.getByRole('button', { name: 'Columns for release matrix', exact: true }).click()
  await dialog.getByRole('button', { name: 'Reset columns', exact: true }).click(); await dialog.getByRole('button', { name: 'Done', exact: true }).click()
  await expect.poll(async () => (await measure(region)).barVisible).toBe(true)
})

test('TBL-02 a narrow result has no top scrollbar', async ({ page }) => {
  const region = await openMatrix(page, 1280, 'dark', few)
  const g = await measure(region)
  expect(g.overflow).toBe(false); expect(g.barVisible).toBe(false); expect(g.bottomBar).toBe(0)
})

test('TBL-02 the table head stays beneath the application header while a long table scrolls vertically', async ({ page }) => {
  seeded = await seedSources(page.request, { roles, users })
  await page.setViewportSize({ width: 800, height: 700 })
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  const region = page.getByRole('region', { name: 'User directory table', exact: true })
  await expect(region.getByRole('row')).not.toHaveCount(0)
  const before = await measure(region)
  expectTopScrollbar(before)
  // Scroll the page until the table's top has passed under the header: the head (toolbar and scrollbar) stays directly below the header
  await page.evaluate(top => window.scrollBy(0, top), before.regionTop + 400)
  const after = await measure(region)
  expect(after.regionTop).toBeLessThan(after.headerBottom) // the table top is scrolled away ...
  expect(Math.abs((await frameOf(region).locator('.table-frame-head').boundingBox())!.y - after.headerBottom)).toBeLessThanOrEqual(1) // ... the head is not
  expect(after.barVisible).toBe(true)
  await scrollBar(region, 120); await expect.poll(() => positions(region)).toEqual({ region: 120, bar: 120 }) // usable without scrolling to the table end
})
