import {test} from 'node:test'
import assert from 'node:assert/strict'
import {parseUsernameList,looksLikeUsernameList} from '../../src/lib/usernameList.ts'

test('exact username lists normalize existing delimiters and remove duplicates without fuzzy expansion',()=>{
 assert.deepEqual(parseUsernameList(' ada,BOB;ada\r\n cy\tBOB '),['ADA','BOB','CY'])
 assert.deepEqual(parseUsernameList(''),[])
 assert.deepEqual(parseUsernameList('USER1,USER10'),['USER1','USER10'])
 assert.equal(looksLikeUsernameList('ADA\nBOB'),true)
 assert.equal(looksLikeUsernameList('Jane Doe, John Smith'),false)
 assert.equal(looksLikeUsernameList('ada@example.invalid,bob@example.invalid'),false)
})
