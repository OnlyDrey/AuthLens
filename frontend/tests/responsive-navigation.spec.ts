import {selectSettingsSection} from './support'
import {test,expect} from '@playwright/test'
import {mkdirSync} from 'node:fs'
import path from 'node:path'
import {seedGovernance,cleanup,headers} from './sod-fixture'

let directory=''
test.beforeEach(async({request})=>{directory=await seedGovernance(request,'static',undefined,true)})
test.afterEach(async({request})=>{await cleanup(request,directory)})
const screenshots=path.resolve('../build/test-artifacts/responsive-ui')

test('drawer component isolates focus, restores scroll, dismisses outside and on Escape @component',async({page})=>{
  await page.setViewportSize({width:390,height:844})
  await page.goto('/#session=browser-test-session')
  const trigger=page.getByRole('button',{name:'Open navigation',exact:true})
  await trigger.focus();await page.keyboard.press('Enter')
  const drawer=page.getByRole('dialog',{name:'Navigation',exact:true})
  await expect(drawer).toBeVisible()
  expect(await page.evaluate(()=>document.getElementById('root')?.inert)).toBe(true)
  expect(await page.evaluate(()=>document.body.style.overflow)).toBe('hidden')
  await page.keyboard.press('Tab');expect(await drawer.evaluate(e=>e.contains(document.activeElement))).toBe(true)
  await page.keyboard.press('Shift+Tab');expect(await drawer.evaluate(e=>e.contains(document.activeElement))).toBe(true)
  await page.keyboard.press('Escape');await expect(drawer).toHaveCount(0);await expect(trigger).toBeFocused()
  expect(await page.evaluate(()=>document.body.style.overflow)).not.toBe('hidden')
  await trigger.click();await expect(drawer).toBeVisible();await page.mouse.click(385,400)
  await expect(drawer).toHaveCount(0)
})

test('mobile routes retain all groups, active labels, keyboard navigation and close after selection',async({page})=>{
  await page.setViewportSize({width:360,height:800});await page.goto('/#session=browser-test-session')
  const trigger=page.getByRole('button',{name:'Open navigation',exact:true})
  await trigger.click();const drawer=page.getByRole('dialog',{name:'Navigation',exact:true})
  await drawer.locator('summary').filter({hasText:'Users'}).click();await drawer.locator('summary').filter({hasText:'SoD'}).click();await drawer.locator('summary').filter({hasText:'Reviews'}).click()
  for(const label of ['Dashboard','Role Lookup','User Directory','Release Access','Account Review','Position Changes','Compare Users','Risk Matrix','Work Queue','Review Periods'])await expect(drawer.getByRole('link',{name:label,exact:true})).toBeVisible()
  await expect(drawer.getByRole('link',{name:'Overview',exact:true})).toHaveCount(2) // SoD and Reviews
  await expect(drawer.getByRole('link',{name:'Dashboard',exact:true})).toHaveAttribute('aria-current','page')
  await drawer.getByRole('link',{name:'Compare Users',exact:true}).focus();await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/#\/users\/compare/);await expect(drawer).toHaveCount(0)
  await trigger.click();await expect(drawer.getByRole('link',{name:'Compare Users',exact:true})).toHaveAttribute('aria-current','page')
  await page.setViewportSize({width:1440,height:900});await expect(drawer).toHaveCount(0)
  await expect(page.getByRole('navigation',{name:'Main navigation',exact:true})).toBeVisible()
  await page.getByRole('link',{name:'Role Lookup',exact:true}).click();await expect(page.getByRole('heading',{name:'Role Lookup',exact:true})).toBeVisible()
})

test('profile icon opens a bounded keyboard-operable menu and the existing profile dialog @component',async({page})=>{
  await page.setViewportSize({width:360,height:800});await page.goto('/#session=browser-test-session')
  const trigger=page.getByRole('button',{name:'Reviewer profile',exact:true})
  await expect(trigger.locator('svg')).toHaveCount(1);expect((await trigger.innerText()).trim()).toBe('')
  await trigger.focus();await page.keyboard.press('Enter')
  const menu=page.getByRole('dialog',{name:'Reviewer profile',exact:true});await expect(menu).toBeVisible()
  const bounds=(await menu.boundingBox())!;expect(bounds.x).toBeGreaterThanOrEqual(0);expect(bounds.x+bounds.width).toBeLessThanOrEqual(360)
  await menu.getByRole('button',{name:'Edit reviewer profile'}).click()
  const profile=page.getByRole('dialog',{name:'Local reviewer profile',exact:true});await expect(profile).toBeVisible()
  const dialog=(await profile.boundingBox())!;expect(dialog.x+dialog.width).toBeLessThanOrEqual(360)
  await page.keyboard.press('Escape');await expect(profile).toHaveCount(0)
})

test('signed-in profile menu retains logout and opens no separate profile page',async({page})=>{
  let logout=false
  await page.route('**/api/auth/state',route=>route.fulfill({json:{provider:'local-sessions',setup_required:false}}))
  await page.route('**/api/auth/me',route=>logout?route.fulfill({status:401,json:{detail:'authentication_required'}}):route.fulfill({json:{id:'synthetic',username:'synthetic',display_name:'Synthetic operator',role:'administrator',permissions:['read','export','profile','review','approve','admin','accounts'],enabled:true,revision:1,last_login:null}}))
  await page.route('**/api/auth/sessions',route=>route.fulfill({json:{items:[]}}))
  await page.route('**/api/auth/logout',route=>{logout=true;return route.fulfill({json:{ok:true}})})
  await page.setViewportSize({width:390,height:844});await page.goto('/#session=browser-test-session')
  await page.getByRole('button',{name:'My Profile',exact:true}).click()
  const menu=page.getByRole('dialog',{name:'My Profile',exact:true})
  await menu.getByRole('button',{name:'Profile & sessions',exact:true}).click()
  await expect(page.getByRole('dialog',{name:'My Profile',exact:true}).getByRole('heading',{name:'Profile information'})).toBeVisible()
  await page.keyboard.press('Escape');await expect(page).toHaveURL(/#\/dashboard$/)
  await page.getByRole('button',{name:'My Profile',exact:true}).click()
  await page.getByRole('dialog',{name:'My Profile',exact:true}).getByRole('button',{name:'Sign out',exact:true}).click()
  await expect(page.getByRole('heading',{name:'Sign in to AuthLens'})).toBeVisible();expect(logout).toBe(true)
})

for(const width of [360,375,390,768,800,1024,1280,1440,1600])test(`responsive routes and screenshots at ${width}px`,async({page,request})=>{
  await page.setViewportSize({width,height:900})
  await page.goto('/#session=browser-test-session')
  for(const theme of ['light','dark']){
    expect((await request.post('/api/configuration/theme',{headers,data:{theme}})).ok()).toBe(true)
    await page.reload()
    await expect(page.locator('html')).toHaveAttribute('data-theme',theme)
    if(width<1024){
      const trigger=page.getByRole('button',{name:'Open navigation',exact:true})
      expect(await trigger.evaluate(element=>getComputedStyle(element).color)).toBe(await page.getByRole('button',{name:'Reviewer profile',exact:true}).evaluate(element=>getComputedStyle(element).color))
    }
    for(const route of ['dashboard','role-lookup','users','users/compare','users/release-access','reviews/account-review','reviews/position-changes','sod','sod/risk-matrix','sod/activity-matrix','reviews','reviews/queue','reviews/periods','reports/review']){
      await page.evaluate(route=>{location.hash='/'+route},route)
      const heading=route==='dashboard'?'Dashboard':route==='role-lookup'?'Role Lookup':route==='users'?'Users':route.endsWith('/compare')?'Compare Users':route.endsWith('/release-access')?'Release Access':route.endsWith('/account-review')?'Account Review':route.endsWith('/position-changes')?'Position Changes':route.startsWith('reviews')?'Reviews':route.startsWith('reports')?'Reports':'Segregation of Duties'
      await expect(page.getByRole('heading',{name:heading,exact:true}).first()).toBeVisible()
      await expect(page.getByRole('status').filter({hasText:/^Loading local records/})).toHaveCount(0)
      if(route==='dashboard'){
        await expect(page.getByRole('region',{name:'Review Progress',exact:true})).toBeVisible()
        await expect(page.locator('.dashboard-status[data-state="loading"],.dashboard-status[data-state="initial-load"]')).toHaveCount(0)
      }
      if(route.startsWith('sod/'))await expect(page.getByRole('navigation',{name:'SoD views',exact:true}).locator(`a[href="#/${route}"]`)).toHaveAttribute('aria-current','page')
      if(route.startsWith('reviews/'))await expect(page.getByRole('navigation',{name:'Review views',exact:true}).locator(`a[href="#/${route}"]`)).toHaveAttribute('aria-current','page')
      expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${route} ${theme}`).toBe(true)
      if([390,1440].includes(width)&&['dashboard','sod/risk-matrix'].includes(route)){
        mkdirSync(screenshots,{recursive:true});await page.screenshot({path:path.join(screenshots,`${route.replaceAll('/','-')}-${width}-${theme}.png`)})
      }
    }
    if(width<1024){
      await page.getByRole('button',{name:'Open navigation',exact:true}).click()
      mkdirSync(screenshots,{recursive:true});await page.screenshot({path:path.join(screenshots,`navigation-${width}-${theme}.png`)})
      await page.keyboard.press('Escape')
    }
    await page.getByRole('button',{name:'Open settings',exact:true}).click()
    await selectSettingsSection(page,'Health & Diagnostics')
    await expect(page.getByRole('heading',{name:'Health & Diagnostics',exact:true})).toBeVisible()
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`Settings ${theme}`).toBe(true)
    mkdirSync(screenshots,{recursive:true});await page.screenshot({path:path.join(screenshots,`settings-${width}-${theme}.png`)})
    await page.getByRole('button',{name:'Back to AuthLens',exact:true}).click()
    await expect(page.getByRole('button',{name:'Open settings',exact:true})).toBeFocused()
    expect((await(await request.get('/api/configuration',{headers})).json()).settings.refresh_schedule.enabled).toBe(false)
  }
})
