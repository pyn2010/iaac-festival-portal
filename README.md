# IAAC Festival Portal

Production-ready static JavaScript + Supabase portal for the 4th Parul University International Folklore Festival (`festival.iaac.in`).

## Features

- Role based sign-up and navigation for `admin` and `participant` users.
- Admin assignment for `info@iaac.in` or access code `PU-FOLKLORE-2026`.
- Supabase persistence with RLS policies for profiles, participant applications, official documents, and storage objects.
- Participant dashboard, private application summary download, and step-by-step submission form.
- Admin dashboard with participant search/filter, approval controls, CSV export, and organizer document upload/delete workflow.
- Responsive dark festival UI with profile dropdown, settings, sign out, and visible fetch error handling.

## Setup

1. Apply `supabase/migrations/202608080001_portal_schema.sql` to your Supabase project.
2. Provide credentials at runtime with `window.SUPABASE_URL` and `window.SUPABASE_ANON_KEY`, or save them in browser `localStorage` for local testing.
3. Run `npm run dev` to serve locally, or deploy the static files to `festival.iaac.in`.

## Security Notes

Client route guards are backed by database RLS. Participants can only select and upsert their own `applications` row, while admins can review all applications and manage event documents.
