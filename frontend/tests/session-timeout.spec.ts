import {test,expect,type Page} from '@playwright/test'

// BUG-04 (inactivity warning, continue, expiry) and BUG-05 (personal theme on account switching in one browser). Account endpoints are
// mocked; the server-side expiry rules themselves are covered by the .NET AccountsTests.
type User={id:string;username:string;display_name:string;role:string;permissions:string[];enabled:boolean;revision:number;last_login:null;theme:'light'|'dark'|'system'|null}
const reviewer=(id:string,theme:User['theme']):User=>({id,username:id,display_name:id,role:'reviewer',permissions:['read','export','profile','review','approve'],enabled:true,revision:1,last_login:null,theme})
const timing=(remaining:number,reason:'inactivity'|'absolute'='inactivity')=>({now:1_000_000,idle_seconds:1800,absolute_seconds:43200,warning_seconds:300,idle_expires_at:1_000_000+remaining,absolute_expires_at:1_000_000+(reason==='absolute'?remaining:40000),expires_at:1_000_000+remaining,reason})

async function signedIn(page:Page,state:{user:User|null;remaining:number;reason?:'inactivity'|'absolute';expired?:boolean;activity:string[];continued:number}){
 await page.route('**/api/auth/state',route=>route.fulfill({json:{provider:'local-sessions',setup_required:false}}))
 await page.route('**/api/auth/me',route=>state.user&&!state.expired?route.fulfill({json:state.user}):route.fulfill({status:401,json:{detail:'authentication_required',code:'authentication_required'}}))
 await page.route('**/api/auth/session',route=>{state.activity.push(route.request().headers()['x-authlens-activity']||'');return state.expired?route.fulfill({status:401,json:{detail:'authentication_required'}}):route.fulfill({json:timing(state.remaining,state.reason)})})
 await page.route('**/api/auth/session/continue',route=>{state.continued++;state.remaining=1800;return route.fulfill({json:timing(1800)})})
 await page.goto('/')
}

test('inactivity warning appears before expiry, reads passively and continues only on request',async({page})=>{
 const state={user:reviewer('reviewer',null),remaining:240,activity:[] as string[],continued:0}
 await signedIn(page,state)
 const dialog=page.getByRole('dialog',{name:'Are you still there?'})
 await expect(dialog).toBeVisible()
 await expect(dialog.getByRole('timer')).toContainText(/Signing out in [34]:\d\d/)
 await expect(dialog).toContainText('not submitted automatically')
 expect(state.activity[0]).toBe('passive')                       // the background timing read never counts as activity
 expect(state.continued).toBe(0)
 await dialog.getByRole('button',{name:'Continue session'}).click()
 await expect(dialog).toHaveCount(0)
 expect(state.continued).toBe(1)
})

test('expiry signs out, clears protected content and explains why; the expired session is not revived',async({page})=>{
 const state={user:reviewer('reviewer',null),remaining:3,activity:[] as string[],continued:0,expired:false}
 await signedIn(page,state)
 await expect(page.getByRole('button',{name:'My Profile',exact:true})).toBeVisible()
 state.expired=true
 await expect(page.getByRole('heading',{name:'Sign in to AuthLens'})).toBeVisible({timeout:15000})
 await expect(page.getByRole('status')).toContainText('signed out after a period of inactivity')
 await expect(page.getByRole('button',{name:'My Profile',exact:true})).toHaveCount(0)
 expect(state.continued).toBe(0)
 await page.goBack().catch(()=>undefined)
 await expect(page.getByRole('button',{name:'My Profile',exact:true})).toHaveCount(0)
})

test('the absolute lifetime warning offers no continuation',async({page})=>{
 const state={user:reviewer('reviewer',null),remaining:200,reason:'absolute' as const,activity:[] as string[],continued:0}
 await signedIn(page,state)
 const dialog=page.getByRole('dialog',{name:'Session ends soon'})
 await expect(dialog).toBeVisible()
 await expect(dialog.getByRole('button',{name:'Continue session'})).toHaveCount(0)
 await expect(dialog.getByRole('button',{name:'Sign out'})).toBeVisible()
})

test('personal themes do not leak between accounts signed in one after another in the same browser',async({page})=>{
 const accounts:Record<string,User>={alice:reviewer('alice','dark'),bob:reviewer('bob','light')}
 const state={user:accounts.alice as User|null,remaining:1800,activity:[] as string[],continued:0}
 await page.route('**/api/auth/logout',route=>{state.user=null;return route.fulfill({json:{ok:true}})})
 await page.route('**/api/auth/login',route=>{state.user=accounts[route.request().postDataJSON().username];return route.fulfill({json:{...state.user,role:'reviewer'}})})
 await signedIn(page,state)
 await expect(page.locator('html')).toHaveAttribute('data-theme','dark')
 for(const [next,theme] of [['bob','light'],['alice','dark']] as const){
  await page.getByRole('button',{name:'My Profile',exact:true}).click()
  await page.getByRole('dialog',{name:'My Profile'}).getByRole('button',{name:'Sign out'}).click()
  await expect(page.getByRole('heading',{name:'Sign in to AuthLens'})).toBeVisible()
  await page.getByLabel('Username').fill(next)
  await page.getByLabel('Password',{exact:true}).fill('Synthetic password 123!')
  await page.getByRole('button',{name:'Sign in'}).click()
  await expect(page.getByRole('button',{name:'My Profile',exact:true})).toBeVisible()
  await expect(page.locator('html')).toHaveAttribute('data-theme',theme)
 }
})
