import { readFileSync, existsSync } from 'node:fs';
const required = ['index.html', 'admin/index.html', 'group/index.html', 'src/app.js', 'src/config.js', 'src/styles.css', 'supabase/migrations/202608080001_portal_schema.sql', 'supabase/migrations/202608120001_group_account_model.sql', 'supabase/migrations/202608120002_portal_entrypoints_test_group.sql'];
for (const file of required) {
  if (!existsSync(file)) throw new Error(`Missing ${file}`);
}
const html = readFileSync('index.html', 'utf8');
if (!html.includes('src/config.js') || !html.includes('src/app.js')) throw new Error('index.html must load config before app');
const config = readFileSync('src/config.js', 'utf8');
for (const token of ['window.SUPABASE_URL', 'window.SUPABASE_ANON_KEY']) {
  if (!config.includes(token)) throw new Error(`Missing expected config token ${token}`);
}
const app = readFileSync('src/app.js', 'utf8');
for (const token of ['Forgot password?', 'claim_group_id', 'PUIFF26-TEST01', 'Admin Portal', 'Group Portal', 'group_ids', 'group_id_events', 'profiles', 'applications', 'event_documents']) {
  if (!app.includes(token)) throw new Error(`Missing expected token ${token}`);
}
console.log('Static portal validation passed.');
