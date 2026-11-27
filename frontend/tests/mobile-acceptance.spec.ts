import {test,expect} from '@playwright/test'
import {readFileSync,mkdirSync} from 'node:fs'
import path from 'node:path'
import {seedGovernance,cleanup,headers} from './sod-fixture'
import {selectSettingsSection,parseDelimited} from './support'

let directory=''
test.beforeEach(async({request})=>{directory=await seedGovernance(request,'static',undefined,true)})
test.afterEach(async({request})=>{await cleanup(request,directory)})

test('mobile header tools and independent settings drawer retain icons and keyboard isolation',async({page})=>{
  await page.setViewportSize({width:390,height:844});await page.goto('/#session=browser-test-session')
  const header=page.getByRole('banner')
  for(const name of ['Open settings','Refresh role data from CSV','Reviewer profile'])await expect(header.getByRole('button',{name,exact:true})).toBeVisible()
  await expect(header.getByRole('button',{name:/Switch to (light|dark) mode/})).toBeVisible()
  await header.getByRole('button',{name:'Open navigation',exact:true}).click()
  const navigation=page.getByRole('dialog',{name:'Navigation',exact:true})
  await expect(navigation.getByRole('link',{name:'Compare Users',exact:true})).toBeHidden()
  await navigation.locator('summary').filter({hasText:'Users'}).click()
  await expect(navigation.getByRole('link',{name:'Compare Users',exact:true})).toBeVisible()
  await page.keyboard.press('Escape');await header.getByRole('button',{name:'Open settings',exact:true}).click()
  const trigger=page.getByRole('button',{name:/^Settings sections:/});await trigger.click()
  const settings=page.getByRole('dialog',{name:'Settings sections',exact:true})
  await expect(page.getByRole('dialog',{name:'Navigation',exact:true})).toHaveCount(0)
  await expect(header.getByRole('button',{name:'Open navigation',exact:true})).toBeDisabled()
  await expect(settings.getByRole('button',{name:'Data Sources',exact:true}).locator('svg')).toHaveCount(1)
  for(const label of ['Organization & SAP System','Data Sources','Health & Diagnostics'])await expect(settings.getByRole('button',{name:label,exact:true}).locator('span')).toBeVisible()
  await page.keyboard.press('Escape');await expect(trigger).toBeFocused()
  await selectSettingsSection(page,'Appearance & Branding');await expect(page.locator('#settings-heading')).toHaveText('Appearance & Branding')
  await expect(page.locator('#settings-heading')).toBeFocused()
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
})

test('mobile sign-in and reset controls have icons and fit the viewport',async({page})=>{
  await page.route('**/api/auth/state',route=>route.fulfill({json:{provider:'local-sessions',setup_required:false}}))
  await page.route('**/api/auth/me',route=>route.fulfill({status:401,json:{detail:'authentication_required'}}))
  await page.setViewportSize({width:360,height:800});await page.goto('/#session=browser-test-session')
  await expect(page.getByRole('button',{name:'Sign in',exact:true}).locator('svg')).toHaveCount(1)
  const reset=page.getByRole('button',{name:'Use password reset code',exact:true});await expect(reset.locator('svg')).toHaveCount(1)
  const bounds=(await reset.boundingBox())!;expect(Math.abs(bounds.x+bounds.width/2-180)).toBeLessThanOrEqual(2)
  await reset.click();await expect(page.getByRole('button',{name:'Set password',exact:true}).locator('svg')).toHaveCount(1)
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
  await page.getByRole('button',{name:'Back to sign in',exact:true}).click()
  let release!:()=>void;const pending=new Promise<void>(resolve=>{release=resolve})
  await page.route('**/api/auth/login',async route=>{await pending;await route.fulfill({status:401,json:{detail:'invalid_credentials',code:'invalid_credentials'}})})
  try{
    await page.getByLabel('Username',{exact:true}).fill('synthetic-user')
    await page.getByLabel('Password',{exact:true}).fill('synthetic-wrong-password')
    const submit=page.getByRole('button',{name:'Sign in',exact:true});await submit.click()
    await expect(submit).toHaveAttribute('aria-busy','true');await expect(submit.locator('svg')).toHaveCount(1)
    release();await expect(submit).toBeEnabled()
  }finally{release()}
})

test('mobile role and exact-user searches belong to focus-isolated Filters',async({page})=>{
  await page.setViewportSize({width:390,height:844});await page.goto('/#session=browser-test-session');await page.goto('/#/role-lookup')
  await expect(page.getByRole('searchbox',{name:'Search roles by name or description',exact:true})).toBeHidden()
  await page.getByRole('button',{name:'Filters',exact:true}).click()
  const filters=page.getByRole('dialog',{name:'Filters',exact:true})
  await expect(filters.getByRole('searchbox',{name:'Search roles by name or description',exact:true})).toBeVisible()
  await expect(filters.getByRole('group',{name:'SAP areas',exact:true})).toBeVisible()
  await expect(page.locator('body')).toHaveCSS('overflow','hidden')
  await page.keyboard.press('Escape');await page.goto('/#/users')
  await expect(page.getByRole('textbox',{name:'Search users',exact:true})).toBeHidden()
  await page.getByRole('button',{name:'Filters',exact:true}).click()
  await expect(filters.getByRole('textbox',{name:'Search users',exact:true})).toBeVisible()
  await expect(filters.getByRole('textbox',{name:'Exact usernames',exact:true})).toBeVisible()
  await expect(page.locator('#exact-usernames-help')).toHaveCount(1)
  await filters.getByRole('button',{name:'Show results',exact:true}).click();await expect(filters).toHaveCount(0)
  await page.getByRole('button',{name:'Filters',exact:true}).click();await page.setViewportSize({width:1280,height:900})
  await expect(filters).toHaveCount(0);await page.setViewportSize({width:390,height:844});await expect(filters).toHaveCount(0)
})

for(const width of [375,800,1280,1600])test(`responsive surface screenshots at ${width}px`,async({page,request})=>{
  const output=path.resolve('../build/test-artifacts/mobile-acceptance/screenshots');mkdirSync(output,{recursive:true})
  await page.setViewportSize({width,height:900});await page.goto('/#session=browser-test-session')
  for(const theme of ['light','dark']){
    expect((await request.post('/api/configuration/theme',{headers,data:{theme}})).ok()).toBe(true);await page.reload()
    await expect(page.locator('html')).toHaveAttribute('data-theme',theme)
    if(width<1024){
      await page.getByRole('button',{name:'Open navigation',exact:true}).click()
      const navigation=page.getByRole('dialog',{name:'Navigation',exact:true})
      const summary=navigation.locator('summary').filter({hasText:'SoD'});if(await summary.locator('..').getAttribute('open')===null)await summary.click()
      await page.screenshot({animations:'disabled',path:path.join(output,`navigation-${width}-${theme}.png`)});await page.keyboard.press('Escape')
    }
    await page.goto('/#/role-lookup');await page.getByRole('button',{name:width<1024?'Filters':'Hide filters',exact:true}).click()
    if(width>=1024)await page.getByRole('button',{name:'Filters',exact:true}).click()
    await expect(page.getByRole('searchbox',{name:'Search roles by name or description',exact:true})).toBeVisible()
    await page.screenshot({animations:'disabled',path:path.join(output,`filters-${width}-${theme}.png`)})
    if(width<1024)await page.keyboard.press('Escape')
    await page.goto('/#/users');await expect(page.getByRole('region',{name:'User directory table',exact:true})).toBeVisible()
    await page.getByRole('button',{name:'Columns for User directory',exact:true}).click() // TBL-02: in the table frame's toolbar above the scroll region
    const columns=page.getByRole('dialog',{name:/^Columns for/});await expect(columns).toBeVisible()
    await page.screenshot({animations:'disabled',path:path.join(output,`columns-${width}-${theme}.png`)});await columns.getByRole('button',{name:'Done',exact:true}).click()
    await page.getByRole('button',{name:'Open settings',exact:true}).click();await selectSettingsSection(page,'Health & Diagnostics')
    await page.screenshot({animations:'disabled',path:path.join(output,`health-${width}-${theme}.png`)})
    if(width<768){await page.getByRole('button',{name:/^Settings sections:/}).click();await page.screenshot({animations:'disabled',path:path.join(output,`settings-navigation-${width}-${theme}.png`)});await page.keyboard.press('Escape')}
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
    await page.getByRole('button',{name:'Back to AuthLens',exact:true}).click()
  }
})

test('table columns persist, reorder reading order and export visible or all displayed-row fields',async({page})=>{
  await page.setViewportSize({width:390,height:844});await page.goto('/#session=browser-test-session');await page.goto('/#/users')
  const table=page.getByRole('region',{name:'User directory table',exact:true})
  await expect(table.getByRole('columnheader',{name:'Email',exact:true})).toBeVisible()
  await page.getByRole('button',{name:'Columns for User directory',exact:true}).click() // TBL-02: in the table frame's toolbar above the scroll region
  const dialog=page.getByRole('dialog',{name:/^Columns for/})
  await dialog.getByLabel('Email',{exact:true}).uncheck();await dialog.getByRole('button',{name:'Move Department up',exact:true}).click()
  const visible=page.waitForEvent('download');await dialog.getByRole('button',{name:'Export visible columns',exact:true}).click()
  const exported=parseDelimited(readFileSync((await(await visible).path())!,'utf8'));expect(exported.length).toBeGreaterThan(0)
  expect(Object.keys(exported[0])).toContain('Username');expect(Object.keys(exported[0])).not.toContain('Email')
  expect(Object.keys(exported[0]).indexOf('Department')).toBeLessThan(Object.keys(exported[0]).indexOf('Job title'))
  const all=page.waitForEvent('download');await dialog.getByRole('button',{name:'Export all columns',exact:true}).click()
  const complete=parseDelimited(readFileSync((await(await all).path())!,'utf8'));expect(Object.keys(complete[0])).toContain('Email')
  await dialog.getByRole('button',{name:'Done',exact:true}).click();await page.reload()
  await expect(table.getByRole('columnheader',{name:'Email',exact:true})).toHaveCount(0)
  expect(await table.locator('tbody td[data-column-index]').first().evaluate(cell=>getComputedStyle(cell).whiteSpace)).toBe('nowrap')
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
})

// The heatmap is an SoD analysis visualization; it moved off the review pages (Reviews workspace) and is checked on SoD Overview.
test('SoD heatmap keeps its corner heading opaque and visible after horizontal scrolling',async({page})=>{
  await page.setViewportSize({width:390,height:844});await page.goto('/#session=browser-test-session');await page.goto('/#/sod')
  const region=page.getByRole('region',{name:'SAP user group heatmap',exact:true})
  const scroll=region.locator('.sod-heatmap-scroll');await expect(scroll).toBeVisible()
  const corner=scroll.locator('thead th').first();const label=await corner.innerText()
  await scroll.evaluate(element=>{element.scrollLeft=element.scrollWidth})
  await expect(corner).toHaveText(label)
  const r=(await scroll.boundingBox())!,c=(await corner.boundingBox())!
  expect(c.x).toBeGreaterThanOrEqual(r.x-1);expect(c.x).toBeLessThan(r.x+10)
  expect(await corner.evaluate(element=>getComputedStyle(element).backgroundColor)).not.toBe('rgba(0, 0, 0, 0)')
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
  const output=path.resolve('../build/test-artifacts/mobile-acceptance');mkdirSync(output,{recursive:true})
  await page.screenshot({animations:'disabled',path:path.join(output,'sod-heatmap-390-scrolled.png')})
})

test('virtualized matrix column choices have a separate scoped export and persist',async({page})=>{
  await page.setViewportSize({width:390,height:844});await page.goto('/#session=browser-test-session');await page.goto('/#/sod/risk-matrix')
  await expect(page.getByRole('region',{name:/Scrollable User by risk matrix/})).toBeVisible()
  await page.getByRole('button',{name:'Columns for User by risk matrix',exact:true}).click()
  const dialog=page.getByRole('dialog',{name:'Columns for User by risk matrix',exact:true})
  const fields=await dialog.locator('.table-column-options label').allTextContents();expect(fields.length).toBeGreaterThan(1)
  await dialog.getByLabel(fields[0],{exact:true}).uncheck()
  const visible=page.waitForEvent('download');await dialog.getByRole('button',{name:'Export visible columns',exact:true}).click()
  const exported=parseDelimited(readFileSync((await(await visible).path())!,'utf8'));expect(exported.length).toBeGreaterThan(0)
  expect(Object.keys(exported[0])).not.toContain(fields[0])
  const all=page.waitForEvent('download');await dialog.getByRole('button',{name:'Export all columns',exact:true}).click()
  const complete=parseDelimited(readFileSync((await(await all).path())!,'utf8'));expect(Object.keys(complete[0])).toContain(fields[0])
  await dialog.getByRole('button',{name:'Done',exact:true}).click();await page.reload()
  await page.getByRole('button',{name:'Columns for User by risk matrix',exact:true}).click()
  await expect(dialog.getByLabel(fields[0],{exact:true})).not.toBeChecked()
})

test('touch emulation keeps header targets usable and drawer interactions distinct',async({browser})=>{
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,deviceScaleFactor:2,baseURL:`http://127.0.0.1:${process.env.AUTHLENS_BROWSER_TEST_PORT||18745}`,extraHTTPHeaders:{'X-SAP-Lens-Token':'synthetic-browser-capability-0000000000000000'}})
  try{
    const page=await context.newPage();await page.goto('/#session=browser-test-session')
    expect(await page.evaluate(()=>matchMedia('(pointer: coarse)').matches)).toBe(true)
    for(const name of ['Open navigation','Open settings','Reviewer profile','Refresh role data from CSV']){
      const bounds=(await page.getByRole('button',{name,exact:true}).boundingBox())!;expect(bounds.width).toBeGreaterThanOrEqual(44);expect(bounds.height).toBeGreaterThanOrEqual(44)
    }
    await page.getByRole('button',{name:'Open navigation',exact:true}).tap()
    const navigation=page.getByRole('dialog',{name:'Navigation',exact:true});await navigation.locator('summary').filter({hasText:'Users'}).tap()
    await navigation.getByRole('link',{name:'User Directory',exact:true}).tap();await expect(navigation).toHaveCount(0)
    await expect(page.getByRole('heading',{name:'Users',exact:true})).toBeVisible()
    await page.getByRole('button',{name:'Filters',exact:true}).tap();await expect(page.getByRole('dialog',{name:'Filters',exact:true})).toBeVisible()
    await page.getByRole('button',{name:'Show results',exact:true}).tap()
    await page.getByRole('button',{name:'Open settings',exact:true}).tap();await page.getByRole('button',{name:/^Settings sections:/}).tap()
    await expect(page.getByRole('dialog',{name:'Settings sections',exact:true})).toBeVisible()
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
  }finally{await context.close()}
})

for(const width of [375,800])test(`all Settings sections fit ${width}px in both themes without clipping controls`,async({page,request})=>{
  await page.setViewportSize({width,height:900});await page.goto('/#session=browser-test-session')
  const sections=['Organization & SAP System','Appearance & Branding','Data Sources','SAP Modules','Runtime & Scheduling','Functional Groups','SoD Risk Configuration','Backup & Restore','Health & Diagnostics','Features','Component Library','About AuthLens']
  for(const theme of ['light','dark']){
    expect((await request.post('/api/configuration/theme',{headers,data:{theme}})).ok()).toBe(true);await page.reload()
    await page.getByRole('button',{name:'Open settings',exact:true}).click()
    for(const section of sections){
      await selectSettingsSection(page,section);await expect(page.locator('#settings-heading')).toHaveText(section)
      await expect(page.getByRole('status').filter({hasText:/^Loading (component previews|settings|local records)/})).toHaveCount(0)
      if(section==='Component Library')await expect(page.getByLabel('Component Library previews',{exact:true})).toBeVisible()
      const content=page.locator('.settings-content')
      const geometry=await content.evaluate(element=>{
        const outer=element.getBoundingClientRect()
        return {width:element.clientWidth,scroll:element.scrollWidth,offenders:[...element.querySelectorAll<HTMLElement>('*')].filter(node=>{const bounds=node.getBoundingClientRect();return bounds.width>0&&(bounds.right>outer.right+1||bounds.left<outer.left-1)&&!node.closest('.access-table,.matrix-scroll')}).slice(0,16).map(node=>({tag:node.tagName,classes:typeof node.className==='string'?node.className:'svg',width:node.getBoundingClientRect().width,scroll:node.scrollWidth,parent:node.parentElement?.className}))}
      })
      if(geometry.scroll>geometry.width+1){await test.info().attach('layout-overflow.json',{body:JSON.stringify({section,theme,...geometry},null,2),contentType:'application/json'});await page.screenshot({animations:'disabled',path:test.info().outputPath('inner-overflow.png')})}
      expect(geometry.scroll<=geometry.width+1,`${section} ${theme} ${JSON.stringify(geometry)}`).toBe(true)
      expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${section} ${theme} page`).toBe(true)
    }
    await page.getByRole('button',{name:'Back to AuthLens',exact:true}).click()
  }
})

test('mobile access-package preview keeps long identifiers and actions inside its panel',async({page})=>{
  await page.setViewportSize({width:375,height:844});await page.goto('/#session=browser-test-session');await page.goto('/#/role-lookup')
  await page.getByRole('button',{name:'Add to access package',exact:true}).first().click()
  await page.getByRole('button',{name:'Access package (1)',exact:true}).click()
  const panel=page.getByRole('dialog',{name:'Proposed access package',exact:true});await expect(panel).toBeVisible()
  const bounds=(await panel.boundingBox())!;expect(bounds.x).toBeGreaterThanOrEqual(0);expect(bounds.x+bounds.width).toBeLessThanOrEqual(375)
  await expect(panel.getByRole('button',{name:'Clear package',exact:true})).toBeVisible()
  expect(await panel.evaluate(element=>element.scrollWidth<=element.clientWidth+1)).toBe(true)
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true)
  const output=path.resolve('../build/test-artifacts/mobile-acceptance/screenshots');mkdirSync(output,{recursive:true})
  await page.screenshot({animations:'disabled',path:path.join(output,'access-package-375.png')})
  await page.keyboard.press('Escape');await expect(panel).toHaveCount(0)
})
