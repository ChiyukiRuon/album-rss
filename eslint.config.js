import js from '@eslint/js'
import { defineConfig, globalIgnores } from 'eslint/config'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default defineConfig([
  // .local-check/ 是验证脚本生成的浏览器 profile，含大量第三方 JS。
  // .build/ 与 DerivedData/ 是 Swift Package Manager / Xcode 的构建目录，含依赖源码。
  globalIgnores(['**/dist/', '**/coverage/', '.local-check/', '**/.build/', '**/DerivedData/']),
  {
    files: ['**/*.{js,ts,tsx}'],
    extends: [js.configs.recommended, tseslint.configs.recommended],
  },
  {
    files: ['apps/web/src/**/*.{ts,tsx}'],
    extends: [reactHooks.configs.flat.recommended, reactRefresh.configs.vite],
    languageOptions: { globals: globals.browser },
  },
  {
    files: ['*.js', 'apps/*/*.ts', 'packages/*/*.ts'],
    languageOptions: { globals: globals.node },
  },
])
