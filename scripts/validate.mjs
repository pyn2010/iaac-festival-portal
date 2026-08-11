import { readFileSync, existsSync } from 'node:fs';
const required = ['index.html', 'src/app.js', 'src/styles.css', 'supabase/migrations/202608080001_portal_schema.sql'];
for (const file of required) {
  if (!existsSync(file)) throw new Error(`Missing ${file}`);
}
const app = readFileSync('src/app.js', 'utf8');
for (const token of ['PU-FOLKLORE-2026', 'info@iaac.in', 'try{return', 'profiles', 'applications', 'event_documents']) {
  if (!app.includes(token)) throw new Error(`Missing expected token ${token}`);
}
console.log('Static portal validation passed.');
