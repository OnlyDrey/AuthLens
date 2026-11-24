import { useQuery } from '@tanstack/react-query'
import { fetchOrganizationOptions, organizationKey } from '@/api/functionalGroups'
import { MultiSelectFilter } from './MultiSelectFilter'
import {ExactUsernameFilter} from './ExactUsernameFilter'
import {FormField} from './Controls'
import {Button} from './Button'

export interface SubjectFiltersValue {functional_groups:string[];managers:string[];usernames:string[]}
export function SubjectFilters({value,onChange,maxUsernames=500,compact=false}:{value:SubjectFiltersValue;onChange:(value:SubjectFiltersValue)=>void;maxUsernames?:number;compact?:boolean}){
 return <div className={compact?'grid min-w-0 gap-3':'grid min-w-0 gap-3 md:grid-cols-3'}>
  <FormField label="Functional Group"><OrganizationFilter kind="functional_group" values={value.functional_groups} onChange={values=>onChange({...value,functional_groups:values})}/></FormField>
  <FormField label="Manager"><OrganizationFilter kind="manager" values={value.managers} onChange={values=>onChange({...value,managers:values})}/></FormField>
  <ExactUsernameFilter values={value.usernames} onChange={values=>onChange({...value,usernames:values})} max={maxUsernames}/>
  <Button size="compact" variant="ghost" disabled={!Object.values(value).some(values=>values.length)} onClick={()=>onChange({functional_groups:[],managers:[],usernames:[]})}>Clear population filters</Button>
 </div>
}
export function subjectFilterParams(value:SubjectFiltersValue){
 const parameters=new URLSearchParams()
 for(const key of ['functional_groups','managers','usernames'] as const)for(const item of value[key])parameters.append(key,item)
 return parameters
}

/** Functional Group and Manager filters for user-level views. Selection is sent to the server (OR within a filter, AND with every other filter)
 *  so paginated results and totals stay correct. Options show the number of SAP users. */
export function OrganizationFilter({ kind, values, onChange }: { kind: 'functional_group' | 'manager'; values: string[]; onChange: (values: string[]) => void }) {
  const options = useQuery({ queryKey: organizationKey, queryFn: fetchOrganizationOptions, staleTime: 15_000 })
  const items = (kind === 'manager' ? options.data?.managers : options.data?.functional_groups) ?? []
  const label = kind === 'manager' ? 'Manager' : 'Functional Group'
  return (<>
    <MultiSelectFilter label={label} values={values} options={items.map(item => item.value)} onChange={onChange} maxSelected={50} loading={options.isFetching&&!options.data}
      optionLabel={value => { const item = items.find(entry => entry.value === value); return item ? `${item.label} (${item.count})` : value }}
      placeholder={kind === 'manager' ? items.length?'All managers':'No manager mappings available' : 'All Functional Groups'} />
      {kind==='manager'&&options.isSuccess&&!items.length&&<p className="ui-description" role="status">Manager choices require enabled Employee Directory and loaded SAP user data. Direct relationships are used; no hierarchy expansion is applied.</p>}
  </>)
}

/** Display label for a stored filter value (for removable chips). Falls back to the raw value while options load. */
export function useOrganizationLabel() {
  const options = useQuery({ queryKey: organizationKey, queryFn: fetchOrganizationOptions, staleTime: 15_000 })
  return (kind: 'functional_group' | 'manager', value: string) => {
    const items = (kind === 'manager' ? options.data?.managers : options.data?.functional_groups) ?? []
    return items.find(item => item.value === value)?.label ?? value
  }
}
