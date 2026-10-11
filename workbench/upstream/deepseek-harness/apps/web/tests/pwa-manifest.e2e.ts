import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { createHash } from 'node:crypto'
import { expect, it } from 'vitest'

const DIST_ROOT = fileURLToPath(new URL('../dist', import.meta.url))

it('ships install metadata with the built web application', async () => {
  const index = await readFile(join(DIST_ROOT, 'index.html'), 'utf8')
  expect(index).toContain('<link rel="manifest" href="/manifest.webmanifest" />')

  const manifest: unknown = JSON.parse(await readFile(join(DIST_ROOT, 'manifest.webmanifest'), 'utf8'))
  expect(manifest).toEqual({
    id: '/',
    name: 'FDE-X 交付工作台',
    short_name: 'FDE-X',
    start_url: '/',
    scope: '/',
    display: 'fullscreen',
    icons: [
      {
        src: '/ff-brand/ff-logo.png',
        sizes: '300x300',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/ff-brand/favicon.svg',
        sizes: 'any',
        type: 'image/svg+xml',
        purpose: 'any',
      },
    ],
  })
})

it('ships the FDE-X brand icon for browser tabs', async () => {
  const index = await readFile(join(DIST_ROOT, 'index.html'), 'utf8')
  expect(index).toContain('href="/ff-brand/favicon.svg"')
  const favicon = await readFile(join(DIST_ROOT, 'ff-brand/ff-logo.png'))
  expect(createHash('sha256').update(favicon).digest('hex')).toBe('7f60a0150309d2847113bc2c866aa43bb1a544f19063ce9b817aeacfbe626b11')
})
