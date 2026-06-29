# Bird migration paths from eBird data

Seasonal migration maps and animated **population centroids** for three iconic
long-distance migrants — the **Arctic tern** (*Sterna paradisaea*), the
**common swift** (*Apus apus*), and the **red knot** (*Calidris canutus*) —
built from hundreds of millions of citizen-science observations.

The end product is a self-contained **Wolfram Community notebook**
(`community/bird_migration.nb`) that is detailed, scientific and educational.

## What the project does

1. **Pulls eBird observations** through **GBIF** (the eBird Observation Dataset,
   **CC BY 4.0**) using the GBIF **Download API**, which mints a citable **DOI**
   for the exact data snapshot. Pure Wolfram Language.
2. **Computes monthly population centroids** with a proper spherical (3-D
   unit-vector) mean on an equal-area grid, explicitly correcting for and
   discussing **observer-effort sampling bias**.
3. **Builds seasonal migration maps** (monthly density / abundance) for each
   species.
4. **Animates the centroid through the year** and produces a strong combined
   **hero animation** (rotating globe with comet-trail migration paths +
   synchronized monthly density map).
5. **Cross-checks against eBird Status & Trends** — Cornell's bias-corrected
   modeled weekly abundance — pulled via the R `ebirdst` package driven through
   `ExternalEvaluate["R"]` from inside the notebook, and overlays the modeled
   track on the raw-occurrence track.
6. **Adds a live "where are they right now" layer** from the eBird API 2.0
   (recent observations), for a current-data snapshot alongside the historical
   maps.

## Data & licensing

| Source | License | Citation |
| --- | --- | --- |
| GBIF — eBird Observation Dataset (EOD) | **CC BY 4.0** | GBIF download DOI (see `data/gbif_dois.json`) |
| eBird Status & Trends (Cornell Lab) | **CC BY-NC-SA** (non-commercial) | Fink et al., eBird Status & Trends |

We gratefully acknowledge the global community of **eBird** citizen scientists,
the **Cornell Lab of Ornithology**, and **GBIF** for mobilizing these data.

## Reproducing

```sh
# 1. Fetch the data (GBIF Download API -> DOI; needs config/gbif_credentials.json)
wolframscript -file wolfram/gbif_download.wls

# 2. Run the analysis + render figures (writes data/ and docs/images/)
wolframscript -file wolfram/run_all.wls

# 3. Build the community notebook
wolframscript -file community/build_notebook.wls
```

The eBird Status & Trends cross-check additionally needs **R**, the **`ebirdst`**
package, and a free Status & Trends **access key** (placed in
`config/ebirdst_key.txt`).

## Status

Active. Design spec in
`docs/superpowers/specs/2026-06-29-bird-migration-paths-design.md`.
