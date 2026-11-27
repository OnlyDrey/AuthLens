import { SecondaryNavigation } from '@/components/Shared/Navigation'
import { usersHref, useViewHistory } from '@/hooks/useViewHistory'
import { USERS_VIEWS, type UsersNavigation as UsersPage } from '@/lib/navigationItems'

/** Module tabs of Users (NAV-2): User Directory, Compare Users and Release Access, the same items, labels and order as the main-navigation submenu.
 *  Each tab opens its page directly; Release Access opens its list (an open release role is closed). */
export function UsersNavigation({ current, onSelect }: { current: UsersPage; onSelect?: (value: UsersPage) => void }) {
  const { change } = useViewHistory()
  return <SecondaryNavigation label="Users view" items={USERS_VIEWS.map(({ value, label, icon }) => ({
    value, label, icon, href: usersHref(value), active: current === value,
    onSelect: () => {
      onSelect?.(value)
      if (value === 'release-access') change({ page: 'releases', release: null, releaseContext: '', user: '', detailRole: null })
      else change({ page: 'users', accessMode: value, user: '', userContext: {} })
    },
  }))} />
}
