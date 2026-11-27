import {test,expect,type Page,type Locator} from '@playwright/test'
import {readFileSync} from 'node:fs'
import {seedGovernance,cleanup,names,openSod,headers} from './sod-fixture'
import {goTo,openSettings,postConfiguration} from './support'
import {setReviewerName} from './reviewer-profile'

let directory='',groupName='',otherName=''
test.beforeEach(async({request})=>{
 directory=await seedGovernance(request)
 const columns='Site;Name;SamAccountName;UserPrincipalName;Mail;Department;Title;Enabled;DistinguishedName;ManagerDN;ManagerName;ManagerSamAccountName;ManagerMail;ManagerDepartment;ManagerTitle;ManagerLookupStatus'
 const csv=columns+'\n'+['HQ','Synthetic employee','SYNTHETIC','synthetic@example.invalid','synthetic@example.invalid','Finance','Analyst','True','CN=Synthetic,OU=Staff','','','','','','','Missing'].join(';')+'\n'
 let settings=(await(await request.get('/api/configuration',{headers})).json()).settings
 expect((await request.post('/api/server/uploads/employees/activate',{headers,multipart:{file:{name:'synthetic-directory.csv',mimeType:'text/csv',buffer:Buffer.from(csv)},revision:String(settings.revision)}})).ok()).toBe(true)
 settings=(await(await request.get('/api/configuration',{headers})).json()).settings;settings.features.employee_directory=true
 expect((await postConfiguration(request,settings)).ok()).toBe(true)
 await setReviewerName(request,'Synthetic Filter Reviewer')
 groupName=`Filter owners ${names.a}`;otherName=`Filter overlap ${names.a}`
 for(const [name,users] of [[groupName,[names.a,names.b]],[otherName,[names.a]]] as const){
  const created=await request.post('/api/functional-groups',{headers,data:{name,description:'Synthetic filter coverage'}})
  expect(created.ok()).toBe(true);const group=(await created.json()).id
  for(const username of users){
   const current=await(await request.get(`/api/functional-groups/users/${username}`,{headers})).json()
   expect((await request.post('/api/functional-groups/memberships',{headers,data:{username,group_id:group,expected_revision:current.classification.revision}})).ok()).toBe(true)
  }
 }
})
test.afterEach(async({request})=>{await cleanup(request,directory)})
async function choose(scope:Page|Locator,page:Page,label:string,value:string){
 const input=scope.getByRole('combobox',{name:label,exact:true});await input.click();await input.fill(value)
 await page.getByRole('option').filter({hasText:value}).first().click();await input.press('Escape')
}

test('organizational and exact filters combine, follow SoD views and constrain exports',async({page})=>{
 await openSod(page,'Risk Matrix')
 const filters=page.getByRole('complementary',{name:'Filters',exact:true})
 await choose(filters,page,'Functional Group',groupName)
 await choose(filters,page,'Functional Group',otherName)
 await choose(filters,page,'Manager','No manager')
 await expect(page.locator('tbody th.matrix-row-head code')).toHaveCount(2)
 await filters.getByRole('textbox',{name:'Exact usernames',exact:true}).fill(`${names.a.toLowerCase()}, ${names.a}\n`)
 await filters.getByRole('button',{name:'Apply exact usernames',exact:true}).click()
 await expect(page.locator('tbody th.matrix-row-head code')).toHaveCount(1)
 for(const destination of ['Activity Matrix','Access Explorer','Reviews']){
  if(destination==='Reviews'){await page.getByRole('navigation',{name:'Main navigation',exact:true}).getByRole('link',{name:'Reviews',exact:true}).click();await page.getByRole('navigation',{name:'Review views',exact:true}).getByRole('link',{name:'Work Queue',exact:true}).click()}
  else await page.getByRole('link',{name:destination,exact:true}).click()
  await expect(filters.getByRole('textbox',{name:'Exact usernames',exact:true})).toHaveValue(names.a)
  await expect(filters.getByRole('group',{name:'Selected Functional Group',exact:true})).toContainText(groupName)
  await expect(filters.getByRole('group',{name:'Selected Functional Group',exact:true})).toContainText(otherName)
  if(destination==='Access Explorer'){
   const downloading=page.waitForEvent('download');await page.getByRole('button',{name:/Export CSV/}).first().click()
   const text=readFileSync((await(await downloading).path())!,'utf8')
   expect(text).toContain(names.a);expect(text).not.toContain(names.b)
  }
 }
 await page.getByRole('navigation',{name:'Review views',exact:true}).getByRole('link',{name:'Remediation',exact:true}).click()
 await expect(filters.getByRole('combobox',{name:'Functional Group',exact:true})).toBeVisible()
 await expect(filters.getByRole('combobox',{name:'Manager',exact:true})).toBeVisible()
 await expect(filters.getByRole('textbox',{name:'Exact usernames',exact:true})).toHaveValue(names.a)
})

test('population filters are available across user views and fit the narrow layout',async({page})=>{
 await page.goto('/#session=browser-test-session');await goTo(page,'Dashboard')
 // WP30/BUG-014: dashboard filters live in the shared, closed-by-default filter sidebar (drawer on narrow screens) and take effect on Apply.
 await page.getByRole('toolbar',{name:'Page actions',exact:true}).getByRole('button',{name:/^Filters/}).click()
 const dashboardFilters=page.getByRole('group',{name:'Dashboard filters',exact:true})
 await choose(dashboardFilters,page,'Functional Group',groupName)
 await dashboardFilters.getByRole('button',{name:'Apply filters',exact:true}).first().click()
 await page.getByRole('button',{name:/^SAP users/}).click()
 await expect(page.getByRole('group',{name:'Selected Functional Group',exact:true})).toContainText(groupName)
 await page.getByRole('navigation',{name:'Main navigation',exact:true}).getByRole('link',{name:'Reviews',exact:true}).click();await page.getByRole('navigation',{name:'Review views',exact:true}).getByRole('link',{name:'Account Review',exact:true}).click()
 await expect(page.getByRole('combobox',{name:'Functional Group',exact:true})).toBeVisible()
 await expect(page.getByRole('textbox',{name:'Exact usernames',exact:true})).toBeVisible()
 await goTo(page,'Compare Users') // NAV-2/3: a Users page, opened from Reviews through the navigation
 await expect(page.getByRole('combobox',{name:'Functional Group',exact:true})).toBeVisible()
 await goTo(page,'Release Access')
 await expect(page.getByRole('combobox',{name:'Functional Group',exact:true})).toBeVisible()
 await expect(page.getByRole('textbox',{name:'Exact usernames',exact:true})).toBeVisible()
 await openSettings(page,'Data Sources');await page.getByRole('tab',{name:'Employee Directory',exact:true}).click()
 await page.getByText('Employee Directory data preview',{exact:true}).click()
 const employees=page.getByRole('region',{name:'Employee search',exact:true})
 await expect(employees.getByRole('combobox',{name:'Functional Group',exact:true})).toBeVisible()
 await expect(employees.getByRole('textbox',{name:'Exact usernames',exact:true})).toBeVisible()
 await page.getByRole('button',{name:'Back to AuthLens',exact:true}).click();await goTo(page,'Dashboard')
 for(const theme of ['light','dark']){
  const toggle=page.getByRole('button',{name:theme==='light'?'Switch to light mode':'Switch to dark mode',exact:true})
  if(await toggle.count())await toggle.click()
  await expect(page.locator('html')).toHaveAttribute('data-theme',theme)
  for(const width of [375,800,1280,1600]){
   await page.setViewportSize({width,height:900})
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`population filters at ${width} ${theme}`).toBe(true)
  }
 }
})
