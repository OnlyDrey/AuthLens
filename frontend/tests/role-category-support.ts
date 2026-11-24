import {type Page} from '@playwright/test'
export async function toggleRoleCategory(page:Page,code:string){
  const control=page.getByRole('combobox',{name:'Role categories',exact:true})
  await control.click()
  await page.getByRole('listbox',{name:'Role categories',exact:true}).getByRole('option',{name:new RegExp('^'+code+' ')}).click()
  await control.press('Escape')
}
