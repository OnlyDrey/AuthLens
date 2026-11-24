import {test,expect,type Page} from '@playwright/test'

type User={id:string;username:string;display_name:string;role:string;permissions:string[];enabled:boolean;revision:number;last_login:null;theme:'light'|'dark'|'system'|null}
const account=(id:string,permissions:string[]):User=>({id,username:id,display_name:id,role:permissions.includes('admin')?'administrator':'reviewer',permissions,enabled:true,revision:1,last_login:null,theme:null})
async function session(page:Page,user:User){
 await page.route('**/api/auth/state',route=>route.fulfill({json:{provider:'local-sessions',setup_required:false}}))
 await page.route('**/api/auth/me',route=>route.fulfill({json:user}))
 await page.route('**/api/auth/preferences/theme',route=>{user.theme=route.request().postDataJSON().theme;return route.fulfill({json:user})})
 await page.goto('/')
 await expect(page.getByRole('button',{name:'My Profile',exact:true})).toBeVisible()
}

test('reviewer theme is personal, synchronized and does not reveal administrative controls',async({page,context})=>{
 const reviewer=account('reviewer',['read','export','profile','review','approve'])
 const other=account('other',['read','export','profile','review','approve'])
 reviewer.theme='dark';other.theme='dark'
 await session(page,reviewer)
 await expect(page.getByRole('button',{name:'Open settings',exact:true})).toHaveCount(0)
 await expect(page.getByRole('button',{name:'Refresh role data from CSV',exact:true})).toHaveCount(0)
 const sameUser=await context.newPage(),otherUser=await context.newPage()
 await session(sameUser,reviewer);await session(otherUser,other)
 await page.getByRole('button',{name:'Switch to light mode',exact:true}).click()
 await expect(page.locator('html')).toHaveAttribute('data-theme','light')
 await sameUser.evaluate(()=>window.dispatchEvent(new Event('focus')))
 await expect(sameUser.locator('html')).toHaveAttribute('data-theme','light')
 await expect(otherUser.locator('html')).toHaveAttribute('data-theme','dark')
 await page.reload();await expect(page.locator('html')).toHaveAttribute('data-theme','light')
 expect(other.theme).toBe('dark')
})

test('effective permissions control administrative actions and update on session refresh',async({page})=>{
 const user=account('administrator',['read','export','profile','review','approve','admin','accounts'])
 await session(page,user)
 await expect(page.getByRole('button',{name:'Open settings',exact:true})).toBeVisible()
 await expect(page.getByRole('button',{name:'Refresh role data from CSV',exact:true})).toBeVisible()
 user.permissions=['read','export','profile','review','approve'];user.role='reviewer'
 await page.evaluate(()=>window.dispatchEvent(new Event('focus')))
 await expect(page.getByRole('button',{name:'Open settings',exact:true})).toHaveCount(0)
 await expect(page.getByRole('button',{name:'Refresh role data from CSV',exact:true})).toHaveCount(0)
 await expect(page.getByRole('button',{name:'My Profile',exact:true})).toBeVisible()
})
