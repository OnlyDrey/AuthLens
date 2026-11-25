import {test,expect,type Page} from '@playwright/test'
import {cleanup,headers,seedGovernance} from './sod-fixture'

// WP33 UI contract (FILE-001 to FILE-006, FILE-010). The disposable browser host is Desktop, so the Server runtime and the host endpoints are
// mocked here; the real policy, browsing and import behavior is covered by ServerSourceBrowserTests, ServerSourcePolicyTests and DataSourcesTests.
const SOURCES=['Role Catalogue','User Access','SoD Matrix','Employee Directory']
async function serverSettings(page:Page,request:import('@playwright/test').APIRequestContext){
 const configuration=(await(await request.get('/api/configuration',{headers})).json()).settings
 configuration.features.employee_directory=true
 expect((await request.post('/api/configuration',{headers,data:configuration})).ok()).toBeTruthy()
 await page.route('**/api/runtime',async route=>{const response=await route.fetch(),body=await response.json();await route.fulfill({json:{...body,deployment_mode:'server',browser_upload:true}})})
}
async function openSources(page:Page){
 await page.goto('/#session=browser-test-session')
 await page.getByRole('button',{name:'Open settings',exact:true}).click()
 await page.getByRole('tab',{name:'Data Sources',exact:true}).click()
}

test('every source uses one host-file workflow: typed or browsed path, detected type, approval only when needed, hash-bound import',async({page,request})=>{
 const directory=await seedGovernance(request,'static')
 try{
  await serverSettings(page,request)
  let authorizations=0,validations=0;const activations:{path:string;validated_sha256?:string}[]=[]
  await page.route(/\/api\/server\/sources\/(roles|users|employees|sod)(\/authorize|\/validate)?$/,async route=>{
   const url=route.request().url()
   if(url.endsWith('/authorize')){expect(route.request().postDataJSON().approve_host_access).toBe(true);authorizations++;await route.fulfill({json:{authorized:true}})}
   else if(url.endsWith('/validate')){
    validations++
    const path=route.request().postDataJSON().path as string
    // Outside an approved folder and not yet authorized: the server refuses with the policy category.
    if(path.includes('unapproved')&&!authorizations)await route.fulfill({status:400,json:{detail:'Server source paths prohibited by policy.',category:'policy_prohibited',previous_preserved:true}})
    else await route.fulfill({json:{records:3,sha256:'a'.repeat(64),revision:route.request().postDataJSON().revision,message:'Validated without activation.'}})
   }
   else await route.fulfill({json:{path:'',host:'SYNTHETIC-HOST',authorization:'none'}})
  })
  await page.route(/\/api\/data-sources\/(roles|users|employees|sod)\/select$/,async route=>{activations.push(route.request().postDataJSON());await route.fulfill({status:400,json:{detail:'Synthetic activation stop.'}})})
  await openSources(page)
  for(const [index,label] of SOURCES.entries()){
   await page.getByRole('tab',{name:label,exact:true}).click()
   const area=page.getByRole('region',{name:`${label} source management`,exact:true})
   await expect(area.getByRole('combobox',{name:'Source type'})).toHaveCount(0)               // no early local/UNC/upload choice
   await area.getByRole('radio',{name:/File on the AuthLens host/}).check()
   const field=area.getByLabel('File on SYNTHETIC-HOST',{exact:true})
   // Typing reads nothing and contacts nothing; the type is detected from the path.
   await field.fill('\\\\fileserver.example.org\\exports\\source.csv');await field.press('Tab')
   await expect(area.getByText('Network file',{exact:true})).toBeVisible()
   await field.fill('D:\\Exports\\source.csv')
   await expect(area.getByText('Local file on the host',{exact:true})).toBeVisible()
   expect(validations).toBe(index*3)
   // A file in an approved folder validates directly: no exact authorization request.
   const before=authorizations
   await area.getByRole('button',{name:'Validate only',exact:true}).click()
   await expect(area.getByRole('status').filter({hasText:'Validated: 3 records'})).toBeVisible()
   expect(authorizations).toBe(before)
   const importValidated=area.getByRole('button',{name:'Import validated file',exact:true})
   await expect(importValidated).toBeVisible()
   await field.fill('D:\\Exports\\changed.csv')
   await expect(importValidated).toHaveCount(0)                                                // stale validation cannot import other content
   // A file outside approved folders asks for explicit approval of the exact file, then imports exactly the validated content.
   authorizations=0
   await field.fill('D:\\Elsewhere\\unapproved.csv')
   await area.getByRole('button',{name:'Validate and import',exact:true}).click()
   await expect(area.getByRole('alert')).toContainText('not in an approved folder')
   await expect(area.getByRole('button',{name:'Validate and import',exact:true})).toBeDisabled()
   await area.getByRole('checkbox',{name:/I authorize AuthLens to read this exact file/}).check()
   await area.getByRole('button',{name:'Validate and import',exact:true}).click()
   await expect.poll(()=>activations.length).toBe(index+1)
   expect(authorizations).toBe(1)
   expect(activations[index]).toMatchObject({path:'D:\\Elsewhere\\unapproved.csv',validated_sha256:'a'.repeat(64)})
   await area.getByRole('radio',{name:/Upload from this device/}).check()
   await expect(area.getByRole('button',{name:'Browse / Upload file',exact:true})).toBeVisible()
  }
  expect(activations).toHaveLength(4)
 }finally{await cleanup(request,directory)}
})

test('the host file picker browses the AuthLens host, selects a CSV, explains refusals and approves a folder explicitly',async({page,request})=>{
 const directory=await seedGovernance(request,'static')
 try{
  await serverSettings(page,request)
  await page.route(/\/api\/server\/sources\/(roles|users|employees|sod)$/,route=>route.fulfill({json:{path:'',host:'SYNTHETIC-HOST',authorization:'none'}}))
  let approved=false
  const listing=(path:string)=>({host:'SYNTHETIC-HOST',path,root:'D:\\Exports',parent:path==='D:\\Exports'?null:'D:\\Exports',network:false,truncated:false,
   breadcrumbs:path==='D:\\Exports'?[{name:'Exports',path:'D:\\Exports'}]:[{name:'Exports',path:'D:\\Exports'},{name:'2026',path:'D:\\Exports\\2026'}],
   entries:path==='D:\\Exports'?[{name:'2026',path:'D:\\Exports\\2026',kind:'directory',size:null,modified:null,supported:false},{name:'users.csv',path:'D:\\Exports\\users.csv',kind:'file',size:2048,modified:'2026-11-25T10:00:00Z',supported:true}]
    :[{name:'employees.csv',path:'D:\\Exports\\2026\\employees.csv',kind:'file',size:900,modified:'2026-11-24T08:00:00Z',supported:true}]})
  await page.route(/\/api\/server\/sources\/browse(\?.*)?$/,async route=>{
   const path=new URL(route.request().url()).searchParams.get('path')
   if(!path)return route.fulfill({json:{host:'SYNTHETIC-HOST',locations:[{name:'Exports',path:'D:\\Exports',kind:'approved',network:false},{name:'exports',path:'\\\\fileserver.example.org\\share\\exports',kind:'operator',network:true}]}})
   if(path.startsWith('\\\\'))return route.fulfill({status:403,json:{detail:'The AuthLens service identity cannot list this folder.',category:'access_denied'}})
   if(path.startsWith('E:')&&!approved)return route.fulfill({status:403,json:{detail:'This folder is not approved for browsing.',category:'not_approved'}})
   return route.fulfill({json:listing(path.startsWith('E:')?'D:\\Exports':path)})
  })
  await page.route(/\/api\/server\/sources\/roots(\?.*)?$/,async route=>{
   if(route.request().method()==='POST'){expect(route.request().postDataJSON()).toEqual({path:'E:\\Drop',approve_folder_access:true});approved=true;return route.fulfill({json:{approved:true,path:'E:\\Drop'}})}
   return route.fulfill({json:{approved:approved?['E:\\Drop']:[],operator_roots:[],max:16}})
  })
  await page.setViewportSize({width:1280,height:900})
  await openSources(page)
  await page.getByRole('tab',{name:'User Access',exact:true}).click()
  const area=page.getByRole('region',{name:'User Access source management',exact:true})
  await area.getByRole('radio',{name:/File on the AuthLens host/}).check()
  await area.getByRole('button',{name:'Browse host…',exact:true}).click()
  const picker=page.getByRole('dialog',{name:'Select a file on the AuthLens host'})
  await expect(picker).toContainText('SYNTHETIC-HOST')
  await expect(picker.getByRole('button',{name:'Select',exact:true})).toBeDisabled()
  await picker.getByRole('button',{name:/Exports Approved folder/}).click()
  await expect(picker.getByRole('region',{name:'Contents of D:\\Exports'})).toBeVisible()
  await picker.getByRole('button',{name:'Open folder 2026'}).click()
  await expect(picker.getByRole('navigation',{name:'Folder path'})).toContainText('2026')
  await picker.getByRole('button',{name:'Parent folder'}).click()
  await picker.getByRole('button',{name:'Select file users.csv'}).click()
  await expect(picker.getByText('Selected:')).toBeVisible()
  // A network location the service cannot read explains the Windows permission; nothing is selected.
  await picker.getByRole('button',{name:/exports Operator folder/}).click()
  await expect(picker.getByRole('alert')).toContainText('service identity cannot list')
  // An unapproved folder entered directly needs explicit approval, then lists.
  await picker.getByLabel('Folder or file path',{exact:true}).fill('E:\\Drop')
  await picker.getByRole('button',{name:'Open',exact:true}).click()
  await expect(picker.getByRole('alert')).toContainText('not approved for browsing')
  await expect(picker.getByRole('button',{name:'Approve folder',exact:true})).toBeDisabled()
  await picker.getByRole('checkbox',{name:/I approve AuthLens to list and read CSV files below/}).check()
  await picker.getByRole('button',{name:'Approve folder',exact:true}).click()
  await expect(picker.getByRole('status').filter({hasText:'Approved E:\\Drop'})).toBeVisible()
  await picker.getByRole('button',{name:'Select file users.csv'}).click()
  await picker.getByRole('button',{name:'Select',exact:true}).click()
  await expect(picker).toHaveCount(0)
  await expect(area.getByLabel('File on SYNTHETIC-HOST',{exact:true})).toHaveValue('D:\\Exports\\users.csv')
  // Mobile: the same picker fits the viewport without horizontal page scroll.
  await page.setViewportSize({width:390,height:844})
  await area.getByRole('button',{name:'Browse host…',exact:true}).click()
  await expect(picker).toBeVisible()
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1)).toBe(true)
  await picker.getByRole('button',{name:'Cancel',exact:true}).click()
 }finally{await cleanup(request,directory)}
})

test('changing the update mode keeps the configured file and active data and says when it takes effect',async({page,request})=>{
 const directory=await seedGovernance(request,'static')
 try{
  await serverSettings(page,request)
  await page.route(/\/api\/server\/sources\/(roles|users|employees|sod)$/,route=>route.fulfill({json:{path:'D:\\Exports\\users.csv',host:'SYNTHETIC-HOST',authorization:'approved_folder'}}))
  await openSources(page)
  await page.getByRole('tab',{name:'User Access',exact:true}).click()
  const area=page.getByRole('region',{name:'User Access source management',exact:true})
  await area.getByRole('radio',{name:/File on the AuthLens host/}).check()
  const mode=area.getByLabel('Update mode',{exact:true})
  const current=await mode.inputValue()
  await mode.selectOption(current==='static'?'dynamic':'static')
  await expect(area.getByText(/Save settings to apply the mode change\. Saving reads nothing now and keeps the active data/)).toBeVisible()
  await expect(area.getByLabel('File on SYNTHETIC-HOST',{exact:true})).toHaveValue('D:\\Exports\\users.csv')   // no reselection needed
  await area.getByRole('radio',{name:/Upload from this device/}).check()
  await mode.selectOption('dynamic')
  await expect(area.getByText(/An uploaded copy cannot follow changes on the device it came from/)).toBeVisible()
 }finally{await cleanup(request,directory)}
})
