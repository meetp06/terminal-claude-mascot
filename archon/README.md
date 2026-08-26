# Archon — waitlist site

Pre-launch, build-in-public waitlist page for Archon, an AI gesture-control
smart ring. Warm editorial design: scroll-driven exploded view of the ring's
concept layers, optional generative ambient sound, and a working signup form.

## Contents

- `index.html` — the complete site, self-contained (fonts come from Google
  Fonts at load time; everything else is inline). Open it in a browser or
  deploy it as-is.
- `design/` — the design source (artboard + canvas layout) the page was
  built from.

## Deploying free

1. **GitHub Pages**: Settings → Pages → deploy from branch, folder `/archon`
   (or copy `index.html` to a `gh-pages` branch root). Netlify/Vercel drag
   and drop also works.
2. **Form backend**: create a free form endpoint (e.g. Formspree), then set
   `FORM_ENDPOINT` at the top of the `<script>` block in `index.html` to its
   URL. Until that is set, visitor submissions on a static host are stored
   only in each visitor's own browser.

## Reading submissions

Open the page with `#admin` appended to the URL to see collected entries and
export CSV. On the hosted version with `FORM_ENDPOINT` configured, entries
arrive in your form backend's dashboard instead.

## Placeholders to fill

Search `index.html` for `[YOUR` — social handles and contact email in the
footer — and replace the demo-film placeholder with the real clip when it
exists.
