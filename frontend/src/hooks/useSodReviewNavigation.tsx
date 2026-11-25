import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode} from 'react'
import {useQuery} from '@tanstack/react-query'
import {fetchConfiguration} from '@/api/configuration'
import {sod} from '@/api/sod'
import {useViewHistory} from './useViewHistory'

type Navigation = {guard:(check:()=>boolean)=>()=>void;register:(user:string)=>()=>void; eligible:ReadonlySet<string>; active?:string; open:(user:string,role?:string)=>void; close:()=>void}
const Context = createContext<Navigation | null>(null)

/** One batch per rendered identity set, rather than a subject request from every table cell. */
export function SodReviewNavigationProvider({children}:{children:ReactNode}) {
 const {view,change}=useViewHistory(), context=view.sodContext||'current'
 const beforeSwitch=useRef<(()=>boolean)|null>(null)
 const guard=useCallback((check:()=>boolean)=>{beforeSwitch.current=check;return ()=>{if(beforeSwitch.current===check)beforeSwitch.current=null}},[])
 const [registrations,setRegistrations]=useState<Record<string,number>>({})
 const register=useCallback((user:string)=>{
  setRegistrations(previous=>({...previous,[user]:(previous[user]||0)+1}))
  return ()=>setRegistrations(previous=>{const next={...previous};if(next[user]>1)next[user]--;else delete next[user];return next})
 },[])
 const users=Object.keys(registrations).sort()
 const configuration=useQuery({queryKey:['configuration'],queryFn:fetchConfiguration})
 const enabled=configuration.data?.settings.features?.sod===true
 const available=useQuery({queryKey:['sod-review-subjects',context,users],enabled:enabled&&users.length>0,retry:false,queryFn:async()=>{
  const result:string[]=[]
  for(let offset=0;offset<users.length;offset+=200){
   const params=new URLSearchParams({context})
   users.slice(offset,offset+200).forEach(user=>params.append('usernames',user))
   result.push(...(await sod<{users:string[]}>('/api/sod/review-subjects',params)).users)
  }
  return result
 }})
 const eligible=useMemo(()=>new Set(enabled?available.data||[]:[]),[enabled,available.data])
 // BUG-02: a role context (Release role details) focuses that role's assignment in the same review panel; it never narrows what can be reviewed.
 const open=(user:string,role?:string)=>{if(eligible.has(user)&&(view.sodSubject?.user===user||!beforeSwitch.current||beforeSwitch.current()))change({sodSubject:role?{user,role}:{user},detailRole:null})}
 // BUG-01: the row control that opened the panel also closes it; only the review subject changes (search, filters and the selected user stay).
 const close=()=>{if(!beforeSwitch.current||beforeSwitch.current())change({sodSubject:null})}
 return <Context.Provider value={{guard,register,eligible,active:!view.detailRole&&!view.settings?view.sodSubject?.user:undefined,open,close}}>{children}</Context.Provider>
}

export function useSodReviewAction(user:string,supported=true){
 const navigation=useContext(Context), register=navigation?.register
 const identity=user.trim().toUpperCase()
 useEffect(()=>supported?register?.(identity):undefined,[register,identity,supported])
 if(!supported||!navigation?.eligible.has(identity))return undefined
 const active=navigation.active===identity
 return {active,open:(role?:string)=>navigation.open(identity,role),close:navigation.close,toggle:(role?:string)=>active?navigation.close():navigation.open(identity,role)}
}

/** The active review form owns this guard; it cannot clear a newer scope's protection. */
export function useSodReviewSwitchGuard(active:boolean){
 const navigation=useContext(Context), guard=navigation?.guard
 useEffect(()=>active?guard?.(()=>window.confirm('Discard unsaved SoD review changes?')):undefined,[active,guard])
}
