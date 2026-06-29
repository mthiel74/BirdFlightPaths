# Bird migration paths from eBird data — design

**Status:** approved 2026-06-29 · **Target:** Wolfram Community post
**Repo:** `BirdFlightPaths`

## 1. Goal & deliverable

A self-contained, educational Wolfram Community notebook that builds **seasonal
migration maps** for three iconic migrants and **animates each species'
population centroid through the year**:

- **Arctic tern** — *Sterna paradisaea* (GBIF usageKey `5229230`) — pole-to-pole.
- **Common swift** — *Apus apus* (GBIF usageKey `5228676`) — Europe ↔ sub-Saharan Africa.
- **Red knot** — *Calidris canutus* (GBIF usageKey `2481765`) — long-distance flyways.

The post is detailed, scientific and educational, with **blue section headers**, a
**title** (matching the style of reference notebook `125916155.nb`), and a strong
**combined hero animation** at the top. **No "How to cite" section.**

Two data paths are implemented and explicitly **compared**:
- **Path A — GBIF/eBird occurrences** in pure Wolfram Language (primary).
- **Path B — eBird Status & Trends** modeled weekly abundance via R `ebirdst`,
  driven through `ExternalEvaluate["R"]` inside the notebook.

## 2. Data sources, licensing & attribution

| Source | Product | License | How accessed | Citation |
| --- | --- | --- | --- | --- |
| GBIF — eBird Observation Dataset (EOD), datasetKey `4fa7b334-ce0d-4e88-aaae-2e0c138d049e` | Point occurrences | **CC BY 4.0** (verified live via GBIF dataset API) | GBIF **Download API** (Basic auth) → DOI snapshot | GBIF download **DOI** + EOD dataset |
| eBird Status & Trends (Cornell Lab) | Modeled weekly relative abundance rasters | **CC BY-NC-SA** / eBird S&T terms (non-commercial) | R `ebirdst` via `ExternalEvaluate["R"]`, access key required | Fink et al., eBird Status & Trends |

We are allowed to use both. EOD via GBIF is openly CC BY 4.0; S&T is free for
research/education under a non-commercial license. The notebook's
**Acknowledgements** section credits the eBird citizen-scientist community, the
Cornell Lab of Ornithology, and GBIF, and states both licenses plainly. The
exact GBIF download DOI(s) are recorded in `data/gbif_dois.json` and cited.

**HTTP etiquette:** all GBIF calls set a `User-Agent` with a contact email. Per
GBIF guidance, large pulls use the **Download API** (not paged search) for proper
attribution and to avoid rate limits.

## 3. Repository layout

```
BirdFlightPaths/
  CLAUDE.md  README.md  .gitignore
  config/          gbif_credentials.json, ebirdst_key.txt   (GIT-IGNORED)
  wolfram/
    fetcher_common.wl      HTTP/JSON helpers (URLRead + status checks)
    gbif_download.wls      Download API → DOI + zip → data/raw   (needs creds)
    gbif_search_sample.wls anonymous sampler (dev / no-creds fallback)
    load_data.wl           occurrences → per-species association
    centroids.wls          monthly spherical centroids + great-circle path length
    seasonal_maps.wls      monthly density maps (GeoHistogram/GeoSmoothHistogram)
    ebirdst_r.wls          ExternalEvaluate["R"]: ebirdst weekly abundance → centroids
    hero.wls               combined hero (globe comet-trails + synced density)
    figures.wls            all static figures for the notebook
    run_all.wls            one driver
  community/
    build_notebook.wls       assembles bird_migration.nb + .pdf
    birdflightpaths_helpers.wl   runnable helpers attached to the notebook
    bird_migration.nb / .pdf     committed OUTPUTS
  data/        tidy CSV/JSON (committed)   data/raw/ (git-ignored, regenerable)
  docs/images/  rendered figures + hero gif/mp4
  tests/       data-shape + sanity checks
```

Convention (from the ENSO repo): `.wls`/`.wl` are the source of truth; the `.nb`
and `.pdf` in `community/` are committed build outputs. Tidy small CSV/JSON live
in `data/` and are committed for offline reproducibility; bulk downloads live in
git-ignored `data/raw/`.

## 4. Data path A — GBIF occurrences (pure WL)

GBIF **Download API** predicate per species (or one combined download):
`taxonKey ∈ {5229230, 5228676, 2481765}`, `hasCoordinate = true`,
`basisOfRecord = HUMAN_OBSERVATION`, `datasetKey = <EOD>` (clean CC BY 4.0
provenance), `year = 2014,2024`. Poll status; fetch **SIMPLE_CSV**; record DOI.
Parse fields: `decimalLatitude`, `decimalLongitude`, `month`, `year`,
`individualCount`, `eventDate`, `species`. Tidy CSV per species + `gbif_dois.json`
committed.

A no-credentials `gbif_search_sample.wls` fallback uses the anonymous
`occurrence/search` API (paged, capped) for development before the DOI download
completes.

## 5. Scientific method — centroids & bias (the honest core)

Raw eBird occurrence centroids are **biased by observer effort** (vastly more
observers in North America/Europe). Mitigations, presented explicitly:

1. **Equal-area gridding:** aggregate monthly occurrences onto ~2° cells; compute
   the centroid from *cells* (presence, optionally `individualCount`-weighted),
   not raw points — damps hotspot oversampling.
2. **Proper spherical centroid:** convert (lat, lon) → 3-D unit vectors, average,
   renormalize, convert back. Required for the circumpolar / dateline-crossing
   Arctic tern, where a naïve longitude mean is meaningless. Units carried.
3. **Honest caveat:** centroid displacement *understates* true individual journey
   length; effort bias remains even after gridding. This motivates Path B.

Headline per species: great-circle distance the monthly centroid travels over a
year (`GeoDistance`).

## 6. Data path B — eBird Status & Trends via R

In-notebook `ExternalEvaluate["R"]` session: load `ebirdst` (installed in setup;
needs the user's access key), download low-resolution **weekly relative-abundance**
rasters, compute abundance-weighted weekly centroids in R (`terra`), return the
weekly lat/lon table to WL. A figure overlays the **bias-corrected S&T track vs the
raw GBIF occurrence track** — the educational payoff showing why modeled products
exist. License difference (non-commercial S&T vs CC BY GBIF) flagged in-text.

## 7. Hero animation (combined)

- **Top:** rotating orthographic **globe** (dark ocean basemap) with all three
  species' monthly centroids as glowing markers trailing **fading comet-trails /
  great-circle arcs**, color-coded per species, month label.
- **Bottom:** synchronized monthly **density map**.
- 12-month loop, eased; exported as quantized **GIF + MP4**; embedded with
  `AnimatedImage` (renders inline on the Community web page; `Video` does not).
  Per-frame `ColorQuantize` keeps the `.nb` small.

Prototype both a GeoGraphics orthographic globe and a textured `Graphics3D` sphere;
keep whichever is more striking.

## 8. Notebook structure

Title + subtitle + **hero** → Abstract → 1. The three migrants & why migration
matters · 2. The data: eBird, GBIF, CC BY 4.0, the DOI, and the effort-bias
problem · 3. From checklists to centroids (runnable method) · 4. Seasonal
migration maps · 5. Animating the population centroid · 6. The bias-corrected
view: Status & Trends via R · 7. What each journey reveals · 8. Conclusions ·
9. References · 10. Acknowledgements + data licenses · 11. Reproducibility.

Blue `Section`/`Subsection` headers matched to `125916155.nb`. Each computed
figure preceded by a runnable `Input` cell and followed by a pre-rendered static
image, so the prose reads without evaluating anything. Any externally-generated
illustration carries an `aiNote` disclosure cell (ENSO convention).

## 9. Credentials & environment

- **GBIF account** (`config/gbif_credentials.json`, git-ignored): supplied &
  validated (HTTP 200 against the Download API user endpoint) on 2026-06-29.
- **eBird Status & Trends access key** (`config/ebirdst_key.txt`, git-ignored):
  free research/education key from science.ebird.org — **still to be supplied**.
- **R 4.4.1** present; `ExternalEvaluate["R"]` works. **`ebirdst` not yet
  installed** — installed during Path-B setup.

Until the S&T key arrives, Path A is built/validated end-to-end and Path B is
scaffolded to run the moment the key is in place.

## 10. Defaults

Year window **2014–2024** · ~**2°** grid · globe = GeoGraphics orthographic
(with a textured `Graphics3D` alternative prototyped) · exactly the three
specified species · all-maps aesthetic by default (AI species illustrations only
if requested, with disclosure cells).

## 11. Out of scope

- No "How to cite" section in the notebook.
- No individual-level tracking data (Movebank etc.) — occurrence/abundance only.
- No commercial use of S&T data.
```
