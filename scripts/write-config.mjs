import { writeFileSync } from 'node:fs';

const config = {
  SUPABASE_URL: process.env.SUPABASE_URL || '',
  SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY || '',
};

writeFileSync(
  'src/config.js',
  `// Generated at build time from Vercel environment variables.\n// SUPABASE_ANON_KEY is the browser-safe Supabase publishable key; never put a service-role key here.\nwindow.SUPABASE_URL = ${JSON.stringify(config.SUPABASE_URL)};\nwindow.SUPABASE_ANON_KEY = ${JSON.stringify(config.SUPABASE_ANON_KEY)};\n`,
);

if (config.SUPABASE_URL && config.SUPABASE_ANON_KEY) {
  console.log('Supabase browser config generated from environment variables.');
} else {
  console.log('Supabase browser config generated with empty values; localStorage fallback remains available.');
}
