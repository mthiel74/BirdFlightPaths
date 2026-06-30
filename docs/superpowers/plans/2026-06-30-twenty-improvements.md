# Twenty improvements — making the post deeply scientific

> Driven by the user's request (more science: navigation, energetics, speeds,
> new testable ideas, "spice it up") + the final brutal-critic audit (68/100,
> blockers C1/C2/M1/M2). **Commit AND push after each item.**

Conventions: each item ends with a commit (`git commit`) and `git push origin
build-pipeline`. New analysis lives in `wolfram/`, figures in `docs/images/`,
notebook content in `community/build_notebook.wls`. Magnetic field via
`GeomagneticModelData` (verified working). Daylight via `Sunrise`/`Sunset`.
S&T compliance unchanged (validation only, nothing S&T-derived published).

## Group A — Correctness & compliance (brutal-critic blockers, FIRST)

1. **Fix DOI rendering.** `doiFor` returns the whole JSON sub-association → garbled
   §9/§11 + missing swift/knot DOIs (CC BY attribution failure). Patch to
   `Lookup[Lookup[$dois,ToString[key],<||>],"doi",doiPending]`; rebuild; confirm all
   three DOIs render as plain hyperlinks (87f228 / pkrrb6 / 3kmcbn).
2. **Fix PDF truncation.** §11 renders blank (export silently failed under
   `TimeConstrained`/`Quiet@Check`). Make the export robust + assert the PDF page
   count/last-cell present before committing.
3. **Correct the headline "~3,800 km/month".** Real month-matched mean knot
   global-vs-Americas separation ≈ 4,670 km. Compute it dynamically from the CSVs
   and inject everywhere (5 sites), so it can never drift again.
4. **Scientific-honesty sweep.** (a) knot residual-effort-bias caveat (centroid sits
   ~Panama, not Tierra del Fuego); (b) "decade" → "eleven years (2014–2024)";
   (c) soften swift "mates on the wing" + cite Hedenström et al. 2016 (Curr. Biol.)
   for ~10-months-aloft; (d) date the live maps "(as of late June 2026)";
   (e) harmonize swift colour (cyan everywhere).

## Group B — Navigation science

5. **Geomagnetic inclination field map** (`wolfram/geomag.wls`): global inclination
   (dip) contours + each species' centroid track overlaid; the magnetic-compass
   hypothesis. New §: "How do they find the way?"
6. **Magnetic signature along the route:** sample inclination, total intensity, and
   declination at each monthly centroid → per-species magnetic-profile plots.
7. **Navigation toolkit (high-level prose + figure):** multimodal navigation —
   magnetic compass + magnetic map, sun compass, star compass, polarized-light,
   olfaction, landmarks. Cite Mouritsen 2018 (Nature 558:50) & Wiltschko & Wiltschko.
8. **Testable idea #1 — magnetic contour-following:** does each track hold a
   *narrower* inclination range than random great-circle routes spanning the same
   latitudes? Permutation null test; report p-like fraction.
9. **Photoperiod / sun-compass:** daylight hours along each track per month
   (`Sunrise`/`Sunset`); highlight the Arctic tern experiencing more daylight than
   any animal on Earth.

## Group C — Energetics

10. **Flight-mechanics energy model** (`wolfram/energetics.wls`, Pennycuick): per-
    species mechanical power, cost of transport (J/km), from body mass + wingspan;
    total mechanical energy to complete the migration.
11. **Fuel/fat load:** flight-range equation → estimated fat fraction needed per
    long leg; compare species.
12. **Energy budget figure:** cumulative energetic cost along the year per species;
    cross-species comparison (kJ total, J/km/kg).

## Group D — Speed & movement

13. **Centroid ground speed along the trajectory:** km/day per month per species;
    speed-profile plot; note this is a population-centroid speed (lower bound on
    individual ground speed).
14. **Stopover / refuelling detection:** flag low-displacement months (knot Delaware
    Bay in the spring leg); annotate on the speed profile.
15. **Testable idea #2 — speed vs photoperiod change:** correlate monthly centroid
    speed with the rate of day-length change along the track (do birds move fastest
    when photoperiod shifts fastest?).

## Group E — Spice, figures, synthesis

16. **Multiple-birds flock animation** (`wolfram/flock.wls`): many birds streaming
    along each flyway (staggered phase + jitter, direction-oriented glyphs) instead
    of a single centroid dot — the user's request.
17. **Fill sparse stretches:** latitude-vs-month ribbon for all three species on one
    axis (the migration pulse) + a 3-species comparison dashboard
    (distance / speed / energy / latitude range).
18. **Per-species annual-profile small-multiples:** latitude, speed, daylight, and
    magnetic inclination vs month on shared axes.
19. **Hero v2:** flock + a faint magnetic-inclination field on the globe (science +
    spice combined); keep the reliable render path.
20. **Synthesis — "what's new / test it yourself":** summarize the two testable
    hypotheses + the energy estimates, state limitations honestly, and give a
    reproducible block a reader can run; future directions (tracking data, S&T).

## Push protocol
After each item: run its test/figure, `git add` the item's files (never config/ or
data/raw/ or S&T-derived), secret-scan, `git commit`, `git push origin build-pipeline`.
Rebuild the notebook when an item changes its content; otherwise commit the
script/figure/data. Final: merge build-pipeline → main and push.
