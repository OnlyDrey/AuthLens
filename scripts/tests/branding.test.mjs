import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'node:fs'
import { branding, brandingDirectory, brandingPlugin, webAssets } from '../branding.mjs'
import { icoImages, peIconImages } from '../verify-branding.mjs'

const root = new URL('../../', import.meta.url)
test('canonical branding files exist with actual PNG/ICO formats and stable generic names', () => {
  assert.deepEqual(branding, { logo: 'logo.png', favicon: 'favicon.ico', appleTouchIcon: 'apple-touch-icon.png', windowsIcon: 'app.ico', applicationImage: 'app.png', webIcon192:'icon-192.png', maskableIcon:'icon-maskable-512.png', webManifest:'site.webmanifest' })
  for (const name of Object.values(branding)) {
    const bytes = readFileSync(new URL(name, brandingDirectory))
    if(name.endsWith('.webmanifest')){assert.equal(JSON.parse(bytes).name,'AuthLens');continue}
    assert.deepEqual([...bytes.subarray(0, name.endsWith('.ico') ? 4 : 8)], name.endsWith('.ico') ? [0, 0, 1, 0] : [137, 80, 78, 71, 13, 10, 26, 10])
  }
  for (const old of ['assets/sap-lens.png', 'assets/sap-lens.ico', 'frontend/public/sap-lens.png', 'frontend/public/favicon.png'])
    assert.equal(existsSync(new URL(old, root)), false, old)
})

test('production branding emission preserves source bytes and development serves the same assets', () => {
  const plugin = brandingPlugin()
  const emitted = []
  plugin.generateBundle.call({ emitFile: file => emitted.push(file) })
  assert.deepEqual(emitted.map(file => file.fileName), webAssets.map(role=>branding[role]))
  let handler
  plugin.configureServer({ middlewares: { use: callback => { handler = callback } } })
  for (const file of emitted) {
    assert.deepEqual(file.source, readFileSync(new URL(file.fileName, brandingDirectory)))
    let body, type
    handler({ url: `/${file.fileName}?test=1` }, { setHeader: (_, value) => { type = value }, end: value => { body = value } }, () => assert.fail('asset was not served'))
    assert.equal(type, file.fileName.endsWith('.webmanifest') ? 'application/manifest+json' : file.fileName.endsWith('.ico') ? 'image/x-icon' : 'image/png')
    assert.deepEqual(body, file.source)
  }
  let next = false
  handler({ url: '/api/settings' }, {}, () => { next = true })
  assert.equal(next, true)
})

test('Windows executables and both installers reference the canonical multi-size icon', () => {
  for (const file of ['backend/src/AuthLens.Api/AuthLens.Api.csproj', 'backend/src/AuthLens.Desktop/AuthLens.Desktop.csproj', 'backend/installer/AuthLens-Desktop.iss', 'backend/installer/AuthLens-Server.iss']) {
    const text = readFileSync(new URL(file, root), 'utf8')
    assert.ok(text.includes('assets\\branding\\app.ico'), file)
    assert.ok(!text.includes('sap-lens.ico'), file)
  }
})

test('supplied icon sizes, transparent PNG dimensions and frontend links remain explicit', () => {
  assert.deepEqual(icoImages(readFileSync(new URL(branding.windowsIcon,brandingDirectory))).map(frame=>frame.width),[16,24,32,48,64,128,256])
  assert.deepEqual(icoImages(readFileSync(new URL(branding.favicon,brandingDirectory))).map(frame=>frame.width),[16,32,48])
  for(const [role,size] of [['logo',1024],['applicationImage',512],['appleTouchIcon',180],['webIcon192',192],['maskableIcon',512]]) {
    const png=readFileSync(new URL(branding[role],brandingDirectory))
    assert.equal(png.readUInt32BE(16),size); assert.equal(png.readUInt32BE(20),size)
    if(role !== 'maskableIcon') assert.equal(png[25],6)
  }
  const html=readFileSync(new URL('frontend/index.html',root),'utf8')
  assert.ok(html.includes('/favicon.ico')); assert.ok(html.includes('/apple-touch-icon.png')); assert.ok(!html.includes('favicon.png'))
  const server=readFileSync(new URL('backend/installer/AuthLens-Server.iss',root),'utf8')
  assert.match(server,/IconFilename:.*server\\AuthLens\.Api\.exe/)
  assert.match(readFileSync(new URL('backend/src/AuthLens.Desktop/MainWindow.cs',root),'utf8'),/Icon\.ExtractAssociatedIcon/)
})

test('one webmanifest reuses canonical icons without overriding the application theme or adding offline storage',()=>{
  const manifest=JSON.parse(readFileSync(new URL(branding.webManifest,brandingDirectory)))
  assert.equal(manifest.name,'AuthLens');assert.equal(manifest.short_name,'AuthLens')
  assert.equal(manifest.start_url,'/');assert.equal(manifest.scope,'/');assert.equal(manifest.display,'standalone')
  assert.equal(manifest.theme_color,undefined);assert.equal(manifest.background_color,undefined)
  assert.deepEqual(manifest.icons.map(icon=>icon.src),['/icon-192.png','/app.png','/icon-maskable-512.png'])
  for(const icon of manifest.icons){
    const bytes=readFileSync(new URL(icon.src.slice(1),brandingDirectory))
    assert.equal(icon.sizes,`${bytes.readUInt32BE(16)}x${bytes.readUInt32BE(20)}`)
    assert.equal(icon.type,'image/png')
  }
  assert.equal(manifest.icons.at(-1).purpose,'maskable')
  for(const file of ['frontend/index.html','backend/src/AuthLens.Api/wwwroot/login.html']){
    const html=readFileSync(new URL(file,root),'utf8')
    assert.equal((html.match(/rel="manifest"/g)||[]).length,1)
    assert.ok(html.includes('/site.webmanifest'));assert.ok(!html.includes('64x64'))
  }
})

test('binary icon validation refuses malformed images and non-PE files',()=>{
  assert.throws(()=>peIconImages(Buffer.alloc(64)),/Not a Windows executable/)
  const ico=Buffer.from(readFileSync(new URL(branding.windowsIcon,brandingDirectory)))
  ico.writeUInt32LE(ico.length,18)
  assert.throws(()=>icoImages(ico),/bounds/)
})
