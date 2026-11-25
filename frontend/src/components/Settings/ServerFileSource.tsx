import {useEffect,useState} from 'react'
import {useQuery} from '@tanstack/react-query'
import {apiRequest} from '@/api/client'
import type {CSVSource} from '@/api/sources'
import type {ImportProfile} from '@/api/configuration'
import {Button} from '@/components/Shared/Button'
import {FormField,Input} from '@/components/Shared/Controls'

type Authorization='none'|'managed'|'approved_root'|'exact'|'required'|'invalid'|'not_applicable'
const AUTHORITY:Record<Authorization,string>={none:'No server source is configured.',managed:'Configured source is a managed upload copy on this host.',approved_root:'Configured source is inside an operator-approved directory.',exact:'Configured source is authorized for this exact file.',required:'Configured source needs administrator authorization on this host (for example after restore or revocation). Its path, mode and last valid snapshot are retained.',invalid:'The configured path or the protected source authority was refused. Refresh fails closed; the last valid snapshot is retained. Ask the server operator to review the authority folder.',not_applicable:''}

/** Typing and initial rendering never contact a share; exact-file authorization is explicit. */
export function ServerFileSource({source,kind,revision,profile,disabled,onActivate}:{source:CSVSource;kind:'local'|'unc';revision:number;profile?:ImportProfile;disabled:boolean;onActivate:(path:string,hash:string)=>Promise<void>}) {
 const description=useQuery({queryKey:['server-source-description',source,revision],queryFn:()=>apiRequest<{path:string;host:string;authorization?:Authorization}>(`/api/server/sources/${source}`)})
 const [path,setPath]=useState(''),[approved,setApproved]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState('')
 const [validated,setValidated]=useState<{path:string;hash:string;revision:number}|null>(null)
 useEffect(()=>{setPath(description.data?.path||'');setApproved(false);setValidated(null)},[description.data?.path,source,kind])
 const profileKey=JSON.stringify(profile)
 useEffect(()=>{setValidated(null)},[profileKey,revision])
 const reset=(value:string)=>{setPath(value);setApproved(false);setValidated(null);setMessage('');setError('')}
 // importAfter: one step for the normal flow (validate, then activate exactly the validated content); without it a test that changes nothing.
 const validate=async(importAfter=false)=>{
  setBusy(true);setError('');setMessage('');setValidated(null)
  let validatedResult:{path:string;hash:string}|null=null
  try{
   const chosen=path.trim(),unc=chosen.startsWith('\\\\')
   if(kind==='unc'&&!unc||kind==='local'&&unc)throw Error('Choose the matching Local server file or Network file (UNC) source type.')
   await apiRequest(`/api/server/sources/${source}/authorize`,'POST',{path:chosen,approve_host_access:approved})
   const result=await apiRequest<{records:number;sha256:string;revision:number;message:string}>(`/api/server/sources/${source}/validate`,'POST',{path:chosen,revision,profile})
   setValidated({path:chosen,hash:result.sha256,revision:result.revision});setMessage(`${result.records.toLocaleString()} records validated. ${result.message}`)
   validatedResult={path:chosen,hash:result.sha256}
  }catch(cause){setError(cause instanceof Error?cause.message:'Source validation failed. Existing data is retained.')}
  finally{setBusy(false);void description.refetch()}
  // Activation is hash-bound and keeps the import checks (a suspicious file is held for confirmation); its feedback is shown by the source panel.
  if(importAfter&&validatedResult)await onActivate(validatedResult.path,validatedResult.hash)
 }
 const revoke=async()=>{
  setBusy(true);setError('');setMessage('');setValidated(null)
  try{await apiRequest(`/api/server/sources/${source}/authorize`,'DELETE');setMessage('Authorization revoked. The configured path, mode and last valid snapshot are retained; live refresh is refused until a source is authorized again.')}
  catch(cause){setError(cause instanceof Error?cause.message:'Authorization could not be revoked.')}
  finally{setBusy(false);void description.refetch()}
 }
 const authority=description.data?.authorization
 return <section aria-label="Server file configuration" className="space-y-3">
  {description.isError&&<p role="alert">The configured source description could not be loaded. Existing configuration and snapshots are retained.</p>}
  <p className="ui-description">This path is on the AuthLens host{description.data?.host?` (${description.data.host})`:''}, not your browser computer. The running Windows Service identity needs NTFS read access and, for UNC, SMB share access. No credentials are stored by AuthLens.</p>
  {authority&&authority!=='not_applicable'&&<p role="note" className="ui-description" data-authorization={authority}>Authorization: {AUTHORITY[authority]}</p>}
  <FormField label={kind==='unc'?'Network CSV path (UNC)':'Local server CSV path'}><Input value={path} maxLength={4096} disabled={disabled||busy} placeholder={kind==='unc'?'\\\\server\\share\\exports\\source.csv':'C:\\Data\\AuthLens\\source.csv'} onChange={event=>reset(event.target.value)}/></FormField>
  <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={approved} disabled={disabled||busy} onChange={event=>setApproved(event.target.checked)}/><span>I authorize AuthLens to read this exact CSV{kind==='unc'?' and authenticate to the named enterprise SMB server and share using its Windows Service identity':''}. I control this source location and its writers.</span></label>
  <div className="ui-toolbar"><Button variant="primary" loading={busy} disabled={disabled||!approved||!path.trim()} onClick={()=>void validate(true)}>Validate and import</Button><Button disabled={disabled||busy||!approved||!path.trim()} onClick={()=>void validate()}>Test connection and validate source</Button><Button disabled={disabled||busy||!validated||validated.revision!==revision} onClick={()=>validated&&void onActivate(validated.path,validated.hash)}>Activate validated source</Button>{authority==='exact'&&<Button disabled={disabled||busy} onClick={()=>void revoke()}>Revoke authorization</Button>}</div>
  {message&&<p role="status">{message}</p>}{error&&<p role="alert">{error} No source data was replaced.</p>}
  <p className="ui-description">Validate and import reads the complete CSV as the AuthLens service, then imports exactly the validated content. Test connection only validates and changes nothing. Existing import confirmation and SoD evidence restrictions still apply. Restored paths may need authorization on this host. Network targets must resolve to private enterprise addresses; mapped drives and an interactive sign-in are not required.</p>
 </section>
}
