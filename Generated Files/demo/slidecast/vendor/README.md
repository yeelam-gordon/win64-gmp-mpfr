# Vendored third-party assets

These files are bundled so the deck and the video-render pipeline work **offline / reproducibly**
without depending on a CDN. Live browser playback can use the fallback URLs in `deck.html`, but
deterministic capture blocks HTTP(S) and therefore requires the local files.

- `gsap.min.js`, `MotionPathPlugin.min.js`, `SplitText.min.js` — **GSAP 3.15.0** by
  GreenSock/Webflow. Free for all uses
  (including these plugins) under the GreenSock "No Charge" Standard License — https://gsap.com/standard-license/.
  Source: https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/. Used as-is, unmodified.
- `fonts.css` + `fonts/*.woff2` — only present after running
  `python scripts/vendor.py --fonts --dir path\to\copied-package\vendor` from the Slidecast skill,
  which downloads the Google Fonts (Inter, Playfair Display, Poppins, Nunito, Fraunces, JetBrains
  Mono — all SIL Open Font License). Re-fetch or update with `vendor.py`.

To refresh a copied package, run
`python scripts/vendor.py --gsap --dir path\to\copied-package\vendor` from the Slidecast skill
(add `--fonts` when local fonts are also required).
