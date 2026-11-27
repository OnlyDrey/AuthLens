/** One counting rule for role review progress (BUG-07), shared by the review panel ("Roles 8/16") and the user profile, so both always agree.
 * A row counts as reviewed when the server's review coverage says so (current decisions only: invalidated or outdated decisions are not
 * reviewed), or, for older responses without coverage, when its current decision is a completed outcome. "Removal required" is a completed
 * review recommending removal; it is not a confirmed removal in SAP. Investigate and Pending are not completed reviews. */
export const DECIDED = new Set(['Approved', 'Keep', 'Accepted', 'Conditional', 'Removal required', 'Rejected'])

interface Reviewable { decision?: string; acceptance?: string; review_coverage?: { reviewed?: boolean } }

export const isReviewed = (row: Reviewable) => row.review_coverage?.reviewed ?? DECIDED.has((row.decision ?? row.acceptance) as string)

export const progressOf = (rows: Reviewable[]) => rows.filter(isReviewed).length

/** Role assignment progress with the outcome breakdown the profile shows. */
export function assignmentProgress(rows: Reviewable[]) {
  const reviewed = rows.filter(isReviewed)
  const outcome = (value: string) => reviewed.filter(row => row.decision === value).length
  return { total: rows.length, reviewed: reviewed.length, kept: outcome('Keep'), removal: outcome('Removal required'),
    investigating: rows.filter(row => !isReviewed(row) && row.decision === 'Investigate').length, pending: rows.length - reviewed.length }
}
