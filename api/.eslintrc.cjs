module.exports = {
  parser: '@typescript-eslint/parser',
  parserOptions: { project: 'tsconfig.json', sourceType: 'module' },
  plugins: ['@typescript-eslint', 'security'],
  extends: [
    'plugin:@typescript-eslint/recommended',
    'plugin:security/recommended-legacy',
    'prettier',
  ],
  root: true,
  env: { node: true, jest: true },
  ignorePatterns: ['.eslintrc.cjs', 'dist', 'node_modules'],
  rules: {
    // Garde-fou: pas de log brut (risque PII). Utiliser le logger avec scrubbing.
    'no-console': 'error',
    '@typescript-eslint/no-explicit-any': 'error',
    // Désactivées : trop bruyantes pour un scaffold (réactivables plus tard).
    '@typescript-eslint/explicit-function-return-type': 'off',
    'security/detect-object-injection': 'off',
  },
};
