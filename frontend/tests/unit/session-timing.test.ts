import test from 'node:test'
import assert from 'node:assert/strict'
import {formatRemaining,sessionCountdown,type SessionTiming} from '../../src/lib/sessionTiming.ts'
import {isUserActive,markUserActivity,resetUserActivity} from '../../src/lib/userActivity.ts'

const timing=(remaining:number,warning=120,idle=600,reason:'inactivity'|'absolute'='inactivity'):SessionTiming=>({now:1_000,idle_seconds:idle,absolute_seconds:3600,warning_seconds:warning,idle_expires_at:1_000+remaining,absolute_expires_at:1_000+3600,expires_at:1_000+remaining,reason})

test('the warning starts at the server warning interval and expiry follows the server difference, not the client clock', () => {
  const read=5_000_000
  assert.deepEqual(sessionCountdown(timing(300),read,read),{remaining:300,warning:false,expired:false})
  assert.equal(sessionCountdown(timing(300),read,read+180_000).warning,true)
  assert.equal(sessionCountdown(timing(300),read,read+181_000).remaining,119)
  assert.deepEqual(sessionCountdown(timing(300),read,read+300_000),{remaining:0,warning:true,expired:true})
  // A client clock hours off does not matter: only elapsed local time since the read counts.
  assert.equal(sessionCountdown({...timing(300),now:9_999_999,expires_at:9_999_999+300},read,read).remaining,300)
  // The warning never exceeds the idle lifetime itself.
  assert.equal(sessionCountdown(timing(90,300,90),read,read).warning,true)
  assert.equal(formatRemaining(119),'1:59');assert.equal(formatRemaining(0),'0:00')
})

test('only recent genuine input counts as activity', () => {
  resetUserActivity()
  assert.equal(isUserActive(100_000),false)
  markUserActivity(100_000)
  assert.equal(isUserActive(150_000),true)
  assert.equal(isUserActive(160_001),false)
  assert.equal(isUserActive(160_001,99_000),true)
  assert.equal(isUserActive(160_001,100_000),false)
})
