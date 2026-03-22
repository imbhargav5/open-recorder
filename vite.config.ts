import { defineConfig } from 'vite'
import path from 'node:path'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
  envPrefix: ['VITE_', 'TAURI_ENV_'],
  optimizeDeps: {
    entries: ['index.html'],
    exclude: [
      'lucide-react',
      'react-icons/bs',
      'react-icons/fa',
      'react-icons/fa6',
      'react-icons/fi',
      'react-icons/md',
      'react-icons/rx',
    ],
  },
  build: {
    target: ['es2021', 'chrome100', 'safari14'],
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
        pure_funcs: ['console.log', 'console.debug'],
      },
    },
    rollupOptions: {
      output: {
        manualChunks: {
          pixi: ['pixi.js', 'pixi.js/unsafe-eval'],
          'react-vendor': ['react', 'react-dom'],
          'video-processing': [
            'mediabunny',
            'mp4box',
            '@fix-webm-duration/fix',
          ],
        },
      },
    },
    chunkSizeWarningLimit: 1000,
  },
})
