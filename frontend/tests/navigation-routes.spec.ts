import { test, expect } from '@playwright/test'
import { goTo, mainNavigation, seedSources, type SeededSources } from './support'

/** NAV-1 to NAV-3: canonical routes, legacy redirects with their query, default landing pages and the Users and Reviews structure. */
const roles = `FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,CHILD_AGR_TEXT,TCODE,TTEXT
MM,ZC:MM:BUY:ENP,Buyer plant,ZS:SH,MM - Shared purchasing,MIGO,Goods movement
`
const users = `USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO
SYN_ROUTE,ZC:MM:BUY:ENP,G1,20200101,99991231
`
let seeded: SeededSources
test.beforeEach(async ({ request }) => { seeded = await seedSources(request, { roles, users }) })
test.afterEach(async () => { await seeded.cleanup() })

const pageTitle = (page: import('@playwright/test').Page, name: string) => page.getByRole('heading', { name, exact: true }).first()

test('legacy routes resolve to their canonical destination and keep the query and history', { tag: '@smoke' }, async ({ page }) => {
  await page.goto('/#session=browser-test-session')
  for (const [legacy, canonical, title] of [
    ['#/user-access', '#/users', 'Users'],
    ['#/user-access/compare', '#/users/compare', 'Compare Users'],
    ['#/user-access/user/SYN_ROUTE', '#/users/user/SYN_ROUTE', 'User details'],
    ['#/release-roles', '#/users/release-access', 'Release Access'],
    ['#/user-access/account-review', '#/reviews/account-review', 'Account Review'],
    ['#/user-access/position-changes', '#/reviews/position-changes', 'Position Changes'],
  ] as const) {
    await page.goto(`/${legacy}?view=compact`)
    await expect(page).toHaveURL(new RegExp(`${canonical.replace(/\//g, '\\/')}\\?view=compact$`))
    await expect(pageTitle(page, title)).toBeVisible()
  }
  // Back returns through the visited destinations
  await page.goBack()
  await expect(pageTitle(page, 'Account Review')).toBeVisible()
  await expect(page).toHaveURL(/#\/reviews\/account-review\?view=compact$/)
})

test('top-level modules open their default landing page, not the last visited subpage', async ({ page }) => {
  await page.goto('/#session=browser-test-session')
  await expect(mainNavigation(page).getByRole('link')).toHaveText(['Dashboard', 'Role Lookup', 'Users', 'Reviews']) // SoD off; no report available
  await goTo(page, 'Release Access')
  await expect(page).toHaveURL(/#\/users\/release-access$/)
  await expect(mainNavigation(page).getByRole('link', { name: 'Users', exact: true })).toHaveAttribute('aria-current', 'page')
  await mainNavigation(page).getByRole('link', { name: 'Users', exact: true }).click()
  await expect(page).toHaveURL(/#\/users$/)
  await expect(page.getByRole('navigation', { name: 'Users view', exact: true }).getByRole('link', { name: 'User Directory', exact: true })).toHaveAttribute('aria-current', 'page')
  await page.getByRole('navigation', { name: 'Users view', exact: true }).getByRole('link', { name: 'Compare Users', exact: true }).click()
  await expect(page).toHaveURL(/#\/users\/compare$/)
  await goTo(page, 'Account Review')
  await expect(page).toHaveURL(/#\/reviews\/account-review$/)
  await mainNavigation(page).getByRole('link', { name: 'Users', exact: true }).click()
  await expect(page).toHaveURL(/#\/users$/) // not Compare Users, where Users was left
  await mainNavigation(page).getByRole('link', { name: 'Reviews', exact: true }).click()
  await expect(page).toHaveURL(/#\/reviews$/) // not Account Review
})

test('Users and Reviews list their pages in the approved order; account reviews stay available with SoD off', async ({ page }) => {
  await page.goto('/#session=browser-test-session'); await goTo(page, 'Users')
  await expect(page.getByRole('navigation', { name: 'Users view', exact: true }).getByRole('link')).toHaveText(['User Directory', 'Compare Users', 'Release Access'])
  await goTo(page, 'Reviews')
  // SoD access-review pages follow the SoD switch (off in this fixture); Position Changes and Account Review do not
  await expect(page.getByRole('navigation', { name: 'Review views', exact: true }).getByRole('link')).toHaveText(['Overview', 'Position Changes', 'Account Review'])
  await goTo(page, 'Position Changes')
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(['Reviews']) // one page h1; the page title is a section heading
  await expect(page.getByRole('heading', { name: 'Position Changes', level: 2 })).toBeVisible()
  await goTo(page, 'Account Review')
  await page.getByRole('link', { name: 'SYN_ROUTE', exact: true }).click()
  await expect(pageTitle(page, 'User details')).toBeVisible()
  await page.getByRole('button', { name: 'Back to Account Review', exact: true }).click()
  await expect(page).toHaveURL(/#\/reviews\/account-review$/)
  await expect(page.getByRole('link', { name: 'SYN_ROUTE', exact: true })).toBeVisible()
})

test('the Directory & Data Health card is administrator-only (NAV-5)', async ({ page }) => {
  const card = page.getByRole('region', { name: 'Directory & Data Health', exact: true })
  await page.goto('/#session=browser-test-session')
  await expect(page.getByRole('region', { name: 'Access & Risk', exact: true })).toBeVisible()
  await expect(card).toBeVisible() // the browser host is an administrator session
  // A signed-in viewer: the whole card is absent (no reduced version) and Settings, which holds Data Health, is not offered.
  const viewer = { id: 'viewer-id', username: 'viewer', display_name: 'Viewer', role: 'viewer', permissions: ['read', 'export', 'profile'], enabled: true, revision: 1, last_login: null }
  await page.route('**/api/auth/state', route => route.fulfill({ json: { provider: 'local-sessions', setup_required: false } }))
  await page.route('**/api/auth/me', route => route.fulfill({ json: viewer }))
  await page.reload()
  await expect(page.getByRole('region', { name: 'Access & Risk', exact: true })).toBeVisible()
  await expect(card).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Open settings', exact: true })).toHaveCount(0)
})
