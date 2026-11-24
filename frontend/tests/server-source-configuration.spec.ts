import {test,expect} from '@playwright/test'
import {cleanup,headers,seedGovernance} from './sod-fixture'

// UI contract test: the disposable browser host is Desktop. Real Server policy/import behavior is tested in DataSourcesTests.
test('all source panels require explicit server authority and complete validation before activation',async({page,request})=>{
 const directory=await seedGovernance(request,'static')
 try{
  const configuration=(await(await request.get('/api/configuration',{headers})).json()).settings
  configuration.features.employee_directory=true
  expect((await request.post('/api/configuration',{headers,data:configuration})).ok()).toBeTruthy()
  let authorizations=0,validations=0
  await page.route('**/api/runtime',async route=>{
   const response=await route.fetch(),body=await response.json()
   await route.fulfill({json:{...body,deployment_mode:'server',browser_upload:true}})
  })
  await page.route(/\/api\/server\/sources\/(roles|users|employees|sod)(\/authorize|\/validate)?$/,async route=>{
   const url=route.request().url()
   if(url.endsWith('/authorize')){expect(route.request().postDataJSON().approve_host_access).toBe(true);authorizations++;await route.fulfill({json:{authorized:true}})}
   else if(url.endsWith('/validate')){validations++;await route.fulfill({json:{records:3,sha256:'a'.repeat(64),revision:route.request().postDataJSON().revision,message:'Validated without activation.'}})}
   else await route.fulfill({json:{path:'',host:'SYNTHETIC-HOST',authorization:'none'}})
  })
  await page.goto('/#session=browser-test-session')
  await page.getByRole('button',{name:'Open settings',exact:true}).click()
  await page.getByRole('tab',{name:'Data Sources',exact:true}).click()
  for(const [index,label] of ['Role Catalogue','User Access','SoD Matrix','Employee Directory'].entries()){
   await page.getByRole('tab',{name:label,exact:true}).click()
   const area=page.getByRole('region',{name:`${label} source management`,exact:true})
   await area.getByLabel('Source type',{exact:true}).selectOption('local')
   const field=area.getByLabel('Local server CSV path',{exact:true})
   await field.fill('C:\\Data\\AuthLens\\source.csv');await field.press('Tab')
   expect(authorizations).toBe(index);expect(validations).toBe(index)
   const validate=area.getByRole('button',{name:'Test connection and validate source',exact:true})
   const activate=area.getByRole('button',{name:'Activate validated source',exact:true})
   await expect(validate).toBeDisabled();await expect(activate).toBeDisabled()
   await area.getByRole('checkbox',{name:/I authorize AuthLens/}).check()
   await validate.click();await expect(activate).toBeEnabled()
   await expect(area.getByRole('status').filter({hasText:'3 records validated'})).toBeVisible()
   await field.fill('C:\\Data\\AuthLens\\changed.csv');await expect(activate).toBeDisabled()
   await area.getByLabel('Source type',{exact:true}).selectOption('unc')
   await expect(area.getByLabel('Network CSV path (UNC)',{exact:true})).toBeVisible()
   await expect(area.getByText(/authenticate to the named enterprise SMB/)).toBeVisible()
   await area.getByLabel('Source type',{exact:true}).selectOption('upload')
   await expect(area.getByRole('button',{name:'Browse / Upload file',exact:true})).toBeVisible()
  }
  expect(authorizations).toBe(4);expect(validations).toBe(4)
 }finally{await cleanup(request,directory)}
})
