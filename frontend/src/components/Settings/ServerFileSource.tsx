import {useEffect,useState} from 'react'
import {useQuery} from '@tanstack/react-query'
import {FolderOpen,HardDrive,Network} from 'lucide-react'
import {ApiError,apiRequest} from '@/api/client'
import type {CSVSource} from '@/api/sources'
import type {ImportProfile} from '@/api/configuration'
import {isNetworkPath} from '@/api/hostFiles'
import {Button} from '@/components/Shared/Button'
import {Checkbox,FormField,Input} from '@/components/Shared/Controls'
import {StatusBadge} from '@/components/Shared/Presentation'
import {HostFilePicker} from './HostFilePicker'

type Authorization='none'|'managed'|'approved_root'|'approved_folder'|'exact'|'required'|'invalid'|'not_applicable'
const AUTHORITY:Record<Authorization,string>={none:'No host file is configured.',managed:'The configured source is a managed upload copy on this host.',approved_root:'The configured file is inside an operator-approved folder.',approved_folder:'The configured file is inside an approved folder.',exact:'The configured file is authorized for this exact source.',required:'The configured file needs administrator authorization on this host (for example after restore or revocation). Its path, mode and last valid dataset are retained.',invalid:'The configured path or the protected source authority was refused. Refresh fails closed; the last valid dataset is retained. Ask the server operator to review the authority folder.',not_applicable:''}

/**
 * WP33 (FILE-002, FILE-005): one workflow for every file on the AuthLens host, local or network: browse or enter the path (the type is detected),
 * validate the complete file as the AuthLens service, then import exactly the validated content. Files in an approved folder need no further
 * approval; any other file is authorized explicitly for this source. Typing and opening the panel never contact a share.
 */
export function ServerFileSource({source,revision,profile,disabled,onActivate}:{source:CSVSource;revision:number;profile?:ImportProfile;disabled:boolean;onActivate:(path:string,hash:string)=>Promise<void>}) {
 const description=useQuery({queryKey:['server-source-description',source,revision],queryFn:()=>apiRequest<{path:string;host:string;authorization?:Authorization}>(`/api/server/sources/${source}`)})
 const [path,setPath]=useState(''),[approved,setApproved]=useState(false),[needsApproval,setNeedsApproval]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState(''),[picking,setPicking]=useState(false)
 const [validated,setValidated]=useState<{path:string;hash:string;revision:number;records:number}|null>(null)
 useEffect(()=>{setPath(description.data?.path||'');setApproved(false);setNeedsApproval(false);setValidated(null)},[description.data?.path,source])
 const profileKey=JSON.stringify(profile)
 useEffect(()=>{setValidated(null)},[profileKey,revision])
 const reset=(value:string)=>{setPath(value);setApproved(false);setNeedsApproval(false);setValidated(null);setMessage('');setError('')}
 // importAfter: the normal flow (validate, then activate exactly the validated content); without it a check that changes nothing.
 const validate=async(importAfter=false)=>{
  setBusy(true);setError('');setMessage('');setValidated(null)
  let validatedResult:{path:string;hash:string}|null=null
  const chosen=path.trim()
  try{
   if(approved)await apiRequest(`/api/server/sources/${source}/authorize`,'POST',{path:chosen,approve_host_access:true})
   const result=await apiRequest<{records:number;sha256:string;revision:number;message:string}>(`/api/server/sources/${source}/validate`,'POST',{path:chosen,revision,profile})
   setValidated({path:chosen,hash:result.sha256,revision:result.revision,records:result.records});setNeedsApproval(false)
   setMessage(`Validated: ${result.records.toLocaleString()} records. ${importAfter?'Importing the validated content…':'Nothing was imported yet.'}`)
   validatedResult={path:chosen,hash:result.sha256}
  }catch(cause){
   // A file outside every approved folder: ask for explicit approval of this exact file instead of failing generically.
   const category=cause instanceof ApiError?(cause.body as {category?:string}|undefined)?.category:undefined
   if(category==='policy_prohibited'&&!approved){setNeedsApproval(true);setError('This file is not in an approved folder. Approve this exact file below, or choose a file in an approved folder.')}
   else setError(cause instanceof Error?cause.message:'Source validation failed. Existing data is retained.')
  }
  finally{setBusy(false);void description.refetch()}
  // Activation is hash-bound and keeps the import checks (a suspicious file is held for confirmation); its feedback is shown by the source panel.
  if(importAfter&&validatedResult)await onActivate(validatedResult.path,validatedResult.hash)
 }
 const revoke=async()=>{
  setBusy(true);setError('');setMessage('');setValidated(null)
  try{await apiRequest(`/api/server/sources/${source}/authorize`,'DELETE');setMessage('Authorization revoked. The configured path, mode and last valid dataset are retained; refresh is refused until the file is authorized again.')}
  catch(cause){setError(cause instanceof Error?cause.message:'Authorization could not be revoked.')}
  finally{setBusy(false);void description.refetch()}
 }
 const authority=description.data?.authorization,host=description.data?.host,chosen=path.trim(),network=isNetworkPath(chosen)
 const changed=!!chosen&&chosen!==(description.data?.path||'')
 return <section aria-label="Host file configuration" className="space-y-3">
  {description.isError&&<p role="alert">The configured source could not be described. Existing configuration and data are retained.</p>}
  <div className="host-source-path">
   <FormField label={`File on ${host||'the AuthLens host'}`} description="Local path (D:\Exports\users.csv) or network path (\\fileserver\share\users.csv).">
    <Input value={path} maxLength={4096} spellCheck={false} autoCapitalize="off" autoCorrect="off" disabled={disabled||busy} placeholder="D:\Exports\users.csv" onChange={event=>reset(event.target.value)}/>
   </FormField>
   <Button disabled={disabled||busy} onClick={()=>setPicking(true)}><FolderOpen size={16} aria-hidden="true"/>Browse host…</Button>
  </div>
  {chosen&&<p className="flex flex-wrap items-center gap-2 text-sm">{network?<StatusBadge tone="info"><Network size={12} aria-hidden="true"/> Network file</StatusBadge>:<StatusBadge><HardDrive size={12} aria-hidden="true"/> Local file on the host</StatusBadge>}{changed?<span className="ui-description">Not saved yet: validate to use this file.</span>:<span className="ui-description">Configured file.</span>}</p>}
  {authority&&authority!=='not_applicable'&&!changed&&<p role="note" className="ui-description" data-authorization={authority}>Authorization: {AUTHORITY[authority]}</p>}
  {needsApproval&&<Checkbox checked={approved} disabled={disabled||busy} onChange={event=>setApproved(event.target.checked)}>I authorize AuthLens to read this exact file for this source{network?' and to connect to the named share with its service identity':''}. I control this file and who can write to it.</Checkbox>}
  <div className="ui-toolbar">
   <Button variant="primary" loading={busy} disabled={disabled||!chosen||(needsApproval&&!approved)} onClick={()=>void validate(true)}>Validate and import</Button>
   <Button disabled={disabled||busy||!chosen||(needsApproval&&!approved)} onClick={()=>void validate()}>Validate only</Button>
   {validated&&validated.revision===revision&&validated.path===chosen&&<Button disabled={disabled||busy} onClick={()=>void onActivate(validated.path,validated.hash)}>Import validated file</Button>}
   {authority==='exact'&&!changed&&<Button variant="ghost" disabled={disabled||busy} onClick={()=>void revoke()}>Revoke file authorization</Button>}
  </div>
  {message&&<p role="status">{message}</p>}{error&&<p role="alert">{error} No data was replaced.</p>}
  <p className="ui-description">AuthLens reads host files as its service identity, which needs Windows read access (and share access for network files); your own sign-in is never used. Validation reads the complete file without changing data; import uses exactly the validated content, so a file changed after validation is refused.</p>
  {picking&&<HostFilePicker initialPath={chosen} onCancel={()=>setPicking(false)} onSelect={selected=>{setPicking(false);reset(selected)}}/>}
 </section>
}
