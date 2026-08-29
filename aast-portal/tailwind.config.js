/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: {
          900: '#10233B',
          800: '#16324F',
          700: '#1E4265',
          600: '#2C567F',
        },
        teal: {
          700: '#095F6B',
          600: '#0C7C8C',
          500: '#12939F',
          100: '#DFF1F2',
          50: '#EFF8F8',
        },
        coral: {
          600: '#D3492F',
          500: '#E8593F',
          400: '#EF7B64',
          100: '#FBE4DE',
          50: '#FDF1EE',
        },
        surface: {
          DEFAULT: '#FFFFFF',
          sunk: '#F3F5F8',
          raised: '#FAFBFC',
        },
        border: {
          DEFAULT: '#E2E6EC',
          strong: '#CBD3DC',
        },
        text: {
          primary: '#16212E',
          secondary: '#5B6B7C',
          muted: '#8A97A6',
          onDark: '#F3F5F8',
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
        card: '0 1px 2px rgba(16,35,59,0.06), 0 1px 1px rgba(16,35,59,0.04)',
        raised: '0 8px 24px rgba(16,35,59,0.10), 0 2px 6px rgba(16,35,59,0.06)',
        pop: '0 12px 32px rgba(16,35,59,0.16)',
      },
      spacing: {
        18: '4.5rem',
        22: '5.5rem',
      },
    },
  },
  plugins: [],
}
