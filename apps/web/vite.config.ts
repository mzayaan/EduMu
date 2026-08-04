import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'
import { fileURLToPath } from 'node:url'

// __dirname does not exist in ESM. fileURLToPath is also Windows-safe, whereas
// new URL(...).pathname yields "/D:/..." and breaks path resolution.
const here = (p: string) => fileURLToPath(new URL(p, import.meta.url))

declare const process: { env: Record<string, string | undefined> }

// GitHub Pages serves project repos from /<repo>/, so assets, the manifest and
// the service worker all need that prefix. Set by the deploy workflow; stays
// "/" for local dev and any root-hosted deployment.
const base = process.env.VITE_BASE || '/'

export default defineConfig({
  base,
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg'],
      // Without this the worker registers at origin root, which on
      // <user>.github.io would put it in front of every other project site.
      base,
      scope: base,
      manifest: {
        name: 'EduMU',
        short_name: 'EduMU',
        description: 'School management for Mauritian secondary schools',
        theme_color: '#0f4c5c',
        background_color: '#ffffff',
        display: 'standalone',
        start_url: base,
        scope: base,
      },
      workbox: {
        // Reference data is cached so the register opens on a dead connection.
        runtimeCaching: [
          {
            urlPattern: /\/rest\/v1\/(class_group|class_enrolment|person|student|calendar_day)/,
            handler: 'StaleWhileRevalidate',
            options: { cacheName: 'edumu-reference' },
          },
        ],
      },
    }),
  ],
  resolve: {
    alias: {
      '@': here('./src'),
      '@edumu/domain': here('../../packages/domain/src'),
    },
  },
})
