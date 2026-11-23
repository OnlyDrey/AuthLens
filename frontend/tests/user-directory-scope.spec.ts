import {test,expect,type Page} from '@playwright/test'
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import path from 'node:path'
import {headers,postConfiguration,pickMulti,parseDelimited} from './support'

let directory:string
const longGroup='International Procurement and Operational Risk Coordination for Northern Regions'
test.beforeEach(async({request})=>{
  await request.post('/api/configuration/reset',{headers})
  directory=mkdtempSync(path.join(tmpdir(),'authlens-directory-scope-'))
  const roles=path.join(directory,'roles.csv'),users=path.join(directory,'users.csv')
  writeFileSync(roles,'FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE\nMM,ZC:MM:A,Alpha,ZS:A,T01\nFI,ZC:FI:B,Beta,ZS:B,T02\nMM,ZC:MM:BUY:*,Purchasing,ZS:BUY,T04\n')
  writeFileSync(users,'USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO\n'+[
    ['SYN_ALICE','ZC:MM:A'],['SYN_ALICE','ZC:FI:B'],['SYN_ALICE','ZC:SD:EXTRA'],['SYN_BOB','ZC:MM:A'],['SYN_BOB','ZC:SD:EXTRA'],['SYN_CAROL','ZC:MM:BUY:ENP'],['SYN_CAROL','ZC:SD:EXTRA'],
  ].map(([user,role])=>`${user},${role},G1,20200101,99991231`).join('\n')+'\n')
  const settings=(await(await request.get('/api/configuration',{headers})).json()).settings
  settings.data_csv_path=roles;settings.user_csv_path=users
  expect((await postConfiguration(request,settings)).ok()).toBeTruthy()
})
test.afterEach(async({request})=>{await request.post('/api/configuration/reset',{headers});rmSync(directory,{recursive:true,force:true})})
async function open(page:Page){await page.goto('/#session=browser-test-session');await page.goto('/#/user-access');await expect(page.getByRole('heading',{name:/^User directory/})).toBeVisible()}
async function download(page:Page){const waiting=page.waitForEvent('download');await page.getByRole('button',{name:'Export CSV',exact:true}).click();return parseDelimited(readFileSync((await(await waiting).path())!,'utf8').replace(/^\ufeff/,''),';')}

test('directory CSV scopes selected roles and users independently without exporting unrelated access',async({page})=>{
  await open(page)
  await pickMulti(page,'Filter users by role','ZC:MM:A',page)
  await expect(page.getByRole('region',{name:'User directory table',exact:true}).getByRole('row')).toHaveCount(3)
  const all=await download(page)
  expect(all.map(row=>row.ROLE_NAME)).toEqual(['ZC:MM:A','ZC:MM:A'])
  expect(all.map(row=>row.USERNAME).sort()).toEqual(['SYN_ALICE','SYN_BOB'])
  await page.getByRole('checkbox',{name:'Select SYN_BOB',exact:true}).check()
  await page.locator('details').filter({has:page.locator('summary').filter({hasText:'Export scope'})}).locator('summary').click()
  await page.getByLabel('Assignment CSV users',{exact:true}).selectOption('selected')
  const selected=await download(page)
  expect(selected.map(row=>[row.USERNAME,row.ROLE_NAME])).toEqual([['SYN_BOB','ZC:MM:A']])
  await page.getByRole('button',{name:'Clear selection',exact:true}).click()
  await expect(page.getByRole('button',{name:'Export CSV',exact:true})).toBeDisabled()
  await page.getByLabel('Assignment CSV users',{exact:true}).selectOption('matching')
  expect((await download(page)).length).toBe(2)
  await pickMulti(page,'Filter users by role','ZC:FI:B',page)
  const multiple=await download(page)
  expect(multiple.map(row=>row.ROLE_NAME).sort()).toEqual(['ZC:FI:B','ZC:MM:A','ZC:MM:A'])
})

test('catalogue wildcard role exports concrete assignments; no role filter retains full access',async({page})=>{
  await open(page)
  expect((await download(page)).length).toBe(7)
  await pickMulti(page,'Filter users by role','ZC:MM:BUY:*',page)
  const rows=await download(page)
  expect(rows.map(row=>[row.USERNAME,row.ROLE_NAME])).toEqual([['SYN_CAROL','ZC:MM:BUY:ENP']])
})

for(const width of [390,1280])test(`Functional Group cells retain readable bounded badges and full membership ${width} @visual`,async({page})=>{
  await page.setViewportSize({width,height:900})
  await page.route('**/api/access/users?*',async route=>{
    const response=await route.fetch(),data=await response.json()
    for(const row of data.items){row.functional_groups=(row.username==='SYN_ALICE'?[longGroup,'Finance','Engineering','Operations']:row.username==='SYN_BOB'?['Finance']:[]).map((name:string,index:number)=>({id:`synthetic-${index}`,name,status:'active'}))}
    await route.fulfill({response,json:data})
  })
  await open(page)
  const table=page.getByRole('region',{name:'User directory table',exact:true})
  const row=table.getByRole('row').filter({has:page.getByRole('link',{name:'SYN_ALICE',exact:true})})
  const cell=row.locator('[data-col="fg"]'),groups=cell.getByRole('list')
  await expect(groups.locator('.fg-chip')).toHaveCount(2)
  await expect(groups.locator('.fg-chip').first()).toHaveAttribute('title',longGroup)
  const more=groups.getByRole('button',{name:'Show all 4 Functional Groups of SYN_ALICE',exact:true})
  await expect(more).toHaveText('+2 more')
  const bounds=await cell.evaluate(element=>{
    const cell=element.getBoundingClientRect(),chips=[...element.querySelectorAll('.fg-chip')].map(chip=>chip.getBoundingClientRect())
    const action=element.querySelector('button')!.getBoundingClientRect()
    return {widths:chips.map(chip=>chip.width),heights:chips.map(chip=>chip.height),buttonHeight:action.height,inside:action.right<cell.right-8,nowrap:getComputedStyle(element.querySelector('button')!).whiteSpace}
  })
  expect(bounds.widths[0]).toBe(bounds.widths[1]);expect(bounds.heights).toEqual([28,28]);expect(bounds.buttonHeight).toBe(28);expect(bounds.inside).toBe(true);expect(bounds.nowrap).toBe('nowrap')
  await more.focus();await more.press('Enter')
  const dialog=page.getByRole('dialog',{name:'Functional Groups of SYN_ALICE',exact:true})
  for(const name of [longGroup,'Finance','Engineering','Operations'])await expect(dialog).toContainText(name)
  await page.keyboard.press('Escape');await expect(more).toBeFocused()
  await cell.scrollIntoViewIfNeeded()
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
  const folder=path.resolve('../build/test-artifacts/user-directory');mkdirSync(folder,{recursive:true})
  await page.screenshot({path:path.join(folder,`functional-groups-${width}.png`)})
})
