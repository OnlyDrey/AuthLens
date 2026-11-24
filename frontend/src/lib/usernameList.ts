/** Existing User Access exact-list semantics, shared by user-level filters. */
export const parseUsernameList = (text: string) => [...new Set(text.split(/[\s,;]+/).map(item => item.trim()).filter(Boolean).map(item => item.toLocaleUpperCase()))]
const USERNAME_TOKEN = /^[^\s@,;<>"]{1,40}$/
export function looksLikeUsernameList(text: string): boolean {
 const entries=text.split(/[\n\r\t,;]+/).map(item=>item.trim()).filter(Boolean)
 return entries.length>=2&&entries.every(entry=>USERNAME_TOKEN.test(entry))
}
