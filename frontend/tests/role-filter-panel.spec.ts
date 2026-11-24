import {test,expect,type Page} from '@playwright/test'
import {mkdtempSync,writeFileSync,rmSync,mkdirSync} from 'node:fs'
import {tmpdir} from 'node:os'
import path from 'node:path'
import {headers,postConfiguration,goTo} from './support'
import {toggleRoleCategory} from './role-category-support'

let directory:string
const longName='Materials Management and International Procurement Coordination'
test.beforeEach(async({request,page})=>{
  await request.post('/api/configuration/reset',{headers})
  directory=mkdtempSync(path.join(tmpdir(),'authlens-role-panel-'))
  const catalogue=path.join(directory,'roles.csv')
  writeFileSync(catalogue,'FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE\nMM,ZC:MM:A,Alpha purchasing,ZS:A,MIGO\nMM,ZC:MM:D,Delta purchasing,ZS:D,ME23N\nFI,ZC:FI:B,Beta finance,ZS:B,MIGO\nSD,ZC:SD:C,Gamma sales,ZS:C,VA03\nBC,ZC:BC:E,Basis jobs,ZS:E,SM37\n')
  const settings=(await(await request.get('/api/configuration',{headers})).json()).settings
  settings.data_csv_path=catalogue
  expect((await postConfiguration(request,settings)).ok()).toBeTruthy()
  await page.route('**/api/modules',async route=>{
    const response=await route.fetch(),items=await response.json()
    for(const item of items){if(item.function_key==='MM')item.module_name=longName;if(item.function_key==='FI')item.module_name='Finance';if(item.function_key==='BC')item.module_name='Basis'}
    await route.fulfill({response,json:items})
  })
  // Deliberately distinct registry icons prove the selector uses existing mappings, not a generic replacement.
  await page.route('**/api/registry/modules',async route=>{
    const response=await route.fetch(),registry=await response.json()
    for(const item of registry.modules){if(item.id==='MM')item.icon='Warehouse';if(item.id==='FI')item.icon='Wrench'}
    await route.fulfill({response,json:registry})
  })
})
test.afterEach(async({request})=>{await request.post('/api/configuration/reset',{headers});rmSync(directory,{recursive:true,force:true})})
async function open(page:Page){await page.goto('/#session=browser-test-session');await goTo(page,'Role Lookup')}

for(const theme of ['dark','light'] as const)test(`category dropdown icons, counts and narrow layout ${theme} @visual`,async({page,request})=>{
  const settings=(await(await request.get('/api/configuration',{headers})).json()).settings;settings.theme=theme
  expect((await postConfiguration(request,settings)).ok()).toBeTruthy()
  await open(page)
  for(const width of [375,800,1280,1600]){
    await page.setViewportSize({width,height:900})
    if(width<1024)await page.getByRole('button',{name:'Filters',exact:true}).click()
    const category=page.getByRole('combobox',{name:'Role categories',exact:true})
    await expect(category).toContainText('All categories (5)')
    expect(await category.evaluate(element=>{
      const count=element.querySelector('[title]')!.lastElementChild!.getBoundingClientRect()
      const arrow=element.parentElement!.querySelector(':scope > svg')!.getBoundingClientRect()
      return count.right+4<=arrow.left
    })).toBe(true)
    await category.focus();await category.press('Enter')
    const list=page.getByRole('listbox',{name:'Role categories',exact:true})
    await expect(list.getByRole('option')).toHaveCount(5)
    for(const code of ['BC','FI','MM','SD'])await expect(list.locator(`[data-value="${code}"] [data-module="${code}"] [data-module-icon] svg`)).toBeVisible()
    await expect(list.locator('[data-value="MM"] .lucide-warehouse')).toBeVisible()
    await expect(list.locator('[data-value="FI"] .lucide-wrench')).toBeVisible()
    await expect(list.getByRole('option',{name:`MM ${longName} (2)`,exact:true})).toBeVisible()
    await expect(list.getByRole('option',{name:'All categories (5)',exact:true})).toHaveAttribute('aria-selected','true')
    expect(await list.evaluate(element=>element.scrollWidth<=element.clientWidth+1)).toBe(true)
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
    const folder=path.resolve('../build/test-artifacts/role-category-dropdown');mkdirSync(folder,{recursive:true})
    await page.screenshot({path:path.join(folder,`${theme}-${width}.png`)})
    await category.press('Escape');await expect(category).toBeFocused();await expect(category).toHaveAttribute('aria-expanded','false')
    await category.press('Enter');await category.press('Home');await category.press('ArrowDown');await category.press('Enter');await category.press('Escape')
    await expect(category.locator('[data-module="BC"] [data-module-icon]')).toBeVisible()
    await expect(category).toContainText('Basis (1)')
    await toggleRoleCategory(page,'All categories')
    if(width<1024)await page.getByRole('button',{name:'Show results',exact:true}).click()
  }
})

test('category keyboard navigation, typeahead, selected icon and outside dismissal',async({page})=>{
  await open(page)
  const control=page.getByRole('combobox',{name:'Role categories',exact:true})
  await control.focus();await control.press('ArrowDown')
  await expect(page.getByRole('listbox',{name:'Role categories',exact:true})).toHaveAttribute('aria-multiselectable','true')
  await control.press('End');await control.press('Space')
  await expect(page.getByRole('option',{name:/^SD /})).toHaveAttribute('aria-selected','true')
  await expect(page.getByRole('article')).toHaveCount(1)
  await control.press('Home');await control.press('Enter')
  await expect(page.getByRole('article')).toHaveCount(5)
  await control.press('m');await control.press('Enter')
  await expect(page.getByRole('option',{name:/^MM /})).toHaveAttribute('aria-selected','true')
  await control.press('Escape');await expect(control).toBeFocused()
  await expect(control.locator('.lucide-warehouse')).toBeVisible()
  await expect(control.locator('[title]').first()).toHaveAttribute('title',`MM — ${longName} (2)`)
  await control.press('Enter');await control.press('Tab')
  await expect(control).toHaveAttribute('aria-expanded','false')
  await control.click();await page.getByRole('searchbox',{name:'Search roles by name or description',exact:true}).click()
  await expect(control).toHaveAttribute('aria-expanded','false')
  await expect(page.getByRole('article')).toHaveCount(2)
})

test('role search clear preserves OR categories, transactions and comparison selection',async({page})=>{
  await open(page)
  await expect(page.getByRole('article')).toHaveCount(5)
  await page.getByRole('article').filter({hasText:'Alpha purchasing'}).getByRole('button',{name:'Add to comparison',exact:true}).click()
  const group=page.getByRole('group',{name:'SAP areas',exact:true})
  await toggleRoleCategory(page,'MM');await toggleRoleCategory(page,'FI')
  await expect(page.getByRole('article')).toHaveCount(3)
  const tx=page.getByRole('group',{name:'Filter catalogue by transaction',exact:true})
  await tx.getByRole('textbox').fill('MIGO');await tx.getByRole('textbox').press('Enter')
  await expect(page.getByRole('article')).toHaveCount(2)
  const search=page.getByRole('searchbox',{name:'Search roles by name or description',exact:true})
  await search.fill('ZC:MM:A');await expect(page.getByRole('article')).toHaveCount(1)
  await search.press('Tab')
  const clear=page.getByRole('button',{name:'Clear role search',exact:true})
  await expect(clear).toBeFocused();await clear.press('Enter');await expect(search).toBeFocused()
  await expect(page.getByRole('article')).toHaveCount(2)
  await group.getByRole('combobox').click()
  await expect(page.getByRole('option',{name:/^MM /})).toHaveAttribute('aria-selected','true')
  await expect(page.getByRole('option',{name:/^FI /})).toHaveAttribute('aria-selected','true')
  await group.getByRole('combobox').press('Escape')
  await expect(tx.getByRole('button',{name:'Remove transaction MIGO',exact:true})).toBeVisible()
  await expect(page.getByRole('button',{name:'Remove from comparison',exact:true})).toHaveCount(1)
  await search.fill('no-such-role');await expect(page.getByRole('status').filter({hasText:'No matches found'})).toBeVisible()
  await clear.click();await expect(page.getByRole('article')).toHaveCount(2)
  await toggleRoleCategory(page,'All categories')
  await expect(group.getByRole('combobox')).toContainText('All categories (5)')
  await expect(tx.getByRole('button',{name:'Remove transaction MIGO',exact:true})).toBeVisible()
})
