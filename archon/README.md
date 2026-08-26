# Archon — waitlist site

Pre-launch, build-in-public waitlist page for Archon, an AI gesture-control
smart ring. Apple-style design system: alternating light/dark tiles, a
scroll-driven exploded view of the ring's concept layers, optional generative
ambient sound, and a working signup form (email + interests + per-category
functions + free-text).

## Contents

- `index.html` — the complete site, self-contained. Open in a browser or
  deploy as-is.
- `design/` — earlier design source (artboard + canvas layout).

## Publish free with Netlify (recommended — hosting + submissions in one)

The form is already wired for Netlify Forms. Steps:

1. Create a free account at netlify.com (sign in with GitHub).
2. Either **drag and drop** a folder containing this `index.html` onto
   app.netlify.com/drop, or click "Add new site → Import an existing
   project", pick this repo, and set the publish directory to `archon`.
3. Done. Your site is live at `<yourname>.netlify.app` (add a custom
   domain later under Domain settings, also free).
4. **Seeing your users:** Netlify dashboard → your site → **Forms →
   waitlist**. Every signup shows email, interests (`uses`), chosen
   functions, free-text, and tester answer. Export CSV from the same page.
   Free tier: 100 submissions/month. Enable email notifications under
   Forms → Notifications to get each signup in your inbox.

## Alternatives

- **GitHub Pages** (this repo → Settings → Pages) hosts free but stores
  nothing; pair it with a form service by setting `FORM_ENDPOINT` at the
  top of the `<script>` in `index.html` (e.g. Formspree, free 50/month).
- **Supabase** (free Postgres database) when you outgrow 100/month —
  ask Claude to wire the insert.

## Fallback behavior

If no backend is reachable, submissions are stored in the visitor's own
browser only, and the thank-you note says so. Open the page with `#admin`
appended to the URL to inspect/export locally stored entries.

## Placeholders to fill

Search `index.html` for `[YOUR` — founder name, social handles, contact
email — and replace the demo-film placeholder with the real clip.
