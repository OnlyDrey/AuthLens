import {test,expect} from '@playwright/test'
import {cleanup,createPeriod,openReviews,openSod,seedGovernance,uniqueName} from './sod-fixture'
import {mainNavigation} from './support'

let directory:string
test.beforeEach(async({request})=>{directory=await seedGovernance(request)})
test.afterEach(async({request})=>{await cleanup(request,directory)})

test('Reviews is a top-level workspace whose overview leads directly to the review workflows',async({page})=>{
 await page.goto('/#session=browser-test-session')
 await expect(mainNavigation(page).getByRole('link',{name:'Reviews',exact:true})).toHaveAttribute('href','#/reviews')
 await openReviews(page)
 await expect(page).toHaveURL(/#\/reviews$/)
 const views=page.getByRole('navigation',{name:'Review views',exact:true})
 await expect(views.getByRole('link')).toHaveText(['Overview','Work Queue','Bulk Review','Remediation','Review Periods','Reports and Evidence'])
 const progress=page.getByRole('region',{name:'Review progress',exact:true})
 for(const label of ['Total users','Needs review','Complete','Removal recommended','Completion'])await expect(progress.getByText(label,{exact:true})).toBeVisible()
 // The analytical heatmap stays in SoD, so the queue entry point is not pushed below a large visualization.
 await expect(page.getByRole('region',{name:/heatmap/i})).toHaveCount(0)
 const workflows=page.getByRole('region',{name:'Review workflows',exact:true})
 await workflows.getByRole('button',{name:'Open Work Queue',exact:true}).click()
 await expect(page).toHaveURL(/#\/reviews\/queue$/)
 await expect(views.getByRole('link',{name:'Work Queue',exact:true})).toHaveAttribute('aria-current','page')
 await expect(page.getByRole('region',{name:'SoD review work queue',exact:true})).toBeVisible()
 // SoD keeps analysis pages only.
 await mainNavigation(page).getByRole('link',{name:'SoD',exact:true}).click()
 await expect(page.getByRole('navigation',{name:'SoD views',exact:true}).getByRole('link')).toHaveText(['Overview','Risk Matrix','Activity Matrix','Access Explorer'])
})

test('legacy SoD review routes redirect to the matching Reviews page',async({page})=>{
 await page.goto('/#session=browser-test-session')
 for(const [legacy,target,label] of [['#/sod/reviews','#/reviews/queue','Work Queue'],['#/sod/reviews/bulk','#/reviews/bulk','Bulk Review'],['#/sod/reviews/remediation','#/reviews/remediation','Remediation'],['#/sod/periods','#/reviews/periods','Review Periods'],['#/sod/reports','#/reviews/reports','Reports and Evidence']] as const){
  await page.goto('/'+legacy);await page.reload()
  await expect(page).toHaveURL(new RegExp(target.replace(/[/#]/g,'\\$&')+'$'))
  await expect(page.getByRole('navigation',{name:'Review views',exact:true}).getByRole('link',{name:label,exact:true})).toHaveAttribute('aria-current','page')
 }
})

test('moving between SoD and Reviews keeps the selected review context',async({page,request})=>{
 const name=uniqueName('Synthetic context period'),id=await createPeriod(request,name)
 await openSod(page,'Risk Matrix')
 const context=page.getByRole('combobox',{name:'Review context',exact:true})
 await context.selectOption(id)
 await mainNavigation(page).getByRole('link',{name:'Reviews',exact:true}).click()
 await expect(page.getByRole('combobox',{name:'Review context',exact:true})).toHaveValue(id)
 await page.getByRole('navigation',{name:'Review views',exact:true}).getByRole('link',{name:'Work Queue',exact:true}).click()
 await expect(page.getByRole('combobox',{name:'Review context',exact:true})).toHaveValue(id)
 await page.goBack();await page.goBack()
 await expect(page.getByRole('navigation',{name:'SoD views',exact:true})).toBeVisible()
 await expect(page.getByRole('combobox',{name:'Review context',exact:true})).toHaveValue(id)
})
