import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'
import { copyFile, mkdir } from 'fs/promises'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    {
      name: 'copy-scichart-wasm',
      async buildStart() {
        try {
          const publicDir = path.resolve(__dirname, 'public')
          await mkdir(publicDir, { recursive: true })
          
          const source = path.resolve(__dirname, 'node_modules/scichart/_wasm/scichart2d.wasm')
          const dest = path.resolve(publicDir, 'scichart2d.wasm')
          await copyFile(source, dest)
          
          console.log('[Vite] Copied scichart2d.wasm to public/')
        } catch (err) {
          console.warn('[Vite] Failed to copy scichart2d.wasm:', err)
        }
      }
    }
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  assetsInclude: ['**/*.wasm'],
  optimizeDeps: {
    include: ['scichart']
  }
})
