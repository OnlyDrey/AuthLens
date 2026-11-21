import test from 'node:test'
import assert from 'node:assert/strict'
import {buildTableCSV,csvField} from '../../src/lib/csv.ts'

test('displayed CSV preserves explicit column/row order, Unicode, quotes, commas and line breaks',()=>{
  assert.equal(buildTableCSV(['Department','Username'],[['Finance, A','USER_2'],['Å "B"\nC','USER_1']]),'\uFEFF"Department","Username"\r\n"Finance, A","USER_2"\r\n"Å ""B""\nC","USER_1"')
})
test('every table field retains spreadsheet-formula neutralisation',()=>{
  for(const value of ['=1+1','+SUM(A1)','@command','-1',' \t=cmd','\rcommand'])assert.equal(csvField(value),'"\''+value+'"')
  assert.equal(csvField('ROLE_A'),'"ROLE_A"');assert.equal(csvField(null),'""')
})
test('CSV bounds count UTF-8 and the BOM and fail before returning a partial export',()=>{
  const value=buildTableCSV(['A'],[['Å']]);const size=new TextEncoder().encode(value).byteLength
  assert.equal(buildTableCSV(['A'],[['Å']],size),value)
  assert.throws(()=>buildTableCSV(['A'],[['Å']],size-1),/exceeds/)
  assert.throws(()=>buildTableCSV(['A'],[],1),/exceeds/)
  assert.throws(()=>buildTableCSV(['A'],[['one','extra']]),/columns changed/)
})
