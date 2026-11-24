import {test,expect} from '@playwright/test'
import {mkdirSync,readFileSync} from 'node:fs'
import path from 'node:path'

const screenshots=path.resolve('../build/test-artifacts/branding-v2')

test('canonical web assets and one manifest are served intact by the embedded frontend',async({request})=>{
  const response=await request.get('/site.webmanifest')
  expect(response.status()).toBe(200)
  expect(response.headers()['content-type']).toContain('application/manifest+json')
  const manifest=await response.json()
  expect(manifest.name).toBe('AuthLens')
  expect(manifest.theme_color).toBeUndefined()
  for(const file of ['logo.png','favicon.ico','apple-touch-icon.png',...manifest.icons.map((icon:{src:string})=>icon.src.slice(1))]){
    const asset=await request.get('/'+file)
    expect(asset.status(),file).toBe(200)
    expect(await asset.body(),file).toEqual(readFileSync(path.resolve('../assets/branding',file)))
  }
})

for(const theme of ['light','dark'] as const){
  test(`sign-in and header retain their ${theme} theme with approved raster branding @visual`,async({page})=>{
    mkdirSync(screenshots,{recursive:true})
    await page.setViewportSize({width:390,height:844})
    await page.emulateMedia({colorScheme:theme})
    await page.addInitScript(value=>localStorage.setItem('sap-viz-theme',value),theme)
    await page.route('**/api/auth/state',route=>route.fulfill({json:{provider:'local-sessions',setup_required:false}}))
    await page.route('**/api/auth/me',route=>route.fulfill({status:401,json:{error:'invalid_credentials'}}))
    await page.goto('/')
    await expect(page.getByRole('heading',{name:'Sign in to AuthLens'})).toBeVisible()
    const logo=page.getByRole('img',{name:'AuthLens',exact:true})
    await expect(logo).toHaveJSProperty('naturalWidth',1024)
    const box=await logo.boundingBox()
    expect(box?.width).toBe(80);expect(box?.height).toBe(80)
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
    await page.screenshot({path:path.join(screenshots,`sign-in-${theme}-390.png`)})
    await page.setViewportSize({width:1280,height:900})
    await page.screenshot({path:path.join(screenshots,`sign-in-${theme}-1280.png`)})
    await page.unroute('**/api/auth/state');await page.unroute('**/api/auth/me')
    await page.route('**/api/configuration',async route=>{
      const response=await route.fetch();const data=await response.json();data.settings.theme=theme
      await route.fulfill({response,json:data})
    })
    await page.goto('/#session=browser-test-session')
    // A fragment-only navigation does not remount the authentication gate after the synthetic sign-in preview.
    await page.reload()
    const header=page.locator('.app-brand')
    await expect(header).toBeVisible()
    await expect(header.locator('img')).toHaveAttribute('src','/logo.png')
    await expect(header.locator('img')).toHaveJSProperty('naturalWidth',1024)
    await expect(page.locator('html')).toHaveAttribute('data-theme',theme)
    await header.screenshot({path:path.join(screenshots,`header-${theme}.png`)})
  })
}

test('supplied icon and transparent-logo contact sheet at actual display sizes @visual',async({page})=>{
  mkdirSync(screenshots,{recursive:true})
  await page.setViewportSize({width:1280,height:900})
  // The Windows-only ICO is deliberately absent from web bundles; expose it only in this QA fixture.
  await page.route('**/app.ico*',route=>route.fulfill({contentType:'image/x-icon',body:readFileSync(path.resolve('../assets/branding/app.ico'))}))
  await page.goto('/login.html')
  await page.evaluate(()=>{
    document.body.replaceChildren()
    for(const [name,color] of [['light','#f0f2f7'],['dark','#111827']]){
      const panel=document.createElement('section');panel.style.cssText=`background:${color};color:${name==='light'?'#182C53':'#f1f5f9'};padding:24px;display:flex;align-items:center;flex-wrap:wrap;gap:20px`
      const title=document.createElement('h2');title.textContent=name;panel.append(title)
      for(const [asset,sizes] of [['app.ico',[16,24,32,48,256]],['favicon.ico',[16,32,48]],['logo.png',[64,80,96]],['icon-maskable-512.png',[96]]] as const){
        for(const size of sizes){
          const figure=document.createElement('figure');figure.style.margin='0'
          // Keep contact-sheet image decoding separate from the browser's special favicon cache.
          const img=document.createElement('img');img.src='/'+asset+'?branding-preview=1';img.alt=`${asset} ${size}px ${name}`;img.width=size;img.height=size;img.style.objectFit='contain'
          const caption=document.createElement('figcaption');caption.textContent=`${asset} ${size}px`;caption.style.fontSize='11px'
          figure.append(img,caption);panel.append(figure)
        }
      }
      document.body.append(panel)
    }
  })
  await expect.poll(async()=>{
    return page.locator('img').evaluateAll(images=>images.filter(image=>{
      const img=image as HTMLImageElement
      return !img.complete||!img.naturalWidth
    }).map(image=>image.getAttribute('alt')))
  }).toEqual([])
  await page.screenshot({path:path.join(screenshots,'icon-quality-light-dark.png'),fullPage:true})
})
