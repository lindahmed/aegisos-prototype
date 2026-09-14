interface TabsProps {
  tabs: string[]
  active: string
  onChange: (tab: string) => void
}

export default function Tabs({ tabs, active, onChange }: TabsProps) {
  return (
    <div role="tablist" className="flex gap-1 border-b border-border overflow-x-auto scrollbar-thin">
      {tabs.map((tab) => (
        <button
          key={tab}
          role="tab"
          aria-selected={active === tab}
          onClick={() => onChange(tab)}
          className={`relative whitespace-nowrap px-4 py-2.5 text-sm font-semibold transition-colors ${
            active === tab ? 'text-teal-700' : 'text-text-secondary hover:text-text-primary'
          }`}
        >
          {tab}
          {active === tab && <span className="absolute inset-x-0 -bottom-px h-0.5 rounded-full bg-teal-600" />}
        </button>
      ))}
    </div>
  )
}
