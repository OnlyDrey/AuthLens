import { test, expect, type Page } from '@playwright/test'
import { cleanup, longRoleName, openSod, seedGovernance } from './sod-fixture'
import { goTo, seedSources, type SeededSources, recordClipboard, copiedText } from './support'

/** BUG-09 (reopened): an interactive SAP identifier (role or username) is one line inside its own box: it never wraps, never makes its container
 * scroll, truncates with an ellipsis when its container is narrower (the full value stays in the tooltip and is copied), keeps its copy and
 * open icons visible, and keeps the same geometry in every interaction state and while a sidebar opens or closes. Tables and matrices keep
 * their own intentional horizontal scrolling. */
const MEDIUM = 'ZC:SYN:LONG_ROLE_IDENTIFIER_FOR_LAYOUT:ENP'
const LONG = 'ZC:SYN:A_VERY_LONG_ROLE_IDENTIFIER_FOR_LAYOUT_STRESS_TESTING:ABCDEFGHIJKLMNOP:0123456789:QRSTUV'
const roles = `FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,CHILD_AGR_TEXT,TCODE,TTEXT
MM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MM - Shared purchasing,MIGO,Goods movement
MM,${MEDIUM},Medium identifier role,ZS:MED,MM - Medium,MIGO,Goods movement
MM,${LONG},Long identifier role,ZS:LONG,MM - Long,ME21N,Create purchase order
`
const users = `USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO
U1,ZC:MM:BUY:ENP,G1,20200101,99991231
U1,${MEDIUM},G1,20200101,99991231
U2,${LONG},G2,20200101,99991231
U2,${MEDIUM},G2,20200101,99991231
`

/** Problems with every visible identifier on the page (optionally only the named ones). */
async function violations(page: Page, only: string[] = []) {
  return page.evaluate(({ names }) => {
    const problems: string[] = []
    // Layout regions that may scroll horizontally on purpose; everything between an identifier and such a region must not scroll.
    const region = (node: Element) => node.matches('.access-table, .matrix-scroll, .matrix-grid, table, [role="region"][tabindex], .ui-dialog-content, .ui-side-panel-body, .filter-sidebar, .sod-heatmap-scroll, .user-directory-table, body, html')
    for (const root of document.querySelectorAll<HTMLElement>('.role-identifier')) {
      const code = root.querySelector('code')
      if (!code || !root.getClientRects().length) continue
      const name = code.textContent || ''
      if (names.length && !names.includes(name)) continue
      const style = getComputedStyle(code), box = code.getBoundingClientRect(), frame = root.getBoundingClientRect()
      const label = `${name.slice(0, 24)}… (${Math.round(box.width)}px in ${root.closest('[role=dialog],article,table,aside,section')?.tagName.toLowerCase()})`
      if (style.whiteSpace !== 'nowrap') problems.push(`${label}: white-space ${style.whiteSpace}`)
      if (box.height > parseFloat(style.lineHeight) * 1.5) problems.push(`${label}: wraps onto ${Math.round(box.height)}px`)
      if (code.scrollWidth > code.clientWidth + 1) {
        if (style.textOverflow !== 'ellipsis') problems.push(`${label}: truncated without an ellipsis`)
        if (code.title !== name) problems.push(`${label}: truncated without the full name in its tooltip`)
      }
      if (box.left < frame.left - 1 || box.right > frame.right + 1) problems.push(`${label}: the name leaves its box`)
      const copy = root.querySelector<HTMLElement>('button[aria-label^="Copy "]')?.getBoundingClientRect()
      if (!copy || !copy.width) problems.push(`${label}: no copy icon`)
      else {
        if (copy.top > box.bottom || copy.bottom < box.top) problems.push(`${label}: copy icon is not beside the name`)
        if (copy.right > frame.right + 1) problems.push(`${label}: copy icon outside its box`)
      }
      for (let parent = root.parentElement; parent && !region(parent); parent = parent.parentElement) {
        const overflow = getComputedStyle(parent).overflowX
        if ((overflow === 'auto' || overflow === 'scroll') && parent.scrollWidth > parent.clientWidth + 1) { problems.push(`${label}: its container ${parent.tagName.toLowerCase()}.${parent.className.toString().split(' ')[0]} scrolls`); break }
      }
    }
    return problems
  }, { names: only })
}
/** Every identifier: no wrapping, no internal scrolling, icons visible; a realistic short name is never truncated. */
async function expectLines(page: Page) {
  expect(await violations(page)).toEqual([])
  expect(await page.evaluate(() => [...document.querySelectorAll<HTMLElement>('.role-identifier code')].filter(c => c.textContent === 'ZC:MM:BUY:ENP' && c.getClientRects().length && c.scrollWidth > c.clientWidth + 1).length)).toBe(0)
}
const shown = (page: Page, name: string) => page.locator('.role-identifier code', { hasText: name }).first()
/** Box sizes of the visible identifiers (one entry per identifier), to compare geometry between states. */
const geometry = (page: Page, names: string[]) => page.evaluate((wanted) => [...document.querySelectorAll<HTMLElement>('.role-identifier')]
  .filter(root => root.getClientRects().length && wanted.includes(root.querySelector('code')?.textContent || ''))
  .map(root => { const r = root.getBoundingClientRect(); return { h: Math.round(r.height), border: getComputedStyle(root).borderTopWidth } }), names)

test.describe('role codeblocks with synthetic names', () => {
  let seeded: SeededSources
  test.beforeEach(async ({ request }) => { seeded = await seedSources(request, { roles, users }) })
  test.afterEach(async () => { await seeded.cleanup() })

  for (const width of [375, 800, 1280]) {
    test(`Role Lookup cards, role details and the Access Package keep every name on one line in its box at ${width}px`, { tag: '@visual' }, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/#session=browser-test-session'); await goTo(page, 'Role Lookup')
      await expect(shown(page, MEDIUM)).toBeVisible()
      await expect(shown(page, LONG)).toBeVisible()
      expect(await shown(page, LONG).evaluate((element) => [element.textContent, element.getAttribute('title')])).toEqual([LONG, LONG]) // exact text and tooltip
      await expectLines(page)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy()
      await page.getByRole('article', { name: /Medium identifier role$/ }).getByRole('button', { name: /^View details/ }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await expectLines(page)
      await page.getByRole('button', { name: 'Close role details' }).click()
      for (const title of [/Medium identifier role$/, /Long identifier role$/]) await page.getByRole('article', { name: title }).getByRole('button', { name: 'Add to access package' }).click()
      await page.getByRole('button', { name: /^Access package \(2\)$/ }).click()
      const panel = page.getByRole('dialog', { name: 'Proposed access package' })
      await expect(panel.locator('.role-identifier code').first()).toBeVisible()
      await expectLines(page)
      expect(await panel.locator('.role-identifier code', { hasText: MEDIUM }).evaluate((element) => element.getBoundingClientRect().right <= innerWidth + 1)).toBeTruthy()
    })
  }

  test('copying writes the exact, untruncated role name', async ({ page }) => {
    await recordClipboard(page)
    await page.setViewportSize({ width: 375, height: 900 })
    await page.goto('/#session=browser-test-session'); await goTo(page, 'Role Lookup')
    await page.getByRole('button', { name: `Copy role identifier ${LONG}`, exact: true }).first().click()
    await expect.poll(() => copiedText(page)).toBe(LONG)
    await expectLines(page)                                                               // the copy feedback never wraps the identifier
  })

  for (const theme of ['light', 'dark'] as const) test(`identifier geometry is stable across hover, focus and repeated sidebar toggling, during and after the transition (${theme})`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: theme })
    await page.setViewportSize({ width: 1280, height: 900 })
    await page.goto('/#session=browser-test-session'); await goTo(page, 'Role Lookup')
    await expect(shown(page, LONG)).toBeVisible()
    const names = [MEDIUM, LONG, 'ZC:MM:BUY:ENP']
    const before = await geometry(page, names)
    await shown(page, MEDIUM).hover()
    expect(await geometry(page, names)).toEqual(before)                                  // hover
    await page.getByRole('button', { name: `Copy role identifier ${MEDIUM}`, exact: true }).first().focus()
    expect(await geometry(page, names)).toEqual(before)                                  // focus
    const toggle = page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^(Hide )?[Ff]ilters/ }).first()
    for (let round = 0; round < 4; round++) {
      await toggle.click()
      expect(await violations(page, names)).toEqual([])                                 // during the layout change
      await page.waitForTimeout(400)
      expect(await violations(page, names)).toEqual([])                                 // after it settled
      expect((await geometry(page, names)).map(item => item.h)).toEqual(before.map(item => item.h))
    }
  })

  for (const width of [375, 1280]) {
    test(`User Access usernames and roles stay single-line without internal scrollbars while the filter sidebar toggles at ${width}px`, { tag: '@visual' }, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/#session=browser-test-session'); await goTo(page, 'User Access')
      await expect(page.getByRole('link', { name: 'U2', exact: true })).toBeVisible()
      await expectLines(page)
      if (width >= 1024) {
        const toggle = page.getByRole('toolbar', { name: 'Page actions', exact: true }).getByRole('button', { name: /^(Hide )?[Ff]ilters/ }).first()
        for (let round = 0; round < 4; round++) { await toggle.click(); expect(await violations(page)).toEqual([]); await page.waitForTimeout(300); expect(await violations(page)).toEqual([]) }
      }
      await page.getByRole('link', { name: 'U2', exact: true }).click()
      await expect(shown(page, LONG)).toBeVisible()
      expect(await violations(page, [MEDIUM, LONG, 'ZC:MM:BUY:ENP'])).toEqual([])
    })
  }
})

test.describe('role codeblocks in the SoD workspace', () => {
  let directory = ''
  test.beforeEach(async ({ request }) => { directory = await seedGovernance(request, 'static', undefined, true) })
  test.afterEach(async ({ request }) => { await cleanup(request, directory) })

  for (const width of [375, 800, 1280]) {
    test(`Access Explorer and Reviews show ${longRoleName.length}-character names on one line at ${width}px`, { tag: '@visual' }, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await openSod(page, 'Access Explorer')
      await expect(page.locator('.role-identifier code').first()).toBeVisible()
      await expectLines(page)
      await openSod(page, 'Reviews')
      await expectLines(page)
    })
  }
})
