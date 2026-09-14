import { Outlet } from 'react-router-dom'
import Header from './Header'

export default function AppShell() {
  return (
    <div className="flex h-screen flex-col overflow-hidden bg-surface-sunk">
      <Header />
      <main className="flex-1 overflow-y-auto px-4 py-6 sm:px-6 lg:px-8">
        <div className="mx-auto w-full max-w-screen-2xl">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
