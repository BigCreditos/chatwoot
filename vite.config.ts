import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  server: {
    host: '0.0.0.0',
    port: 3036,
    strictPort: true,
    allowedHosts: true,
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
        quietDeps: true,
        silenceDeprecations: ['legacy-js-api', 'import'],
        logger: {
          warn: () => {},
          debug: () => {},
        },
      },
    },
  },
  resolve: { alias: aliases },
});
