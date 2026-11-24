import {test,expect} from '@playwright/test'
import {seedGovernance,cleanup} from './sod-fixture'

let directory=''
test.beforeEach(async({request})=>{directory=await seedGovernance(request,'static')})
test.afterEach(async({request})=>{await cleanup(request,directory)})

test('matrix keeps one reachable cell when a focused column or group is hidden',async({page})=>{
  await page.setViewportSize({width:800,height:900});await page.goto('/#session=browser-test-session');await page.goto('/#/sod/risk-matrix')
  const matrix=page.getByRole('region',{name:/Scrollable User by risk matrix/})
  const focused=matrix.locator('button[data-cell]').last();await expect(focused).toBeVisible()
  const column=Number((await focused.getAttribute('data-cell'))!.split(':')[1]);await focused.focus()
  const trigger=page.getByRole('button',{name:'Columns for User by risk matrix',exact:true});await trigger.click()
  const dialog=page.getByRole('dialog',{name:'Columns for User by risk matrix',exact:true})
  const fields=await dialog.locator('.table-column-options label').allTextContents();expect(fields.length).toBeGreaterThan(1)
  await dialog.getByLabel(fields[column],{exact:true}).uncheck();await dialog.getByRole('button',{name:'Done',exact:true}).click()
  await expect(matrix.locator('button[data-cell][tabindex="0"]')).toHaveCount(1)
  await matrix.locator('button[data-cell][tabindex="0"]').focus();await page.keyboard.press('Home')
  await expect(matrix.locator('button[data-cell][tabindex="0"]')).toBeFocused()

  await trigger.click();await dialog.getByRole('button',{name:'Reset columns',exact:true}).click();await dialog.getByRole('button',{name:'Done',exact:true}).click()
  await page.getByRole('combobox',{name:'Group by',exact:true}).selectOption('group')
  await expect(matrix.locator('.matrix-group-row').first()).toBeVisible()
  const cell=matrix.locator('button[data-cell]').first();await cell.focus()
  const collapse=await cell.evaluate(element=>{
    let row=element.closest('tr')?.previousElementSibling
    while(row&&!row.classList.contains('matrix-group-row'))row=row.previousElementSibling
    return row?.querySelector('button')?.getAttribute('aria-label')
  })
  expect(collapse).toBeTruthy();await matrix.getByRole('button',{name:collapse!,exact:true}).click()
  expect(await matrix.locator('button[data-cell]').count()).toBeGreaterThan(0)
  await expect(matrix.locator('button[data-cell][tabindex="0"]')).toHaveCount(1)
})
