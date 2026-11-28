/**
 * TBL-04 canonical display labels for fields that mean the same thing across AuthLens. Table headers, column selectors, filters, detail views
 * and report configuration use these words. They are display text only: API properties, database fields, stable column keys, saved-filter
 * fields and persisted preference keys keep their names, and CSV headers keep their export contracts (see docs/architecture/TERMINOLOGY.md).
 */
export const FIELD = {
  sapUsername: 'SAP username',
  employee: 'Employee',
  roleName: 'Role name',
  roleDescription: 'Role description',
  sapUserGroup: 'SAP user group',
  department: 'Department',
  jobTitle: 'Job title',
  reviewStatus: 'Review status',
  functionalGroup: 'Functional Group',
  manager: 'Manager',
  releaseArea: 'Release area',
  releaseGroup: 'Release group',
  releaseStrategy: 'Release strategy',
} as const

/** Report column keys (stable backend identifiers) shown with the canonical label; the CSV header stays the backend's own label. */
const REPORT_COLUMN_LABELS: Record<string, string> = {
  username: FIELD.sapUsername,
  full_name: FIELD.employee,
  first_name: 'First name',
  last_name: 'Last name',
  user_group: FIELD.sapUserGroup,
  role_name: FIELD.roleName,
  assigned_role: FIELD.roleName,
  document_type: 'PR/PO',
  role_description: FIELD.roleDescription,
  department: FIELD.department,
  title: FIELD.jobTitle,
  previous_department: `Previous ${FIELD.department.toLowerCase()}`,
  current_department: `Current ${FIELD.department.toLowerCase()}`,
  previous_title: `Previous ${FIELD.jobTitle.toLowerCase()}`,
  current_title: `Current ${FIELD.jobTitle.toLowerCase()}`,
  review_state: FIELD.reviewStatus,
  release_area: FIELD.releaseArea,
  release_group: FIELD.releaseGroup,
  release_strategy: FIELD.releaseStrategy,
}

/** The canonical label of a report column, or the backend label when the column has no canonical field. */
export const reportColumnLabel = (key: string, label: string) => REPORT_COLUMN_LABELS[key] ?? label

/** Search terms that name the same field, for filter discovery (FLT-03): a user typing an older or informal word finds the field. */
export const FIELD_ALIASES: Record<string, string[]> = {
  [FIELD.sapUsername]: ['sap user', 'username', 'user name', 'user id', 'account'],
  [FIELD.employee]: ['name', 'full name', 'person'],
  [FIELD.sapUserGroup]: ['user group', 'group', 'usergroup'],
  [FIELD.roleName]: ['role', 'assigned role'],
  [FIELD.jobTitle]: ['title', 'position'],
  [FIELD.department]: ['dept', 'organization unit'],
  [FIELD.reviewStatus]: ['review', 'decision', 'state'],
  [FIELD.functionalGroup]: ['fg', 'business group'],
  [FIELD.manager]: ['supervisor', 'line manager', 'reporting manager'],
  [FIELD.releaseArea]: ['area', 'release code area'],
  [FIELD.releaseGroup]: ['rel group', 'release grp'],
  [FIELD.releaseStrategy]: ['strategy', 'release code', 'rel strategy'],
  'PR/PO': ['purchase requisition', 'purchase order', 'document type', 'release type'],
  'Transaction code': ['tcode', 't-code', 'transaction'],
  'Exact usernames': ['username list', 'user list', 'paste usernames', 'bulk users'],
}
