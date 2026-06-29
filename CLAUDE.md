# Repo notes for Claude

## Purpose

Produce a Wolfram Community post — `community/bird_migration.nb` — on **bird
migration paths from eBird data**. Seasonal migration maps and animated
population centroids for the Arctic tern (*Sterna paradisaea*), common swift
(*Apus apus*), and red knot (*Calidris canutus*). Two compared data paths:
GBIF/eBird occurrences in pure Wolfram Language, and eBird Status & Trends
modeled abundance via R `ebirdst` through `ExternalEvaluate["R"]`.

Design spec: `docs/superpowers/specs/2026-06-29-bird-migration-paths-design.md`.

## Pipeline

```
wolfram/fetcher_common.wl       shared HTTP/JSON helpers
wolfram/gbif_download.wls       GBIF Download API -> DOI + zip -> data/raw   (needs creds)
wolfram/gbif_search_sample.wls  anonymous occurrence/search sampler (dev fallback)
wolfram/load_data.wl            occurrences -> per-species association
        |
wolfram/centroids.wls           monthly spherical centroids + great-circle path length
wolfram/seasonal_maps.wls       monthly density maps
wolfram/ebirdst_r.wls           ExternalEvaluate["R"]: ebirdst weekly abundance -> centroids
wolfram/ebird_live.wls          eBird API 2.0 recent sightings (live "right now" layer)
wolfram/hero.wls                combined hero animation (globe + density) -> docs/images/*.gif/.mp4
wolfram/figures.wls             all static figures
wolfram/run_all.wls             one entry point

community/build_notebook.wls    assembles bird_migration.nb + .pdf
```

## Conventions (same as ENSO-emergence)

* Plain-text `.wls`/`.wl` is the source of truth; `.nb` and `.pdf` in
  `community/` are committed *outputs*.
* All HTTP fetches use `URLRead[HTTPRequest[...]]` and check the status code —
  `URLDownload` silently writes server error pages on 4xx/5xx.
* Set a `User-Agent` (with contact email) on every GBIF request. Large pulls use
  the **Download API**, not paged search (proper attribution; avoids HTTP 429).
* Figures live in `docs/images/`, referenced from both README and notebook.
* Tidy small CSV/JSON used by the pipeline live in `data/` and are committed;
  bulk raw downloads stay in git-ignored `data/raw/`.
* Hero/looping animations are embedded as `AnimatedImage` (Community's web
  renderer drops `Video[]` but keeps `AnimatedImage`). `ColorQuantize` each
  frame to keep the `.nb` small.

## SECURITY — credentials

* GBIF credentials, the eBird API 2.0 token, and the eBird S&T access key live
  ONLY in `config/`
  (git-ignored). **Never** commit them; never echo the password. Before any
  commit, grep the staged diff for the password string, `password`, and precise
  coordinates.

## Data & licensing

* GBIF eBird Observation Dataset (EOD) = **CC BY 4.0**. Cite the download DOI
  (recorded in `data/gbif_dois.json`) + the EOD dataset.
* eBird Status & Trends = **Cornell custom terms, non-commercial**. Derived/
  modified S&T figures may NOT be published online or redistributed (incl. in
  this repo) — used for **private validation only**; all S&T-derived outputs are
  git-ignored. Cite Fink et al. + DOI + Cornell's verbatim acknowledgement; link
  to Cornell's official visualizations in the post.
* Acknowledge eBird citizen scientists, Cornell Lab of Ornithology, and GBIF.

## Commit cadence

Commit + push after each meaningful step (skeleton, fetchers, centroids,
seasonal maps, hero, R path, notebook). Short factual messages. Co-author line
per global instructions. Only commit/push when asked.
