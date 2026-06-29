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

Three data touchpoints are implemented and explicitly **compared**:
- **Path A — GBIF/eBird occurrences** in pure Wolfram Language (primary, historical).
- **Path B — eBird Status & Trends** modeled weekly abundance via R `ebirdst`,
  driven through `ExternalEvaluate["R"]` inside the notebook (bias-corrected
  cross-check).
- **Path C — live eBird API 2.0** recent sightings: a "where are they right now"
  current-data layer (late-June 2026) via the eBird REST API.

## 2. Data sources, licensing & attribution

| Source | Product | License | How accessed | Citation |
| --- | --- | --- | --- | --- |
| GBIF — eBird Observation Dataset (EOD), datasetKey `4fa7b334-ce0d-4e88-aaae-2e0c138d049e` | Point occurrences | **CC BY 4.0** (verified live via GBIF dataset API) | GBIF **Download API** (Basic auth) → DOI snapshot | GBIF download **DOI** + EOD dataset |
| eBird Status & Trends (Cornell Lab) | Modeled weekly relative abundance rasters | **Custom Cornell Lab Terms of Use** — NOT Creative Commons; non-commercial; **modified/derived products may NOT be published online** except when excerpted from a peer-reviewed publication | R `ebirdst` via `ExternalEvaluate["R"]`, access key required | Fink et al., eBird Status & Trends + DOI + required acknowledgement |
| eBird (Cornell Lab) | Live recent observations (API 2.0) | eBird Terms of Use; cite eBird | eBird REST API 2.0, `X-eBirdApiToken` header | eBird, Cornell Lab of Ornithology |

**Use rights (verified against the published terms 2026-06-29):**
- **GBIF/EOD = CC BY 4.0** — freely usable and publishable with attribution; all
  Path A figures derive from this and go in the post. DOI(s) recorded in
  `data/gbif_dois.json` and cited.
- **eBird Status & Trends = Cornell custom terms (non-commercial).** Computing
  with `ebirdst` for research/education is permitted, but **publishing our own
  derived/modified S&T figures on a website is NOT** (only Cornell's *unmodified*
  visualizations, or peer-reviewed-excerpted figures, may appear online).
  **Decision:** S&T is used as **private method validation only** — the derived
  centroid track is computed locally, never published and never committed (the
  outputs are git-ignored). The notebook describes the comparison in prose, cites
  S&T (Fink et al. + DOI), includes Cornell's required acknowledgement verbatim,
  and **links** readers to Cornell's official S&T visualizations.
- **eBird API 2.0 (live layer)** is governed by the eBird Terms of Use; verify the
  redistribution clause before publishing the live-sightings map, and attribute
  eBird/Cornell Lab.

The **Acknowledgements** section credits the eBird citizen-scientist community,
the Cornell Lab of Ornithology, and GBIF, and states each source's terms plainly.

**Cornell-required S&T acknowledgement (verbatim, to appear in the notebook):**
> "This material uses data from the eBird Status and Trends Project at the Cornell
> Lab of Ornithology, eBird.org. Any opinions, findings, and conclusions or
> recommendations expressed in this material are those of the author(s) and do not
> necessarily reflect the views of the Cornell Lab of Ornithology."

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
    ebird_live.wls         eBird API 2.0 recent sightings (live "right now" layer)
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

1. **Coarse 2° gridding with presence weighting:** aggregate monthly occurrences
   onto ~2° lat/lon cells and weight each occupied cell **equally (=1)**, not by
   summed `individualCount` — otherwise well-birded hotspots still dominate and the
   gridding is cosmetic (a brutal-critic finding, verified). Note: 2° lat/lon cells
   are **not equal-area** (they shrink ∝ cos lat); this is coarse effort mitigation,
   not correction.
2. **Proper spherical centroid:** convert (lat, lon) → 3-D unit vectors, average,
   renormalize, convert back. Required for the circumpolar / dateline-crossing
   Arctic tern, where a naïve longitude mean is meaningless. Units carried. When the
   resultant vector ≈ 0 (an antipodally-smeared cloud) the centroid is genuinely
   undefined → return `Missing`, never a fabricated coordinate. Empty months stay
   `Missing` (no imputation from the annual mean).
3. **Per-flyway treatment (the central scientific narrative).** A *single global*
   centroid is invalid for species spread over disjoint flyways: pooling them makes
   the monthly centroid teleport between hemispheres (the red knot's naïve global
   path was 66,315 km, exceeding the Arctic tern — a pooling artifact). The honest,
   pedagogically strong fix, per species:
   - **Common swift** — global centroid over its Afro-Palearctic range (lon −30…145):
     one coherent flyway, the "it works" case.
   - **Red knot** — primary centroid subset to the **Americas flyway** (lon −110…−30);
     the broken global version is kept and shown as the teaching contrast.
   - **Arctic tern** — **Atlantic-basin** centroid track (lon −80…20) plus a global
     **latitude-vs-month** curve (the real pole-to-pole pulse; longitude meaningless).
4. **Honest caveat:** centroid displacement measures the population *center of mass*,
   NOT how far any bird flies — it *understates* for circumpolar species (east-west
   cancels) and is not a journey at all for pooled disjoint populations. Captions say
   so explicitly, and cite tracked figures (Egevang et al. 2010, PNAS, for the tern
   ~70,900 km). This honest treatment is also what motivates Path B.

Headline per species: great-circle distance the monthly centroid travels over the
year, summed over **observed** edges only (`GeoDistance`), captioned as centroid
displacement.

## 6. Data path B — eBird Status & Trends via R (PRIVATE VALIDATION ONLY)

An `ExternalEvaluate["R"]` session loads `ebirdst` (installed in setup; needs the
user's access key), downloads low-resolution **weekly relative-abundance** rasters,
and computes abundance-weighted weekly centroids in R (`terra`). This is used as a
**local method-validation cross-check** — does our effort-bias-corrected GBIF
centroid track agree with Cornell's professionally modeled track? The agreement is
quantified locally (e.g., mean great-circle separation between the two tracks).

**Compliance:** per the S&T terms, derived/modified S&T figures may **not** be
published online and the derived products may **not** be redistributed. Therefore:
- The S&T-derived outputs (`data/centroids_st_*.csv`, any S&T overlay PNG, the
  `ebirdst` raster cache) are **git-ignored** and never committed.
- The notebook's §6 contains **no S&T-derived figure**. It explains the validation
  in prose (with the quantified agreement number), cites S&T (Fink et al. + DOI),
  prints Cornell's **required acknowledgement verbatim**, and **links** readers to
  Cornell's official S&T visualization pages for the three species.
- `ebirdst_r.wls` is committed (it is our code, not their data); it regenerates the
  local validation for anyone with their own S&T key.

## 6b. Data path C — live eBird API 2.0 sightings

A current-data flourish (ENSO-style "live" ethos). Using the confirmed eBird API
2.0 token (`config/ebird_api_key.txt`, git-ignored), pull each species' most
recent observations via the REST API (`/v2/data/obs/...recent` / species-scoped
endpoints, `X-eBirdApiToken` header), and plot a "where are they right now"
(late-June 2026) map alongside the historical maps. Region-scoped and
recency-limited by design, so this complements — does not replace — the GBIF
historical analysis. eBird Terms of Use; cite eBird / Cornell Lab.

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
migration maps · 5. Animating the population centroid · 6. Cross-checking against the
professionals: eBird Status & Trends (prose validation + cite/link, no derived
figure) · 6b. Live now: recent sightings via the eBird API · 7. What each journey
reveals · 8. Conclusions · 9. References · 10. Acknowledgements + data licenses
(incl. Cornell's required S&T acknowledgement verbatim) · 11. Reproducibility.

Blue `Section`/`Subsection` headers matched to `125916155.nb`. Each computed
figure preceded by a runnable `Input` cell and followed by a pre-rendered static
image, so the prose reads without evaluating anything. Any externally-generated
illustration carries an `aiNote` disclosure cell (ENSO convention).

## 9. Credentials & environment

- **GBIF account** (`config/gbif_credentials.json`, git-ignored): supplied &
  validated (HTTP 200 against the Download API user endpoint) on 2026-06-29.
- **eBird Status & Trends access key** (`config/ebirdst_key.txt`, git-ignored):
  free research/education key from science.ebird.org — **being requested by the
  user now**; supplied shortly.
- **eBird API 2.0 token** (`config/ebird_api_key.txt`, git-ignored): supplied &
  validated (HTTP 200 against the API with `X-eBirdApiToken`, 403 without) on
  2026-06-29. Powers Path C.
- **R 4.4.1** present; `ExternalEvaluate["R"]` works. **`ebirdst` not yet
  installed** — installed during Path-B setup.

Build order: Path A end-to-end first; Path C (live layer) next (token in hand);
Path B scaffolded and run once the S&T key lands.

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
