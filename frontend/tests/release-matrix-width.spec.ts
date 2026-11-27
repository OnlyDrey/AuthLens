import { test, expect, type Page } from '@playwright/test'
import { goTo, headers, seedSources, type SeededSources } from './support'

/** MW-1 Release Access Matrix width: every matrix uses the whole content width beside the filter sidebar (all of it when the sidebar is
 *  closed), fills it when its columns are few and scrolls only inside its own container when they exceed it, with Compare SAP user groups on
 *  or off and after column visibility changes. Geometry is asserted, not screenshots. */
const roles = `FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE
MM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MIGO
`
const few = `USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO
U1,ZO:MM:M:PR_REL_ST_E2_N1:ALL,G1,20200101,99991231
U1,ZO:MM:M:PO_REL_ST_E3_N2:ALL,G1,20200101,99991231
U2,ZO:MM:M:PR_REL_ST_E2_N1:ALL,G2,20200101,99991231
U2,ZO:MM:M:PO_REL_ST_E3_N2:ALL,G2,20200101,99991231
`
// 40 strategy keys, far wider than 1600 px at the matrix's minimum column width; two SAP user groups for Compare
const keys = ['S', 'T', 'U', 'V'].flatMap(letter => Array.from({ length: 10 }, (_, digit) => `${letter}${digit}`))
const many = 'USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO\n'
  + keys.flatMap((key, index) => ['G1', 'G2'].map(group => `MW${index}${group},ZO:MM:M:${index % 2 ? 'PO' : 'PR'}_REL_ST_E${index % 3}_${key}:ALL,${group},20200101,99991231`)).join('\n') + '\n'

let seeded: SeededSources
test.afterEach(async () => { await seeded.cleanup() })

type Matrix = { label: string; main: number; scroll: number; left: number; clientWidth: number; scrollWidth: number; table: number; toolbarLeft: number | null; columns: number[] }
type Geometry = { matrices: Matrix[]; pageOverflow: boolean }
const measure = (page: Page) => page.evaluate((): Geometry => ({
  pageOverflow: document.documentElement.scrollWidth > innerWidth + 1,
  matrices: [...document.querySelectorAll<HTMLElement>('[role="region"][aria-label$="release matrix scroll area"]')].map(scroll => {
    const main = scroll.closest<HTMLElement>('.filter-layout-main')!, style = getComputedStyle(main)
    const table = scroll.querySelector('table')!, toolbar = scroll.closest('.table-frame')?.querySelector('.table-presentation-controls') ?? null, box = scroll.getBoundingClientRect() // TBL-02: the toolbar is in the table frame
    return {
      label: scroll.getAttribute('aria-label')!, main: main.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight), scroll: box.width, left: box.left,
      clientWidth: scroll.clientWidth, scrollWidth: scroll.scrollWidth, table: table.getBoundingClientRect().width,
      toolbarLeft: toolbar ? toolbar.getBoundingClientRect().left : null,
      columns: [...table.querySelectorAll<HTMLElement>('thead th:not([hidden])')].map(th => Math.round(th.getBoundingClientRect().width)),
    }
  }),
}))
/** wide: true = the columns must exceed the width (scroll), false = they must fit (no scroll), undefined = either, decided by the geometry. */
const expectFilled = (g: Geometry, wide: boolean | undefined, count: number) => {
  expect(g.matrices).toHaveLength(count)
  expect(g.pageOverflow).toBe(false)
  for (const m of g.matrices) {
    expect(Math.abs(m.scroll - m.main), `${m.label}: ${m.scroll}px of ${m.main}px content width`).toBeLessThanOrEqual(1) // the whole available width
    if (m.toolbarLeft !== null) expect(Math.abs(m.toolbarLeft - m.left)).toBeLessThanOrEqual(2) // Columns toolbar aligned with the container
    expect(m.columns[0]).toBeGreaterThanOrEqual(160); for (const width of m.columns.slice(1)) expect(width).toBeGreaterThanOrEqual(72) // existing minimum widths
    const scrolls = m.scrollWidth > m.clientWidth
    if (wide !== undefined) expect(scrolls, `${m.label} scrolls`).toBe(wide)
    // Horizontal scrolling only because the columns exceed the width: the table is then wider than the container; otherwise the compact,
    // content-sized table (refinement-completion keeps it under 500 px) sits inside the full-width container without scrolling
    if (scrolls) expect(m.table).toBeGreaterThan(m.clientWidth); else expect(m.table).toBeLessThanOrEqual(m.clientWidth)
  }
}
const sidebarCycle = async (page: Page, width: number, wide: boolean | undefined, count: number) => {
  const open = await measure(page); expectFilled(open, wide, count)
  const sidebar = page.getByRole('complementary', { name: 'Filters', exact: true })
  if (width >= 1024) {
    await expect(sidebar).toBeVisible()
    await page.getByRole('button', { name: /^Hide filters/ }).click(); await expect(sidebar).toBeHidden()
    const closed = await measure(page); expectFilled(closed, wide, count)
    for (const [index, m] of closed.matrices.entries()) {
      expect(m.scroll).toBeGreaterThan(open.matrices[index].scroll + 100) // the sidebar's space goes to the matrix
      if (m.scrollWidth > m.clientWidth && open.matrices[index].scrollWidth > open.matrices[index].clientWidth) expect(m.columns).toEqual(open.matrices[index].columns) // natural column widths are kept; only the scroll range changes
    }
    const toggle = page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^Filters/ }) // the closed sidebar's toggle
    await expect(toggle).toHaveAttribute('aria-expanded', 'false'); await toggle.click(); await expect(sidebar).toBeVisible()
    const reopened = await measure(page); expectFilled(reopened, wide, count)
    for (const [index, m] of reopened.matrices.entries()) expect(Math.abs(m.scroll - open.matrices[index].scroll)).toBeLessThanOrEqual(1) // recalculated back
  } else {
    // below 1024 px the filters are a drawer over the page: opening it never narrows the matrix
    await page.getByRole('button', { name: /^Filters/ }).first().click()
    const drawer = page.getByRole('dialog', { name: 'Filters', exact: true }); await expect(drawer).toBeVisible()
    for (const [index, m] of (await measure(page)).matrices.entries()) expect(Math.abs(m.scroll - open.matrices[index].scroll)).toBeLessThanOrEqual(1)
    await drawer.getByRole('button', { name: 'Show results', exact: true }).click(); await expect(drawer).toHaveCount(0)
    expectFilled(await measure(page), wide, count)
  }
}

for (const [name, users] of [['few', few], ['many', many]] as const)
  for (const width of [375, 800, 1024, 1280, 1600]) for (const theme of ['light', 'dark'] as const) {
    // 40 strategy columns exceed every width; the four columns of the few matrix fit from 800 px, at 375 px only once a column is hidden
    const wide = name === 'many' ? true : width >= 800 ? false : undefined
    test(`MW-1 release matrix uses the available content width: ${name} strategies ${width} ${theme}`, { tag: '@visual' }, async ({ page, request }) => {
      seeded = await seedSources(request, { roles, users })
      expect((await request.post('/api/configuration/theme', { headers, data: { theme } })).ok()).toBeTruthy()
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/#session=browser-test-session'); await goTo(page, 'Release Access')
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
      await page.getByRole('button', { name: 'Matrix', exact: true }).click()
      const matrix = page.getByRole('table', { name: 'release matrix', exact: true })
      await expect(matrix).toBeVisible()
      const strategies = name === 'few' ? ['N1', 'N2'] : keys
      await expect(matrix.getByRole('columnheader')).toHaveText(['Release group', ...strategies, 'Users']) // strategy-only headers, unchanged column set
      // Compare SAP user groups off: one matrix
      await sidebarCycle(page, width, wide, 1)
      // Column visibility through the Columns control: hiding a strategy column keeps the matrix at the full width
      await page.getByRole('button', { name: 'Columns for release matrix', exact: true }).click()
      const columns = page.getByRole('dialog', { name: 'Columns for release matrix', exact: true })
      await columns.getByRole('checkbox', { name: strategies[0], exact: true }).uncheck()
      await columns.getByRole('button', { name: 'Done', exact: true }).click(); await expect(columns).toHaveCount(0)
      await expect(matrix.getByRole('columnheader', { name: strategies[0], exact: true })).toBeHidden()
      expectFilled(await measure(page), wide, 1)
      // Compare SAP user groups on: one matrix per group, each across the whole width
      await page.getByRole('group', { name: 'Release actions' }).getByLabel('Compare SAP user groups').check()
      await expect(page.getByRole('table', { name: 'G2 release matrix', exact: true })).toBeVisible()
      await sidebarCycle(page, width, wide, 2)
    })
  }
