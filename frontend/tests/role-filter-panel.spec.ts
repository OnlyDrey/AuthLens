import {test,expect,type Page} from '@playwright/test'
import {mkdtempSync,writeFileSync,rmSync,mkdirSync} from 'node:fs'
import {tmpdir} from 'node:os'
import path from 'node:path'
import {headers,postConfiguration,goTo} from './support'

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
})
test.afterEach(async({request})=>{await request.post('/api/configuration/reset',{headers});rmSync(directory,{recursive:true,force:true})})
async function open(page:Page){await page.goto('/#session=browser-test-session');await goTo(page,'Role Lookup')}

for(const theme of ['dark','light'] as const)test(`compact role pills, full-name focus hints and narrow search ${theme} @visual`,async({page,request})=>{
  const settings=(await(await request.get('/api/configuration',{headers})).json()).settings;settings.theme=theme
  expect((await postConfiguration(request,settings)).ok()).toBeTruthy()
  await open(page)
  for(const width of [375,800,1280,1600]){
    await page.setViewportSize({width,height:900})
    if(width<1024)await page.getByRole('button',{name:'Filters',exact:true}).click()
    const group=page.getByRole('group',{name:'SAP areas',exact:true})
    await expect(group.getByRole('button')).toHaveCount(5)
    const geometry=await group.evaluate(element=>{
      const bounds=element.getBoundingClientRect()
      return [...element.querySelectorAll('button')].map(button=>({height:button.getBoundingClientRect().height,inside:button.getBoundingClientRect().right<=bounds.right+1,nowrap:getComputedStyle(button).whiteSpace}))
    })
    expect(geometry.every(pill=>pill.height===36&&pill.inside&&pill.nowrap==='nowrap')).toBe(true)
    const category=group.getByRole('button',{name:`MM ${longName} (2)`,exact:true})
    await category.focus()
    await expect(page.getByRole('tooltip',{name:`MM — ${longName}: 2 roles`,exact:true})).toBeVisible()
    await page.getByRole('searchbox',{name:'Search roles by name or description',exact:true}).focus()
    expect(await group.evaluate(element=>element.scrollWidth<=element.clientWidth+1)).toBe(true)
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
    const folder=path.resolve('../build/test-artifacts/role-filter-panel');mkdirSync(folder,{recursive:true})
    await page.screenshot({path:path.join(folder,`${theme}-${width}.png`)})
    if(width<1024)await page.getByRole('button',{name:'Show results',exact:true}).click()
  }
})

test('role search clear preserves OR categories, transactions and comparison selection',async({page})=>{
  await open(page)
  await expect(page.getByRole('article')).toHaveCount(5)
  await page.getByRole('article').filter({hasText:'Alpha purchasing'}).getByRole('button',{name:'Add to comparison',exact:true}).click()
  const group=page.getByRole('group',{name:'SAP areas',exact:true})
  await group.getByRole('button',{name:/^MM /}).click();await group.getByRole('button',{name:/^FI /}).click()
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
  await expect(group.getByRole('button',{name:/^MM /})).toHaveAttribute('aria-pressed','true')
  await expect(group.getByRole('button',{name:/^FI /})).toHaveAttribute('aria-pressed','true')
  await expect(tx.getByRole('button',{name:'Remove transaction MIGO',exact:true})).toBeVisible()
  await expect(page.getByRole('button',{name:'Remove from comparison',exact:true})).toHaveCount(1)
  await search.fill('no-such-role');await expect(page.getByRole('status').filter({hasText:'No matches found'})).toBeVisible()
  await clear.click();await expect(page.getByRole('article')).toHaveCount(2)
  await group.getByRole('button',{name:/^All /}).click()
  await expect(group.getByRole('button',{name:/^All /})).toHaveAttribute('aria-pressed','true')
  await expect(tx.getByRole('button',{name:'Remove transaction MIGO',exact:true})).toBeVisible()
})
