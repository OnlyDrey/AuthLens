import { test, expect } from '@playwright/test'
import { goTo } from './support'

// WP29: BUG-011 (one dropdown surface on touch) and BUG-012 (compact mobile header). Chromium with touch emulation; actual iOS Safari acceptance
// is a native operator step (see the acceptance tracker): desktop WebKit or emulation is not evidence for it.
test.describe('touch input', () => {
  test.use({ hasTouch: true })
  test('a tap on a shared select leaves the platform picker as the only surface; mouse and keyboard keep the custom list', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 })
    await page.goto('/#session=browser-test-session')
    await goTo(page, 'Release Access')
    const select = page.locator('select:visible').first()
    await expect(select).toBeVisible()
    // The sequence a touch tap produces: a touch pointerdown, then the compatibility mousedown (iOS Safari opens its picker in between).
    const press = (pointerType: string) => select.evaluate((element, type) => {
      element.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerType: type, isPrimary: true }))
      element.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 }))
    }, pointerType)
    await press('touch')
    await expect(select).toHaveAttribute('aria-expanded', 'false')               // no custom popup in addition to the native picker
    await expect(page.locator('[role="listbox"]')).toHaveCount(0)
    await press('mouse')
    await expect(select).toHaveAttribute('aria-expanded', 'true')
    await page.keyboard.press('Escape')
    await expect(select).toHaveAttribute('aria-expanded', 'false')
    await select.focus(); await page.keyboard.press('Enter')
    await expect(select).toHaveAttribute('aria-expanded', 'true')
  })
})

test('the phone header is one compact row with every action and no horizontal scroll', async ({ page }) => {
  for (const [width, height] of [[390, 844], [375, 667], [320, 640]] as const) {
    await page.setViewportSize({ width, height })
    await page.goto('/#session=browser-test-session')
    const header = page.locator('header[role="banner"]')
    await expect(header.getByRole('button', { name: 'Open navigation', exact: true })).toBeVisible()
    await expect(header.getByRole('button', { name: 'Open settings', exact: true })).toBeVisible()
    expect((await header.boundingBox())!.height).toBeLessThanOrEqual(64)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
  }
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto('/#session=browser-test-session')
  expect((await page.locator('header[role="banner"]').boundingBox())!.height).toBeLessThanOrEqual(80)
})