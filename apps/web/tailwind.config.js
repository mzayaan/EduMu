/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#0f172a',
        brand: { DEFAULT: '#0f4c5c', dark: '#0a3945', light: '#e6f1f3' },
        present: '#15803d',
        absent: '#b91c1c',
        late: '#b45309',
        authorised: '#1d4ed8',
      },
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
    },
  },
  plugins: [],
}
