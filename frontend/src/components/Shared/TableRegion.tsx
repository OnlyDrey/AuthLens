import { createContext, useCallback, useContext, useLayoutEffect, useRef, useState, type HTMLAttributes, type ReactNode, type Ref } from 'react'

/** The table toolbar slot and scroll region of the enclosing TableRegion; ConfigurableTable places its Columns control in the toolbar. */
type Frame = { toolbar: HTMLElement | null }
const TableFrameContext = createContext<Frame | null>(null)
export const useTableFrame = () => useContext(TableFrameContext)

function assign<T>(target: Ref<T> | undefined, value: T) {
  if (typeof target === 'function') target(value)
  else if (target) (target as { current: T }).current = value
}

/**
 * TBL-02 shared table frame. The head (table toolbar, then a horizontal scrollbar) sits above the scroll region and stays sticky below the
 * application header while the page scrolls, so a wide table can be scrolled sideways without first scrolling to its end. The top scrollbar
 * mirrors the region's own horizontal scroll in both directions and is shown only while the region overflows; the region's own horizontal
 * scrollbar is then hidden (keyboard, wheel, trackpad and touch scrolling of the region are unchanged). `className` is the region's class
 * (`access-table` for ordinary tables, `matrix-scroll` for matrices).
 */
export function TableRegion({ children, className, toolbar, scrollRef, ...props }: HTMLAttributes<HTMLDivElement> & { className: string; toolbar?: ReactNode; scrollRef?: Ref<HTMLDivElement> }) {
  const [tools, setTools] = useState<HTMLElement | null>(null), [scroller, setScroller] = useState<HTMLDivElement | null>(null)
  const region = useCallback((node: HTMLDivElement | null) => { setScroller(node); assign(scrollRef, node) }, [scrollRef])
  return (
    <div className="table-frame">
      <div className="table-frame-head">
        <div className="table-frame-toolbar" ref={setTools}>{toolbar}</div>
        {scroller && <TopScrollbar region={scroller} />}
      </div>
      <TableFrameContext.Provider value={{ toolbar: tools }}>
        <div {...props} ref={region} className={className}>{children}</div>
      </TableFrameContext.Provider>
    </div>
  )
}

/** A pointer scrollbar mirroring `region`'s horizontal scroll. It is not a separate keyboard stop: the region itself stays focusable. */
function TopScrollbar({ region }: { region: HTMLElement }) {
  const bar = useRef<HTMLDivElement>(null), [range, setRange] = useState<number | null>(null)
  useLayoutEffect(() => {
    const measure = () => {
      const overflow = region.scrollWidth - region.clientWidth
      region.toggleAttribute('data-top-scroll', overflow > 1)
      region.toggleAttribute('data-vertical-scroll', region.scrollHeight > region.clientHeight + 1)
      // The bar's scroll range equals the region's: its content is the region's overflow plus the bar's own visible width
      setRange(overflow > 1 ? overflow : null)
      if (bar.current) bar.current.scrollLeft = region.scrollLeft
    }
    const fromRegion = () => { if (bar.current && bar.current.scrollLeft !== region.scrollLeft) bar.current.scrollLeft = region.scrollLeft }
    measure()
    const resize = new ResizeObserver(measure)
    resize.observe(region)
    for (const child of region.children) resize.observe(child)
    const added = new MutationObserver(() => { for (const child of region.children) resize.observe(child); measure() })
    added.observe(region, { childList: true })
    region.addEventListener('scroll', fromRegion, { passive: true })
    return () => { resize.disconnect(); added.disconnect(); region.removeEventListener('scroll', fromRegion); region.removeAttribute('data-top-scroll'); region.removeAttribute('data-vertical-scroll') }
  }, [region])
  useLayoutEffect(() => { if (bar.current) bar.current.scrollLeft = region.scrollLeft }, [range, region])
  return (
    <div ref={bar} className="table-top-scroll" hidden={range === null} aria-hidden="true" tabIndex={-1} data-testid="table-top-scroll"
      onScroll={() => { if (bar.current && region.scrollLeft !== bar.current.scrollLeft) region.scrollLeft = bar.current.scrollLeft }}>
      <div className="table-top-scroll-content" style={{ width: `calc(100% + ${range ?? 0}px)` }} />
    </div>
  )
}

/** Keeps `--app-header-height` equal to the sticky application header, so sticky table heads sit directly beneath it. */
export function useHeaderHeight(header: HTMLElement | null) {
  useLayoutEffect(() => {
    if (!header) return
    const set = () => document.documentElement.style.setProperty('--app-header-height', `${Math.round(header.getBoundingClientRect().height)}px`)
    set()
    const observer = new ResizeObserver(set); observer.observe(header)
    return () => observer.disconnect()
  }, [header])
}
