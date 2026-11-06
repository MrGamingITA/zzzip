# Zzzip website

A static site with no build step: `index.html` (inline CSS and JS), images in `assets/img/` and self-hosted fonts in `assets/fonts/` (OFL). It makes no requests to third parties.

- **Language:** English or Italian, picked from the browser language. The visitor's choice is remembered in localStorage.
- **Screenshots:** `assets/img/screenshot-en.webp` and `screenshot-it.webp` are real captures of the app in light mode, and they switch with the language.
- **Download button:** points to `https://github.com/MrGamingITA/zzzip/releases/latest/download/Zzzip.dmg`. `scripts/release.sh` uploads that stable file name with every release, and also updates the version shown on the page.
- **Publishing:** see `.github/workflows/pages.yml`.
- **Illustrations:** AI-generated, as noted in the footer.
