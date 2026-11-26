// Read-only PE/ICO verification. Never loads or executes the inspected Windows binaries.
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { resolve, join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { branding, brandingDirectory, webAssets } from './branding.mjs'
export const digest = bytes => createHash('sha256').update(bytes).digest('hex')
export function icoImages(bytes) {
  if (bytes.readUInt32LE(0) !== 0x10000) throw Error('Not a Windows ICO')
  return Array.from({length:bytes.readUInt16LE(4)}, (_,i) => {
    const offset=6+i*16, size=bytes.readUInt32LE(offset+8), start=bytes.readUInt32LE(offset+12)
    if (start+size>bytes.length || !size) throw Error('Invalid ICO image bounds')
    return {width:bytes[offset]||256,height:bytes[offset+1]||256,hash:digest(bytes.subarray(start,start+size))}
  })
}
export function peIconImages(bytes) {
  if (bytes.readUInt16LE(0)!==0x5a4d) throw Error('Not a Windows executable')
  const pe=bytes.readUInt32LE(0x3c)
  if(bytes.readUInt32LE(pe)!==0x4550) throw Error('Invalid PE signature')
  const optional=pe+24, magic=bytes.readUInt16LE(optional)
  if(![0x10b,0x20b].includes(magic)) throw Error('Unsupported PE format')
  const directories=optional+(magic===0x20b?112:96), sections=optional+bytes.readUInt16LE(pe+20)
  const rva = address => {
    for(let i=0;i<bytes.readUInt16LE(pe+6);i++) {
      const section=sections+i*40, virtual=bytes.readUInt32LE(section+12)
      if(address>=virtual && address<virtual+Math.max(bytes.readUInt32LE(section+8),bytes.readUInt32LE(section+16))) return bytes.readUInt32LE(section+20)+address-virtual
    }
    throw Error('Unmapped PE resource address')
  }
  const root=rva(bytes.readUInt32LE(directories+16)), images=[]
  function walk(relative,depth,type) {
    if(depth>3) throw Error('Invalid PE resource depth')
    const dir=root+relative, count=bytes.readUInt16LE(dir+12)+bytes.readUInt16LE(dir+14)
    for(let i=0;i<count;i++) {
      const entry=dir+16+i*8, name=bytes.readUInt32LE(entry), target=bytes.readUInt32LE(entry+4), kind=depth===0?name:type
      if(depth===0 && kind!==3) continue
      if(target&0x80000000) walk(target&0x7fffffff,depth+1,kind)
      else {
        const data=root+target, start=rva(bytes.readUInt32LE(data)), size=bytes.readUInt32LE(data+4)
        if(!size||start+size>bytes.length) throw Error('Invalid PE icon bounds')
        images.push(digest(bytes.subarray(start,start+size)))
      }
    }
  }
  walk(0,0,0)
  return images
}
export function verifyExecutable(path) {
  const expected=icoImages(readFileSync(new URL(branding.windowsIcon,brandingDirectory)))
  const actual=new Set(peIconImages(readFileSync(path)))
  for(const image of expected) if(!actual.has(image.hash)) throw Error(`${path}: missing canonical ${image.width}px icon resource`)
  return {path,icon_sizes:expected.map(image=>image.width),verified:true}
}
// WP32 Setup names (AuthLens-<version>-Desktop-Setup.exe, AuthLens-<version>-Server-Setup.exe); installer directories built before WP32 keep
// AuthLens-<version>-Setup.exe and AuthLens-Server-<version>-Setup.exe. Exactly one complete naming scheme must be present.
export function setupPrograms(installers,version) {
  const schemes=[[`AuthLens-${version}-Desktop-Setup.exe`,`AuthLens-${version}-Server-Setup.exe`],[`AuthLens-${version}-Setup.exe`,`AuthLens-Server-${version}-Setup.exe`]]
  const present=schemes.filter(names=>names.every(name=>existsSync(join(installers,name))))
  if(present.length!==1) throw Error(`Expected exactly one complete set of Setup programs in ${installers}`)
  return present[0].map(name=>join(installers,name))
}
if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const [release,installers,frontend,report]=process.argv.slice(2)
  if(!release||!installers||!frontend) throw Error('Usage: node scripts/verify-branding.mjs <release> <installer-directory> <frontend-dist>')
  const manifest=JSON.parse(readFileSync(join(release,'build-manifest.json'),'utf8'))
  const result=[join(release,'desktop/AuthLens.exe'),join(release,'server/AuthLens.Api.exe'),...setupPrograms(installers,manifest.version)].map(verifyExecutable)
  for(const part of ['desktop/AuthLens.exe','server/AuthLens.Api.exe']) {
    const binary=readFileSync(join(release,part))
    for(const role of webAssets) if(!binary.includes(readFileSync(new URL(branding[role],brandingDirectory)))) throw Error(`Missing/stale embedded ${branding[role]} in ${part}`)
  }
  for(const role of webAssets) {
    const name=branding[role]
    if(digest(readFileSync(join(frontend,name)))!==digest(readFileSync(new URL(name,brandingDirectory)))) throw Error(`Stale published frontend branding: ${name}`)
    result.push({path:join(frontend,name),verified:true})
  }
  const output=JSON.stringify({verified:true,source_sha:manifest.source_sha,results:result},null,2)
  if(report) writeFileSync(report,output,{flag:'wx'})
  console.log(output)
}
