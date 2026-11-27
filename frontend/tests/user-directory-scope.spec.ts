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
async function open(page:Page){await page.goto('/#session=browser-test-session');await page.goto('/#/users');await expect(page.getByRole('heading',{name:/^User directory/})).toBeVisible()}
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

// BUG-013: a Functional Group cell is one compact line: the first group as a named pill (ellipsis, full name in title/aria) that opens its
// member list, then a "+X" pill (X = remaining groups) that opens the full list. Covers 0, 1, 2, 3 and 5 groups, a long name, a narrow column,
// 390 and 1280 px and both themes.
const groupNames=(count:number)=>[longGroup,'Finance','Engineering','Operations','Logistics'].slice(0,count)
const shortNames=(count:number)=>['Finance','Engineering','Operations'].slice(0,count)
for(const width of [390,1280])for(const theme of ['light','dark'] as const)test(`BUG-013: Functional Group cells are one line with a named pill and +X ${width} ${theme} @visual`,async({page})=>{
  await page.setViewportSize({width,height:900})
  await page.emulateMedia({colorScheme:theme})
  await page.addInitScript(value=>localStorage.setItem('sap-viz-theme',value),theme)
  let counts:Record<string,number>={SYN_ALICE:5,SYN_BOB:1,SYN_CAROL:0},names=groupNames
  await page.route('**/api/access/users?*',async route=>{
    const response=await route.fetch(),data=await response.json()
    for(const row of data.items)row.functional_groups=names(counts[row.username]??0).map((name,index)=>({id:`synthetic-${index}`,name,status:'active'}))
    await route.fulfill({response,json:data})
  })
  await page.route('**/api/functional-groups/*/members?*',route=>route.fulfill({json:{group:{id:'synthetic-0',name:longGroup,status:'active'},total:1,offset:0,limit:25,items:[
    {username:'SYN_MEMBER',full_name:'Synthetic Member',department:'Finance',title:'Buyer',identity:'matched',status:'Confirmed',confirmed_at:null,confirmed_by:'',revision:1}]}}))
  const table=page.getByRole('region',{name:'User directory table',exact:true})
  const cellOf=(user:string)=>table.getByRole('row').filter({has:page.getByRole('link',{name:user,exact:true})}).locator('[data-col="fg"]')
  const geometry=(user:string)=>cellOf(user).evaluate(element=>{
    const cell=element.getBoundingClientRect(),pills=[...element.querySelectorAll<HTMLElement>('.fg-chip')],label=element.querySelector<HTMLElement>('.fg-chip-label')
    const more=element.querySelector<HTMLElement>('.fg-chip-more'),named=pills.find(pill=>!pill.classList.contains('fg-chip-more'))
    return {tops:pills.map(pill=>Math.round(pill.getBoundingClientRect().top)),heights:pills.map(pill=>pill.getBoundingClientRect().height),
      noOverlap:!more||!named||named.getBoundingClientRect().right<=more.getBoundingClientRect().left,
      moreInside:!more||(more.getBoundingClientRect().left>=cell.left&&more.getBoundingClientRect().right<=cell.right),
      moreWhole:!more||more.scrollWidth<=more.clientWidth,labelTruncated:!!label&&label.scrollWidth>label.clientWidth,
      ellipsis:label?getComputedStyle(label).textOverflow:'',nowrap:pills.every(pill=>getComputedStyle(pill).whiteSpace==='nowrap')}
  })
  const reload=async()=>{await page.reload();await expect(page.getByRole('heading',{name:/^User directory/})).toBeVisible();await expect(cellOf('SYN_ALICE').locator('.fg-chip').first()).toBeVisible()}
  const expectCell=async(user:string,count:number,truncated:boolean)=>{
    const cell=cellOf(user)
    if(!count){await expect(cell).toContainText('Unassigned');await expect(cell.locator('.fg-chip')).toHaveCount(0);await expect(cell.getByRole('button')).toHaveCount(0);return}
    const groups=cell.getByRole('list',{name:`Functional Groups of ${user}`,exact:true}),first=names(count)[0]
    await expect(groups.getByRole('listitem')).toHaveCount(count>1?2:1)
    await expect(groups.getByRole('button',{name:`Show members of ${first}`,exact:true})).toHaveAttribute('title',first)
    const more=groups.getByRole('button',{name:`Show all ${count} Functional Groups of ${user}`,exact:true})
    if(count>1)await expect(more).toHaveText(`+${count-1}`);else await expect(more).toHaveCount(0)
    await expect(groups).not.toContainText('View groups')
    const shape=await geometry(user)
    expect(new Set(shape.tops).size).toBe(1);expect(shape.heights.every(height=>height===28)).toBe(true)
    expect(shape.noOverlap).toBe(true);expect(shape.moreInside).toBe(true);expect(shape.moreWhole).toBe(true);expect(shape.nowrap).toBe(true)
    expect(shape.ellipsis).toBe('ellipsis');expect(shape.labelTruncated).toBe(truncated)
  }
  await open(page)
  await expectCell('SYN_ALICE',5,true);await expectCell('SYN_BOB',1,true);await expectCell('SYN_CAROL',0,false)
  // Keyboard: Enter on +X lists every group; Escape returns focus to +X.
  const more=cellOf('SYN_ALICE').getByRole('button',{name:'Show all 5 Functional Groups of SYN_ALICE',exact:true})
  await more.focus();await more.press('Enter')
  const dialog=page.getByRole('dialog',{name:'Functional Groups of SYN_ALICE',exact:true})
  for(const name of groupNames(5))await expect(dialog.getByRole('button',{name:`Show members of ${name}`,exact:true})).toBeVisible()
  await page.keyboard.press('Escape');await expect(dialog).toHaveCount(0);await expect(more).toBeFocused()
  // The named pill opens the member list of that group.
  await cellOf('SYN_ALICE').getByRole('button',{name:`Show members of ${longGroup}`,exact:true}).click()
  const members=page.getByRole('dialog',{name:`Members of ${longGroup}`,exact:true})
  await expect(members).toContainText('SYN_MEMBER');await page.keyboard.press('Escape');await expect(members).toHaveCount(0)
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
  const folder=path.resolve('../build/test-artifacts/user-directory');mkdirSync(folder,{recursive:true})
  await cellOf('SYN_ALICE').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(folder,`bug-013-${width}-${theme}.png`)})
  // 2 and 3 groups with short names: one line, nothing truncated.
  counts={SYN_ALICE:3,SYN_BOB:2,SYN_CAROL:0};names=shortNames;await reload()
  await expectCell('SYN_ALICE',3,false);await expectCell('SYN_BOB',2,false)
  // Narrow column: the named pill shrinks with an ellipsis, +X keeps its full width and stays inside the cell.
  counts={SYN_ALICE:5,SYN_BOB:0,SYN_CAROL:0};names=groupNames;await reload()
  await page.addStyleTag({content:'.user-directory-table .ud-cell[data-col="fg"] > div { width:7rem; }'})
  const narrow=await geometry('SYN_ALICE')
  expect(new Set(narrow.tops).size).toBe(1);expect(narrow.noOverlap).toBe(true);expect(narrow.moreInside).toBe(true);expect(narrow.moreWhole).toBe(true);expect(narrow.labelTruncated).toBe(true)
  await page.screenshot({path:path.join(folder,`bug-013-narrow-${width}-${theme}.png`)})
})
