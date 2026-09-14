/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: {
          900: '#0B2442',
          800: '#12375E',
          700: '#1B4B78',
          600: '#2A6193',
        },
        teal: {
          700: '#1C568D',
          600: '#2C6DA7',
          500: '#4386BE',
          100: '#DCEBFA',
          50: '#F0F6FC',
        },
        coral: {
          600: '#345F9B',
          500: '#4C78B5',
          400: '#6D96C9',
          100: '#E1EBF8',
          50: '#F2F6FC',
        },
        surface: {
          DEFAULT: '#FFFFFF',
          sunk: '#F1F5F9',
          raised: '#F8FAFD',
        },
        border: {
          DEFAULT: '#D8E2EC',
          strong: '#B9CBDD',
        },
        text: {
          primary: '#12273E',
          secondary: '#526B83',
          muted: '#7890A7',
          onDark: '#F2F7FC',
        },
        success: { DEFAULT: '#1E8E5A', 100: '#E1F5EA' },
        warning: { DEFAULT: '#C98A1F', 100: '#FBF0DC' },
        error: { DEFAULT: '#D64545', 100: '#FAE2E2' },
      },
      fontFamily: {
        display: ['"Sora"', 'sans-serif'],
        body: ['"Inter"', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'monospace'],
      },
      fontSize: {
        xs: ['0.75rem', { lineHeight: '1.1rem' }],
        sm: ['0.8125rem', { lineHeight: '1.25rem' }],
        base: ['0.9375rem', { lineHeight: '1.5rem' }],
        lg: ['1.0625rem', { lineHeight: '1.6rem' }],
        xl: ['1.25rem', { lineHeight: '1.75rem' }],
        '2xl': ['1.5rem', { lineHeight: '2rem' }],
        '3xl': ['1.875rem', { lineHeight: '2.25rem' }],
      },
      borderRadius: {
        sm: '6px',
        DEFAULT: '8px',
        md: '10px',
        lg: '14px',
        xl: '20px',
      },
      boxShadow: {
        card: '0 2px 4px rgba(11,36,66,0.05), 0 10px 28px rgba(11,36,66,0.05)',
        raised: '0 12px 32px rgba(11,36,66,0.12), 0 3px 8px rgba(11,36,66,0.06)',
        pop: '0 18px 44px rgba(11,36,66,0.16)',
      },
      spacing: {
        18: '4.5rem',
        22: '5.5rem',
      },
    },
  },
  plugins: [],
}
