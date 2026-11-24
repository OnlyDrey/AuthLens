import {useEffect,useState} from 'react'
import {parseUsernameList} from '@/lib/usernameList'
import {Button} from './Button'
import {FormField} from './Controls'

export function ExactUsernameFilter({values,onChange,max=100}:{values:string[];onChange:(values:string[])=>void;max?:number}){
 const [draft,setDraft]=useState(values.join('\n')),[error,setError]=useState('')
 const selected=values.join('\n')
 useEffect(()=>{setDraft(selected);setError('')},[selected])
 return <FormField label="Exact usernames" description={`Exact SAP account names; one per line or separated by commas, semicolons or whitespace. At most ${max}. General search remains separate.`}>
  <textarea className="ui-control min-h-20" aria-label="Exact usernames" value={draft} maxLength={50000} onChange={event=>{setDraft(event.target.value);setError('')}}/>
  <div className="flex flex-wrap gap-2"><Button size="compact" onClick={()=>{const next=parseUsernameList(draft);if(next.length>max){setError(`Select at most ${max} exact usernames.`);return}onChange(next)}}>Apply exact usernames</Button><Button size="compact" variant="ghost" disabled={!draft&&!values.length} onClick={()=>{setDraft('');setError('');onChange([])}}>Clear exact usernames</Button></div>
  {!!values.length&&<p role="status" className="ui-description">{values.length} exact usernames selected</p>}{error&&<p role="alert">{error}</p>}
 </FormField>
}
