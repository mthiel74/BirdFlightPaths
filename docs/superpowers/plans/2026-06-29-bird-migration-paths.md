# Bird Migration Paths Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained, educational Wolfram Community notebook
(`community/bird_migration.nb`) mapping seasonal bird migration and animating
yearly population centroids for the Arctic tern, common swift, and red knot, from
eBird data via GBIF — cross-checked against eBird Status & Trends (R `ebirdst`)
and a live eBird API 2.0 layer.

**Architecture:** A pure-Wolfram-Language pipeline (HTTP fetch → tidy CSV →
spherical-centroid + gridded-density analysis → figures → notebook), mirroring the
ENSO-emergence repo conventions. Two auxiliary data paths: eBird Status & Trends
modeled abundance pulled through `ExternalEvaluate["R"]` + `ebirdst`, and live
recent sightings via the eBird REST API 2.0. `.wls`/`.wl` are source of truth;
`.nb`/`.pdf` are committed build outputs.

**Tech Stack:** Wolfram Language (`wolframscript`, v1.13.0); GBIF REST + Download
API; eBird REST API 2.0; R 4.4.1 + `ebirdst` + `terra` via `ExternalEvaluate`.

## Global Constraints

- **Species (GBIF usageKeys):** Arctic tern *Sterna paradisaea* `5229230`;
  common swift *Apus apus* `5228676`; red knot *Calidris canutus* `2481765`.
- **eBird EOD datasetKey:** `4fa7b334-ce0d-4e88-aaae-2e0c138d049e` (license CC BY 4.0).
- **GBIF download predicate:** `hasCoordinate=true`, `basisOfRecord=HUMAN_OBSERVATION`,
  `datasetKey=<EOD>`, `year=2014,2024`, format `SIMPLE_CSV`.
- **Credentials live ONLY in git-ignored `config/`:** `gbif_credentials.json`
  (`username`,`email`,`password`), `ebird_api_key.txt` (API 2.0 token),
  `ebirdst_key.txt` (Status & Trends key — pending). Never commit; never echo.
- **HTTP:** always `URLRead[HTTPRequest[...]]`, check `"StatusCode"`; set
  `User-Agent: BirdFlightPaths/0.1 (marco_thiel@yahoo.com)`. Large pulls use the
  Download API, not paged search.
- **Notebook:** blue `Section`/`Subsection` headers matched to `125916155.nb`;
  has a Title; **no "How to cite" section**; hero via `AnimatedImage` (not
  `Video`); per-frame `ColorQuantize`; each computed figure = runnable `Input`
  cell + pre-rendered static image; `aiNote` disclosure before any AI asset.
- **Licensing in-notebook:** GBIF/EOD = CC BY 4.0 (cite download DOI in
  `data/gbif_dois.json`); S&T = non-commercial CC BY-NC-SA (cite Fink et al.);
  acknowledge eBird citizen scientists, Cornell Lab, GBIF.
- **Commit cadence:** commit after each task; co-author line
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
  Run the secret-scan guard (below) before every commit.

**Secret-scan guard (run before EVERY commit).** Derives the secret values from
the git-ignored `config/` at runtime — never hardcode credentials in tracked
files (including this plan):
```bash
cd /Users/thiel/GitHub/BirdFlightPaths
git add -A
git diff --cached --name-only | grep -qE 'config/|credentials|ebird.*key|\.nc$|data/raw/' \
  && { echo "ABORT: protected file staged"; git reset; } || echo "OK files"
SECRETS=$(python3 - <<'PY'
import json, os
v=[]
try: v.append(json.load(open('config/gbif_credentials.json'))['password'])
except Exception: pass
for f in ('config/ebird_api_key.txt','config/ebirdst_key.txt'):
    if os.path.exists(f):
        s=open(f).read().strip()
        if s: v.append(s)
import re
print('|'.join(re.escape(x) for x in v))
PY
)
[ -n "$SECRETS" ] && git diff --cached | grep -qE "$SECRETS" \
  && { echo "ABORT: secret in diff"; git reset; } || echo "OK secrets"
```

---

## File Structure

| File | Responsibility |
| --- | --- |
| `wolfram/fetcher_common.wl` | HTTP GET/POST helpers with status checks + User-Agent; JSON/CSV helpers; `$repoRoot`, `$speciesList`. |
| `wolfram/gbif_search_sample.wls` | Anonymous occurrence/search sampler → `data/raw/sample/*.csv` (dev, no creds). |
| `wolfram/gbif_download.wls` | Submit Download API predicate, poll, fetch SIMPLE_CSV → `data/raw/`, record DOI → `data/gbif_dois.json`. |
| `wolfram/load_data.wl` | Read occurrences (sample or full) → per-species `Association` of records. |
| `wolfram/centroids.wls` | Equal-area gridding, spherical (3-D) monthly centroid, great-circle path length → `data/centroids_*.csv`. |
| `wolfram/seasonal_maps.wls` | Monthly gridded-density maps per species → `docs/images/seasonal_*.png`. |
| `wolfram/ebird_live.wls` | eBird API 2.0 recent sightings per species → `data/live_*.csv` + `docs/images/live_*.png`. |
| `wolfram/ebirdst_r.wls` | `ExternalEvaluate["R"]` + `ebirdst` weekly abundance centroids → `data/centroids_st_*.csv`. |
| `wolfram/hero.wls` | Combined hero animation (orthographic globe comet-trails + synced density) → `docs/images/hero.gif`/`.mp4`. |
| `wolfram/figures.wls` | All remaining static figures (centroid tracks, path-length bars, S&T-vs-GBIF overlay). |
| `wolfram/run_all.wls` | One driver: load → centroids → maps → figures → hero. |
| `community/birdflightpaths_helpers.wl` | Runnable helper symbols attached to the notebook (loaders, centroid fn, color maps, month names). |
| `community/build_notebook.wls` | Assemble `bird_migration.nb` + `.pdf` from cells + committed images. |
| `tests/*.wls` | Sanity-assertion scripts (per task). |

---

### Task 1: Shared fetch/util package (`fetcher_common.wl`)

**Files:**
- Create: `wolfram/fetcher_common.wl`
- Test: `tests/test_fetcher_common.wls`

**Interfaces:**
- Produces:
  - `$repoRoot` (String, absolute path to repo root)
  - `$userAgent = "BirdFlightPaths/0.1 (marco_thiel@yahoo.com)"`
  - `$speciesList` = `{<|"common"->"Arctic tern","sci"->"Sterna paradisaea","key"->5229230,"code"->"arctir1"|>, ...}` (code = eBird species code; fill swift=`comswi`, knot=`redkno`)
  - `httpGetJSON[url_String, headers_:{}]` → parsed JSON assoc/list, or `$Failed` (prints status on non-200)
  - `httpGetString[url_String, headers_:{}]` → body String or `$Failed`
  - `loadConfig[name_String]` → contents of `config/<name>` (JSON parsed if `.json`, else raw String); aborts with clear message if missing

- [ ] **Step 1: Write the failing test** — `tests/test_fetcher_common.wls`
```wolfram
Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
asserts = {
  StringQ[$repoRoot] && DirectoryQ[$repoRoot],
  Length[$speciesList] === 3,
  AssociationQ[First@$speciesList] && First[$speciesList]["key"] === 5229230,
  (* live GBIF species lookup proves httpGetJSON works *)
  httpGetJSON["https://api.gbif.org/v1/species/5229230"]["scientificName"] =!= Missing
};
Print["PASS count: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print["FAILS: ", Position[asserts, False]]; Exit[1]];
```

- [ ] **Step 2: Run test to verify it fails**
Run: `wolframscript -file tests/test_fetcher_common.wls`
Expected: FAIL (`fetcher_common.wl` not found / symbols undefined).

- [ ] **Step 3: Write `wolfram/fetcher_common.wl`**
```wolfram
(* ::Package:: *)
$repoRoot = DirectoryName[$InputFileName];  (* wolfram/ -> repo via ParentDirectory below *)
$repoRoot = ParentDirectory[$repoRoot];
$userAgent = "BirdFlightPaths/0.1 (marco_thiel@yahoo.com)";

$speciesList = {
  <|"common"->"Arctic tern", "sci"->"Sterna paradisaea", "key"->5229230, "code"->"arctir1"|>,
  <|"common"->"Common swift","sci"->"Apus apus",          "key"->5228676, "code"->"comswi"|>,
  <|"common"->"Red knot",     "sci"->"Calidris canutus",   "key"->2481765, "code"->"redkno"|>
};

reqHeaders[extra_List] := Join[{"User-Agent" -> $userAgent}, extra];

httpGetString[url_String, headers_:{}] := Module[{r},
  r = URLRead[HTTPRequest[url, <|"Headers" -> reqHeaders[headers]|>]];
  If[r["StatusCode"] =!= 200,
    Print["HTTP ", r["StatusCode"], " for ", url]; Return[$Failed]];
  r["Body"]];

httpGetJSON[url_String, headers_:{}] := Module[{b = httpGetString[url, headers]},
  If[b === $Failed, $Failed, ImportString[b, "RawJSON"]]];

loadConfig[name_String] := Module[{p = FileNameJoin[{$repoRoot, "config", name}]},
  If[! FileExistsQ[p], Print["MISSING config/", name]; Abort[]];
  If[StringEndsQ[name, ".json"], Import[p, "RawJSON"], StringTrim@Import[p, "Text"]]];
```

- [ ] **Step 4: Run test to verify it passes**
Run: `wolframscript -file tests/test_fetcher_common.wls`
Expected: `PASS count: 4/4`.

- [ ] **Step 5: Commit** (run secret-scan guard first)
```bash
git add wolfram/fetcher_common.wl tests/test_fetcher_common.wls
git commit -m "feat: shared GBIF/eBird fetch + util package"
```

---

### Task 2: Anonymous GBIF sampler (`gbif_search_sample.wls`)

Dev data fast, before the slow DOI download. Spatially/temporally spreads the
occurrence/search API across months so downstream analysis has all 12 months.

**Files:**
- Create: `wolfram/gbif_search_sample.wls`
- Test: `tests/test_sample_shape.wls`

**Interfaces:**
- Produces: `data/raw/sample/occ_<key>.csv` per species with header
  `lat,lon,month,year,count` (numeric; `count` defaults 1 when `individualCount` absent).

- [ ] **Step 1: Write the failing test** — `tests/test_sample_shape.wls`
```wolfram
dir = FileNameJoin[{DirectoryName[$InputFileName, 2], "data", "raw", "sample"}];
files = FileNames["occ_*.csv", dir];
If[Length[files] < 3, Print["FAIL: expected 3 sample files, got ", Length[files]]; Exit[1]];
Do[ With[{d = Import[f, "CSV"]},
   If[First[d] =!= {"lat","lon","month","year","count"}, Print["FAIL header ", f]; Exit[1]];
   If[Length[d] < 200, Print["FAIL too few rows ", f]; Exit[1]];
   If[! (Min[#] >= 1 && Max[#] <= 12 &@ (Rest[d][[All,3]])), Print["FAIL month range ", f]; Exit[1]];
 ], {f, files}];
Print["PASS sample shape: ", Length[files], " files"];
```

- [ ] **Step 2: Run to verify it fails**
Run: `wolframscript -file tests/test_sample_shape.wls`
Expected: FAIL (no sample dir/files yet).

- [ ] **Step 3: Write `wolfram/gbif_search_sample.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
EOD = "4fa7b334-ce0d-4e88-aaae-2e0c138d049e";
outDir = FileNameJoin[{$repoRoot, "data", "raw", "sample"}];
If[! DirectoryQ[outDir], CreateDirectory[outDir, CreateIntermediateDirectories->True]];

(* Pull up to `perMonth` records for each (species, month) so all 12 months
   are represented despite the 100k offset cap. *)
perMonth = 300;
fetchMonth[key_, m_] := Module[{url, j},
  url = "https://api.gbif.org/v1/occurrence/search?taxonKey=" <> ToString[key] <>
        "&datasetKey=" <> EOD <> "&hasCoordinate=true&month=" <> ToString[m] <>
        "&year=2014,2024&limit=" <> ToString[perMonth];
  j = httpGetJSON[url];
  If[j === $Failed, {},
    Select[#, NumberQ[#[[1]]] && NumberQ[#[[2]]] &] & @
     ({#["decimalLatitude"], #["decimalLongitude"], m,
       Lookup[#, "year", 2020], Lookup[#, "individualCount", 1] /. Except[_?NumberQ] -> 1} & /@ j["results"])]];

Do[ Module[{rows},
   rows = Join @@ Table[fetchMonth[sp["key"], m], {m, 12}];
   Export[FileNameJoin[{outDir, "occ_" <> ToString[sp["key"]] <> ".csv"}],
     Prepend[rows, {"lat","lon","month","year","count"}], "CSV"];
   Print[sp["common"], ": ", Length[rows], " rows"];
 ], {sp, $speciesList}];
```

- [ ] **Step 4: Run the script, then the test**
Run: `wolframscript -file wolfram/gbif_search_sample.wls` then
`wolframscript -file tests/test_sample_shape.wls`
Expected: per-species row counts printed; test `PASS sample shape: 3 files`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/gbif_search_sample.wls tests/test_sample_shape.wls
git commit -m "feat: anonymous GBIF occurrence sampler (dev data)"
```

---

### Task 3: Occurrence loader (`load_data.wl`)

**Files:**
- Create: `wolfram/load_data.wl`
- Test: `tests/test_load_data.wls`

**Interfaces:**
- Consumes: `data/raw/sample/occ_<key>.csv` (or full `data/raw/occ_<key>.csv`).
- Produces: `loadOccurrences[key_Integer, source_:"sample"]` →
  `<|"lat"->{..},"lon"->{..},"month"->{..},"year"->{..},"count"->{..}|>` (all
  equal-length numeric lists). `source` ∈ {"sample","full"} selects the dir.

- [ ] **Step 1: Write the failing test** — `tests/test_load_data.wls`
```wolfram
Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
o = loadOccurrences[5229230, "sample"];
asserts = {
  AssociationQ[o], Sort@Keys[o] === Sort@{"lat","lon","month","year","count"},
  Equal @@ (Length /@ Values[o]), Length[o["lat"]] > 100,
  Min[o["month"]] >= 1 && Max[o["month"]] <= 12,
  Min[o["lat"]] >= -90 && Max[o["lat"]] <= 90};
Print["PASS: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print[Position[asserts, False]]; Exit[1]];
```

- [ ] **Step 2: Run to verify it fails**
Run: `wolframscript -file tests/test_load_data.wls` → FAIL (no `load_data.wl`).

- [ ] **Step 3: Write `wolfram/load_data.wl`**
```wolfram
(* ::Package:: *)
loadOccurrences[key_Integer, source_:"sample"] := Module[{dir, f, d, cols},
  dir = If[source === "full",
    FileNameJoin[{$repoRoot, "data", "raw"}],
    FileNameJoin[{$repoRoot, "data", "raw", "sample"}]];
  f = FileNameJoin[{dir, "occ_" <> ToString[key] <> ".csv"}];
  If[! FileExistsQ[f], Print["MISSING ", f]; Abort[]];
  d = Rest@Import[f, "CSV"];                 (* drop header *)
  d = Select[d, Length[#] >= 5 && NumberQ[#[[1]]] && NumberQ[#[[2]]] &];
  cols = Transpose[d];
  <|"lat"->cols[[1]], "lon"->cols[[2]], "month"->Round@cols[[3]],
    "year"->Round@cols[[4]], "count"->(cols[[5]] /. Except[_?NumberQ] -> 1)|>];
```

- [ ] **Step 4: Run test to verify it passes** → `PASS: 6/6`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/load_data.wl tests/test_load_data.wls
git commit -m "feat: occurrence loader"
```

---

### Task 4: Centroids — gridding + spherical mean + path length (`centroids.wls`)

The scientific core. Grid to ~2° equal-area cells per month (damp effort bias),
then take the **spherical** centroid of occupied cells.

**Files:**
- Create: `wolfram/centroids.wls`
- Modify: `wolfram/load_data.wl` (add `monthlyCentroids` + `pathLength` so the
  notebook helper can reuse them)
- Test: `tests/test_centroids.wls`

**Interfaces:**
- Consumes: `loadOccurrences`.
- Produces:
  - `sphericalCentroid[lats_List, lons_List, weights_List]` → `{lat,lon}` via mean of 3-D unit vectors.
  - `monthlyCentroids[key_, source_]` → 12×3 list `{month, lat, lon}` (gridded, weighted).
  - `centroidPathLengthKm[centroids_]` → total great-circle km around the 12-month loop.
  - Side effect: writes `data/centroids_<key>.csv` (`month,lat,lon`) and appends
    a row to `data/path_lengths.csv` (`key,common,km`).

- [ ] **Step 1: Write the failing test** — `tests/test_centroids.wls`
```wolfram
Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
(* spherical centroid of two points either side of the antimeridian must land
   near +/-180, NOT near 0 (the naive-mean failure). *)
c = sphericalCentroid[{0., 0.}, {170., -170.}, {1., 1.}];
near180 = Abs[Abs[c[[2]]] - 180.] < 1.0;
cs = monthlyCentroids[5229230, "sample"];
asserts = {near180, Dimensions[cs] === {12, 3},
  AllTrue[cs[[All,2]], -90 <= # <= 90 &],
  centroidPathLengthKm[cs] > 1000,                 (* tern roams widely *)
  FileExistsQ[FileNameJoin[{$repoRoot,"data","centroids_5229230.csv"}]]};
Print["PASS: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print[Position[asserts, False]]; Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL (functions undefined).

- [ ] **Step 3: Add functions to `wolfram/load_data.wl`**
```wolfram
sphericalCentroid[lats_List, lons_List, w_List] := Module[{v, m},
  v = MapThread[Function[{la, lo, wt},
        wt * {Cos[la Degree] Cos[lo Degree], Cos[la Degree] Sin[lo Degree], Sin[la Degree]}],
        {lats, lons, w}];
  m = Total[v];
  If[Norm[m] < 10^-9, Return[{Mean[lats], Mean[lons]}]];
  m = m / Norm[m];
  {ArcSin[m[[3]]]/Degree, ArcTan[m[[1]], m[[2]]]/Degree}];

(* ~2 deg cells: key by {Round[lat/2], Round[lon/2]}; cell weight = total count *)
gridCells[lat_, lon_, cnt_] := Module[{g},
  g = GroupBy[Transpose[{lat, lon, cnt}], {Round[#[[1]]/2], Round[#[[2]]/2]} &];
  KeyValueMap[Function[{k, rows},
     {Mean[rows[[All,1]]], Mean[rows[[All,2]]], Total[rows[[All,3]]]}], g]];

monthlyCentroids[key_Integer, source_:"sample"] := Module[{o, res},
  o = loadOccurrences[key, source];
  res = Table[
    Module[{idx = Flatten@Position[o["month"], m], cells},
      If[idx === {}, {m, Missing[], Missing[]},
        cells = gridCells[o["lat"][[idx]], o["lon"][[idx]], o["count"][[idx]]];
        With[{c = sphericalCentroid[cells[[All,1]], cells[[All,2]], cells[[All,3]]]},
          {m, c[[1]], c[[2]]}]]],
    {m, 12}];
  (* fill any empty month by interpolating neighbours on the sphere *)
  res = res /. {mm_, _Missing, _} :> {mm,
        Sequence @@ sphericalCentroid[
          DeleteMissing[res[[All,2]]], DeleteMissing[res[[All,3]]],
          ConstantArray[1., Length@DeleteMissing[res[[All,2]]]]]};
  Export[FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[key] <> ".csv"}],
    Prepend[res, {"month","lat","lon"}], "CSV"];
  res];

centroidPathLengthKm[cs_List] := Total[
  GeoDistance[{cs[[#,2]], cs[[#,3]]}, {cs[[Mod[#,12]+1,2]], cs[[Mod[#,12]+1,3]]}] & /@ Range[12]
] /. q_Quantity :> QuantityMagnitude[UnitConvert[q, "Kilometers"]];
```

- [ ] **Step 4: Create driver `wolfram/centroids.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
src = If[Length[$ScriptCommandLine] > 1, $ScriptCommandLine[[2]], "sample"];
rows = Table[
  Module[{cs = monthlyCentroids[sp["key"], src]},
    {sp["key"], sp["common"], centroidPathLengthKm[cs]}], {sp, $speciesList}];
Export[FileNameJoin[{$repoRoot, "data", "path_lengths.csv"}],
  Prepend[rows, {"key","common","km"}], "CSV"];
Print["path lengths (km): ", rows[[All, {2,3}]]];
```

- [ ] **Step 5: Run driver + test**
Run: `wolframscript -file wolfram/centroids.wls sample` then
`wolframscript -file tests/test_centroids.wls`
Expected: path lengths printed; `PASS: 5/5`.

- [ ] **Step 6: Commit**
```bash
git add wolfram/centroids.wls wolfram/load_data.wl tests/test_centroids.wls data/centroids_*.csv data/path_lengths.csv
git commit -m "feat: gridded spherical monthly centroids + path length"
```

---

### Task 5: Seasonal density maps (`seasonal_maps.wls`)

**Files:**
- Create: `wolfram/seasonal_maps.wls`
- Test: `tests/test_seasonal_maps.wls`

**Interfaces:**
- Consumes: `loadOccurrences`, `monthlyCentroids`.
- Produces: `docs/images/seasonal_<key>.png` — a 12-panel (3×4) grid of monthly
  `GeoSmoothHistogram`/`GeoHistogram` density maps per species, centroid marked.

- [ ] **Step 1: Write the failing test** — `tests/test_seasonal_maps.wls`
```wolfram
dir = FileNameJoin[{DirectoryName[$InputFileName, 2], "docs", "images"}];
files = FileNameJoin[{dir, "seasonal_" <> ToString[#] <> ".png"}] & /@ {5229230,5228676,2481765};
ok = AllTrue[files, FileExistsQ[#] && FileByteCount[#] > 30000 &];
Print[If[ok, "PASS seasonal maps", "FAIL"]]; If[! ok, Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL (no PNGs).

- [ ] **Step 3: Write `wolfram/seasonal_maps.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
monNames = DateString[{2020, #, 1}, "MonthNameShort"] & /@ Range[12];

panel[key_, src_] := Module[{o = loadOccurrences[key, src], cs = monthlyCentroids[key, src]},
  Grid[Partition[Table[
    Module[{idx = Flatten@Position[o["month"], m], pts},
      pts = Transpose[{o["lat"][[idx]], o["lon"][[idx]]}];
      GeoHistogram[pts, Quantity[750, "Kilometers"],
        GeoRange -> "World", GeoProjection -> "Robinson",
        ColorFunction -> "TemperatureMap", PlotLabel -> monNames[[m]],
        GeoBackground -> GrayLevel[0.15], ImageSize -> 230,
        Epilog -> {}, PlotLegends -> None]],
    {m, 12}], 4]]];

Do[ Export[FileNameJoin[{$repoRoot, "docs", "images", "seasonal_" <> ToString[sp["key"]] <> ".png"}],
      panel[sp["key"], "sample"], "PNG", ImageResolution -> 120];
    Print["wrote seasonal_", sp["key"]], {sp, $speciesList}];
```
(Note for implementer: if `GeoHistogram` over `"World"` is slow, switch
`GeoRange -> "World"` to species-appropriate bounds; keep 12-panel layout.)

- [ ] **Step 4: Run script + test**
Run: `wolframscript -file wolfram/seasonal_maps.wls` then
`wolframscript -file tests/test_seasonal_maps.wls` → `PASS seasonal maps`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/seasonal_maps.wls tests/test_seasonal_maps.wls docs/images/seasonal_*.png
git commit -m "feat: monthly seasonal density map panels"
```

---

### Task 6: Live eBird API 2.0 layer (`ebird_live.wls`)

**Files:**
- Create: `wolfram/ebird_live.wls`
- Test: `tests/test_live.wls`

**Interfaces:**
- Consumes: `loadConfig["ebird_api_key.txt"]`, `$speciesList`.
- Produces: `data/live_<key>.csv` (`lat,lon,obsDt,locName`) and
  `docs/images/live_<key>.png` (recent-sightings map). Uses the species-scoped
  recent-observations endpoint over a set of regions (global coverage is not a
  single call; iterate a region list and dedupe).

- [ ] **Step 1: Write the failing test** — `tests/test_live.wls`
```wolfram
dir = FileNameJoin[{DirectoryName[$InputFileName, 2], "data"}];
img = FileNameJoin[{DirectoryName[$InputFileName, 2], "docs", "images"}];
csvOk = AllTrue[{5229230,5228676,2481765},
  FileExistsQ[FileNameJoin[{dir, "live_" <> ToString[#] <> ".csv"}]] &];
imgOk = AllTrue[{5229230,5228676,2481765},
  FileExistsQ[FileNameJoin[{img, "live_" <> ToString[#] <> ".png"}]] &];
Print[If[csvOk && imgOk, "PASS live layer", "FAIL"]]; If[! (csvOk && imgOk), Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Write `wolfram/ebird_live.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
token = loadConfig["ebird_api_key.txt"];
hdr = {"X-eBirdApiToken" -> token};
(* Recent obs of one species across a spread of regions, last 30 days *)
regions = {"US","CA","GB","IE","IS","NO","SE","FI","NL","FR","ES","PT","DE","DK",
           "ZA","AU","NZ","AR","CL","BR","MX","SN","MA","NA","CL","IN","JP","RU"};
fetch[code_, reg_] := Module[{j},
  j = httpGetJSON["https://api.ebird.org/v2/data/obs/" <> reg <> "/recent/" <> code <>
        "?back=30&maxResults=200", hdr];
  If[j === $Failed || ! ListQ[j], {},
    {#["lat"], #["lng"], Lookup[#,"obsDt",""], Lookup[#,"locName",""]} & /@ j]];

Do[ Module[{rows, pts, map},
   rows = DeleteDuplicates@Join @@ (fetch[sp["code"], #] & /@ regions);
   Export[FileNameJoin[{$repoRoot, "data", "live_" <> ToString[sp["key"]] <> ".csv"}],
     Prepend[rows, {"lat","lon","obsDt","locName"}], "CSV"];
   pts = {#[[1]], #[[2]]} & /@ Select[rows, NumberQ[#[[1]]] && NumberQ[#[[2]]] &];
   map = GeoListPlot[GeoPosition /@ pts, GeoRange -> "World",
     GeoProjection -> "Robinson", GeoBackground -> GrayLevel[0.15],
     PlotStyle -> Directive[Orange, Opacity[0.7], PointSize[0.006]],
     PlotLabel -> sp["common"] <> " — recent eBird sightings (last 30 d)",
     ImageSize -> 900];
   Export[FileNameJoin[{$repoRoot, "docs", "images", "live_" <> ToString[sp["key"]] <> ".png"}],
     map, "PNG", ImageResolution -> 120];
   Print[sp["common"], ": ", Length[pts], " live points"];
 ], {sp, $speciesList}];
```

- [ ] **Step 4: Run script + test**
Run: `wolframscript -file wolfram/ebird_live.wls` then
`wolframscript -file tests/test_live.wls` → `PASS live layer`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/ebird_live.wls tests/test_live.wls data/live_*.csv docs/images/live_*.png
git commit -m "feat: live eBird API 2.0 recent-sightings layer"
```

---

### Task 7: Combined hero animation (`hero.wls`)

The attention-grabber. Build for visual impact; iterate until it looks stunning.

**Files:**
- Create: `wolfram/hero.wls`
- Test: `tests/test_hero.wls`

**Interfaces:**
- Consumes: `monthlyCentroids` for all three species.
- Produces: `docs/images/hero.gif` and `docs/images/hero.mp4` — 12-frame loop.
  Top: orthographic globe (dark ocean) with each species' centroid as a glowing
  marker + fading comet-trail great-circle arc of the path so far (distinct
  colors). Bottom: synchronized monthly density (focal species or 3 small maps).

- [ ] **Step 1: Write the failing test** — `tests/test_hero.wls`
```wolfram
g = FileNameJoin[{DirectoryName[$InputFileName, 2], "docs", "images", "hero.gif"}];
ok = FileExistsQ[g] && FileByteCount[g] > 100000 &&
     Length[Import[g, {"GIF", "ImageList"}]] >= 12;
Print[If[ok, "PASS hero (" <> ToString[FileByteCount[g]] <> " bytes)", "FAIL"]];
If[! ok, Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Write `wolfram/hero.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
cols = <|5229230 -> RGBColor[1,0.35,0.2], 5228676 -> RGBColor[0.3,0.9,1],
         2481765 -> RGBColor[1,0.85,0.2]|>;
cents = Association[#["key"] -> monthlyCentroids[#["key"], "sample"] & /@ $speciesList];
monNames = DateString[{2020, #, 1}, "MonthName"] & /@ Range[12];

(* centre the orthographic globe on the swift's current centroid, slowly spun *)
frame[m_] := Module[{spin = 30 (m - 1)},
  GeoGraphics[
    Flatten@Table[ With[{cs = cents[k]},
      {(* comet-trail: arcs for months 1..m fading back *)
       Table[{cols[k], Opacity[0.15 + 0.75 (j/m)], Thickness[0.006],
          GeoPath[{{cs[[j,2]],cs[[j,3]]}, {cs[[j+1,2]],cs[[j+1,3]]}}]}, {j, Max[1,m-1]}],
       (* current marker glow *)
       {cols[k], Opacity[0.9], PointSize[0.02], Point[GeoPosition[{cs[[m,2]],cs[[m,3]]}]]}}],
      {k, Keys[cents]}],
    GeoRange -> "World", GeoProjection -> {"Orthographic",
       "Centering" -> {10, -60 + spin}},
    GeoBackground -> GeoStyling["StreetMapNoLabels", GrayLevel[0.1]],
    GeoGridLines -> Automatic, ImageSize -> 700,
    PlotLabel -> Style[monNames[[m]], White, 20]]];

frames = Table[Rasterize[frame[m], ImageSize -> 700], {m, 12}];
frames = ColorQuantize[#, 128] & /@ frames;
Export[FileNameJoin[{$repoRoot,"docs","images","hero.gif"}],
  AnimatedImage[frames, FrameRate -> 2], "GIF"];
Export[FileNameJoin[{$repoRoot,"docs","images","hero.mp4"}],
  AnimatedImage[frames, FrameRate -> 2], "MP4"];
Print["hero frames: ", Length[frames]];
```
(Implementer: this is the polish task — add the synchronized bottom density strip
via `Column[{globe, densityStrip[m]}]` before rasterizing, tune colors/easing/glow
until striking. The test only gates existence + frame count + size.)

- [ ] **Step 4: Run script + test**
Run: `wolframscript -file wolfram/hero.wls` then
`wolframscript -file tests/test_hero.wls` → `PASS hero (...)`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/hero.wls tests/test_hero.wls docs/images/hero.gif docs/images/hero.mp4
git commit -m "feat: combined hero animation (globe comet-trails + density)"
```

---

### Task 8: GBIF Download API → DOI (`gbif_download.wls`)

Replaces sample data with the citable full snapshot. Run once; slow (minutes).

**Files:**
- Create: `wolfram/gbif_download.wls`
- Test: `tests/test_dois.wls`

**Interfaces:**
- Consumes: `loadConfig["gbif_credentials.json"]`.
- Produces: per-species `data/raw/occ_<key>.csv` (header `lat,lon,month,year,count`,
  same schema as the sampler so `loadOccurrences[key,"full"]` just works) and
  `data/gbif_dois.json` (`{key -> {"doi"->..., "downloadKey"->...}}`).

- [ ] **Step 1: Write the failing test** — `tests/test_dois.wls`
```wolfram
f = FileNameJoin[{DirectoryName[$InputFileName, 2], "data", "gbif_dois.json"}];
If[! FileExistsQ[f], Print["FAIL: no gbif_dois.json"]; Exit[1]];
d = Import[f, "RawJSON"];
ok = AllTrue[{"5229230","5228676","2481765"}, KeyExistsQ[d, #] && StringContainsQ[d[#]["doi"], "doi.org"] &];
Print[If[ok, "PASS dois", "FAIL doi content"]]; If[! ok, Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Write `wolfram/gbif_download.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
cfg = loadConfig["gbif_credentials.json"];
EOD = "4fa7b334-ce0d-4e88-aaae-2e0c138d049e";
auth = <|"Username" -> cfg["username"], "Password" -> cfg["password"]|>;

predicate[key_] := ExportString[<|
  "creator" -> cfg["username"], "notificationAddresses" -> {cfg["email"]},
  "sendNotification" -> False, "format" -> "SIMPLE_CSV",
  "predicate" -> <|"type" -> "and", "predicates" -> {
     <|"type" -> "equals", "key" -> "TAXON_KEY", "value" -> ToString[key]|>,
     <|"type" -> "equals", "key" -> "DATASET_KEY", "value" -> EOD|>,
     <|"type" -> "equals", "key" -> "HAS_COORDINATE", "value" -> "true"|>,
     <|"type" -> "equals", "key" -> "BASIS_OF_RECORD", "value" -> "HUMAN_OBSERVATION"|>,
     <|"type" -> "and", "predicates" -> {
        <|"type"->"greaterThanOrEquals","key"->"YEAR","value"->"2014"|>,
        <|"type"->"lessThanOrEquals","key"->"YEAR","value"->"2024"|>}|>}|>
  |>, "RawJSON"];

submit[key_] := Module[{r},
  r = URLRead[HTTPRequest["https://api.gbif.org/v1/occurrence/download/request",
     <|Method -> "POST", "Headers" -> {"User-Agent" -> $userAgent, "Content-Type" -> "application/json"},
       "Body" -> predicate[key], "Username" -> auth["Username"], "Password" -> auth["Password"]|>]];
  If[r["StatusCode"] =!= 201, Print["submit failed ", r["StatusCode"], " ", r["Body"]]; Abort[]];
  StringTrim[r["Body"]]];

waitFor[dk_] := Module[{status = "", meta},
  While[! MemberQ[{"SUCCEEDED","KILLED","FAILED","CANCELLED"}, status],
    Pause[20];
    meta = httpGetJSON["https://api.gbif.org/v1/occurrence/download/" <> dk];
    status = meta["status"]; Print["  ", dk, ": ", status]];
  meta];

process[key_] := Module[{dk, meta, zip, dir, csv, d, rows},
  dk = submit[key]; Print["downloadKey ", key, " = ", dk];
  meta = waitFor[dk];
  If[meta["status"] =!= "SUCCEEDED", Abort[]];
  zip = FileNameJoin[{$repoRoot, "data", "raw", dk <> ".zip"}];
  URLDownload[meta["downloadLink"], zip];   (* binary asset; OK to use here *)
  dir = FileNameJoin[{$repoRoot, "data", "raw", "extract_" <> ToString[key]}];
  ExtractArchive[zip, dir, OverwriteTarget -> True];
  csv = First@FileNames["*.csv", dir];
  d = Import[csv, "TSV"];                    (* SIMPLE_CSV is tab-separated *)
  With[{h = First[d], body = Rest[d]},
    Module[{la, lo, mo, yr, ct},
      la = Position[h, "decimalLatitude"][[1,1]]; lo = Position[h,"decimalLongitude"][[1,1]];
      mo = Position[h, "month"][[1,1]]; yr = Position[h,"year"][[1,1]];
      ct = Position[h, "individualCount"]; ct = If[ct === {}, 0, ct[[1,1]]];
      rows = Select[
        {ToExpression[#[[la]]], ToExpression[#[[lo]]], ToExpression[#[[mo]]],
         ToExpression[#[[yr]]], If[ct == 0, 1, (ToExpression[#[[ct]]] /. Except[_?NumberQ] -> 1)]} & /@ body,
        NumberQ[#[[1]]] && NumberQ[#[[2]]] && IntegerQ[#[[3]]] &]]];
  Export[FileNameJoin[{$repoRoot, "data", "raw", "occ_" <> ToString[key] <> ".csv"}],
    Prepend[rows, {"lat","lon","month","year","count"}], "CSV"];
  <|"doi" -> "https://doi.org/" <> meta["doi"], "downloadKey" -> dk, "n" -> Length[rows]|>];

res = Association[ToString[#["key"]] -> process[#["key"]] & /@ $speciesList];
Export[FileNameJoin[{$repoRoot, "data", "gbif_dois.json"}], res, "RawJSON"];
Print["DOIs: ", #["doi"] & /@ Values[res]];
```

- [ ] **Step 2 (run): Submit + wait (slow)**
Run: `wolframscript -file wolfram/gbif_download.wls`
Expected: each species cycles `PREPARING/RUNNING → SUCCEEDED`, prints DOIs.
Then re-run analysis on full data:
`wolframscript -file wolfram/centroids.wls full`

- [ ] **Step 3: Run test** → `PASS dois`.

- [ ] **Step 4: Commit** (DOIs + tidy CSV only; `data/raw/` is git-ignored)
```bash
git add wolfram/gbif_download.wls tests/test_dois.wls data/gbif_dois.json data/centroids_*.csv data/path_lengths.csv
git commit -m "feat: GBIF Download API snapshot with citable DOIs"
```

---

### Task 9: eBird Status & Trends via R (`ebirdst_r.wls`)

Runs only once `config/ebirdst_key.txt` exists and `ebirdst` is installed.

**Files:**
- Create: `wolfram/ebirdst_r.wls`
- Test: `tests/test_ebirdst.wls`

**Interfaces:**
- Consumes: `loadConfig["ebirdst_key.txt"]`, `ExternalEvaluate["R"]`.
- Produces: `data/centroids_st_<key>.csv` (`week,lat,lon`, 52 rows) per species.

- [ ] **Step 1: Setup — install ebirdst (one-off, document)**
Run:
```bash
Rscript -e 'install.packages(c("ebirdst","terra"), repos="https://cloud.r-project.org")'
```
Expected: packages install (terra needs GDAL; on macOS via Homebrew if missing).

- [ ] **Step 2: Write the failing test** — `tests/test_ebirdst.wls`
```wolfram
ok = AllTrue[{5229230,5228676,2481765}, Module[{f =
   FileNameJoin[{DirectoryName[$InputFileName,2],"data","centroids_st_"<>ToString[#]<>".csv"}]},
   FileExistsQ[f] && Length[Import[f,"CSV"]] >= 50] &];
Print[If[ok, "PASS ebirdst", "FAIL (need S&T key + ebirdst install)"]]; If[!ok, Exit[1]];
```

- [ ] **Step 3: Run to verify it fails** → FAIL.

- [ ] **Step 4: Write `wolfram/ebirdst_r.wls`**
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
key = loadConfig["ebirdst_key.txt"];
sess = StartExternalSession["R"];
ExternalEvaluate[sess, "library(ebirdst); library(terra)"];
ExternalEvaluate[sess, "set_ebirdst_access_key('" <> key <> "', overwrite=TRUE)"];

stCentroids[code_] := Module[{rcode, tbl},
  rcode = "sp<-'" <> code <> "'
    ebirdst_download_status(sp, download_abundance=TRUE, pattern='abundance_seasonal|abundance_median', res='27km')
    r<-load_raster(sp, product='abundance', period='weekly', resolution='27km')
    xy<-terra::xyFromCell(r, 1:terra::ncell(r))
    out<-data.frame()
    for(i in 1:terra::nlyr(r)){ v<-terra::values(r[[i]]); v[is.na(v)]<-0
      if(sum(v)>0){ lon<-sum(xy[,1]*v)/sum(v); lat<-sum(xy[,2]*v)/sum(v) }
      else { lon<-NA; lat<-NA }
      out<-rbind(out, data.frame(week=i, lat=lat, lon=lon)) }
    out";
  ExternalEvaluate[sess, rcode]];

Do[ Module[{df = stCentroids[sp["code"]]},
   Export[FileNameJoin[{$repoRoot,"data","centroids_st_"<>ToString[sp["key"]]<>".csv"}],
     Prepend[Normal@Values@df, {"week","lat","lon"}] /. Null -> "", "CSV"];
   Print[sp["common"], ": ", Length[df["week"]], " weekly S&T centroids"];
 ], {sp, $speciesList}];
DeleteObject[sess];
```
(Note: S&T raster CRS is equal-area Mollweide-like; reproject centroid xy back to
lon/lat with `terra::project` if `xyFromCell` is not already in lon/lat — verify
on first run and add `r<-terra::project(r,'EPSG:4326')` if needed.)

- [ ] **Step 5: Run script + test** → `PASS ebirdst`.

- [ ] **Step 6: Commit**
```bash
git add wolfram/ebirdst_r.wls tests/test_ebirdst.wls data/centroids_st_*.csv
git commit -m "feat: eBird Status & Trends weekly centroids via R ebirdst"
```

---

### Task 10: Static figures + GBIF-vs-S&T overlay (`figures.wls`)

**Files:**
- Create: `wolfram/figures.wls`
- Test: `tests/test_figures.wls`

**Interfaces:**
- Consumes: `data/centroids_*.csv`, `data/centroids_st_*.csv` (if present),
  `data/path_lengths.csv`.
- Produces: `docs/images/centroid_track_<key>.png` (per species, GBIF track on a
  globe with month labels), `docs/images/path_lengths.png` (bar chart),
  `docs/images/st_vs_gbif_<key>.png` (overlay; only if S&T CSV exists).

- [ ] **Step 1: Write the failing test** — `tests/test_figures.wls`
```wolfram
img = FileNameJoin[{DirectoryName[$InputFileName,2],"docs","images"}];
need = Join[FileNameJoin[{img,"centroid_track_"<>ToString[#]<>".png"}]&/@{5229230,5228676,2481765},
            {FileNameJoin[{img,"path_lengths.png"}]}];
ok = AllTrue[need, FileExistsQ[#] && FileByteCount[#] > 10000 &];
Print[If[ok,"PASS figures","FAIL"]]; If[!ok, Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Write `wolfram/figures.wls`** (track + bars required; overlay conditional)
```wolfram
#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
loadCsv[f_] := Rest@Import[f, "CSV"];
img = FileNameJoin[{$repoRoot, "docs", "images"}];

Do[ Module[{cs = loadCsv[FileNameJoin[{$repoRoot,"data","centroids_"<>ToString[sp["key"]]<>".csv"}]], g},
   g = GeoGraphics[{
        Red, Thick, GeoPath[{#[[2]],#[[3]]} & /@ cs ~Join~ {First[cs]}],
        Black, Table[Text[Style[ToString[cs[[m,1]]],10,White,Bold],
           GeoPosition[{cs[[m,2]],cs[[m,3]]}]], {m, Length[cs]}]},
        GeoRange->"World", GeoProjection->"Robinson", GeoBackground->GrayLevel[0.15],
        PlotLabel->sp["common"]<>" — monthly population centroid", ImageSize->900];
   Export[FileNameJoin[{img,"centroid_track_"<>ToString[sp["key"]]<>".png"}], g, "PNG"];
 ], {sp, $speciesList}];

pl = loadCsv[FileNameJoin[{$repoRoot,"data","path_lengths.csv"}]];
Export[FileNameJoin[{img,"path_lengths.png"}],
  BarChart[pl[[All,3]], ChartLabels->pl[[All,2]], BarOrigin->Left,
    PlotLabel->"Annual centroid travel (km)", ImageSize->700], "PNG"];

(* conditional S&T overlay *)
Do[ Module[{stf = FileNameJoin[{$repoRoot,"data","centroids_st_"<>ToString[sp["key"]]<>".csv"}], st, gb},
   If[FileExistsQ[stf],
     st = loadCsv[stf]; gb = loadCsv[FileNameJoin[{$repoRoot,"data","centroids_"<>ToString[sp["key"]]<>".csv"}]];
     Export[FileNameJoin[{img,"st_vs_gbif_"<>ToString[sp["key"]]<>".png"}],
       GeoGraphics[{Orange,Thick,GeoPath[{#[[2]],#[[3]]}&/@st],
                    Cyan,Dashed,Thick,GeoPath[{#[[2]],#[[3]]}&/@gb]},
         GeoRange->"World", GeoProjection->"Robinson", GeoBackground->GrayLevel[0.15],
         PlotLabel->sp["common"]<>" — S&T (orange) vs GBIF occurrence (cyan)", ImageSize->900], "PNG"]];
 ], {sp, $speciesList}];
Print["figures done"];
```

- [ ] **Step 4: Run script + test** → `PASS figures`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/figures.wls tests/test_figures.wls docs/images/centroid_track_*.png docs/images/path_lengths.png docs/images/st_vs_gbif_*.png
git commit -m "feat: centroid-track, path-length, and S&T-vs-GBIF figures"
```

---

### Task 11: Pipeline driver (`run_all.wls`)

**Files:**
- Create: `wolfram/run_all.wls`
- Test: `tests/test_run_all.wls`

**Interfaces:**
- Produces: runs centroids → seasonal_maps → figures → hero in order on the given
  source (`sample`|`full`, default `full` if `data/gbif_dois.json` exists else `sample`).

- [ ] **Step 1: Write the failing test** — `tests/test_run_all.wls`
```wolfram
(* after run, the key artifacts all exist *)
img = FileNameJoin[{DirectoryName[$InputFileName,2],"docs","images"}];
ok = AllTrue[{"hero.gif","path_lengths.png","seasonal_5229230.png","centroid_track_5229230.png"},
   FileExistsQ[FileNameJoin[{img,#}]] &];
Print[If[ok,"PASS run_all artifacts","FAIL"]]; If[!ok, Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** (only if artifacts cleared) — otherwise note dependence.

- [ ] **Step 3: Write `wolfram/run_all.wls`**
```wolfram
#!/usr/bin/env wolframscript
root = DirectoryName[$InputFileName];
src = If[FileExistsQ[FileNameJoin[{ParentDirectory[root],"data","gbif_dois.json"}]], "full", "sample"];
Print["=== run_all source = ", src, " ==="];
Run["wolframscript -file " <> FileNameJoin[{root,"centroids.wls"}] <> " " <> src];
Run["wolframscript -file " <> FileNameJoin[{root,"seasonal_maps.wls"}]];
Run["wolframscript -file " <> FileNameJoin[{root,"figures.wls"}]];
Run["wolframscript -file " <> FileNameJoin[{root,"hero.wls"}]];
Print["=== run_all done ==="];
```

- [ ] **Step 4: Run script + test** → `PASS run_all artifacts`.

- [ ] **Step 5: Commit**
```bash
git add wolfram/run_all.wls tests/test_run_all.wls
git commit -m "feat: one-shot pipeline driver"
```

---

### Task 12: Notebook helper package (`birdflightpaths_helpers.wl`)

Runnable symbols the notebook's `Input` cells call (so a Community reader can
shift-Enter each figure).

**Files:**
- Create: `community/birdflightpaths_helpers.wl`
- Test: `tests/test_helpers.wls`

**Interfaces:**
- Produces (self-contained — does NOT depend on repo paths; reads CSVs shipped
  beside the notebook or refetches): `monthNames`, `speciesColors`,
  `sphericalCentroid` (re-exported), `loadCentroidCSV[key]`, `centroidGlobe[key]`,
  `LoadLiveSightings[code]` (live API call using a reader-supplied token).

- [ ] **Step 1: Write the failing test** — `tests/test_helpers.wls`
```wolfram
Get[FileNameJoin[{DirectoryName[$InputFileName,2],"community","birdflightpaths_helpers.wl"}]];
asserts = {Length[monthNames]===12, ColorQ[speciesColors[5229230]],
  ListQ[sphericalCentroid[{0.,0.},{170.,-170.},{1.,1.}]]};
Print["PASS: ", Count[asserts,True],"/",Length[asserts]]; If[!And@@asserts, Exit[1]];
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Write `community/birdflightpaths_helpers.wl`** — port
  `sphericalCentroid`, `monthlyCentroids` (CSV-reading variant), color map, month
  names, and a `LoadLiveSightings` that takes the token as an argument. (Full code
  ported from `wolfram/load_data.wl` + `wolfram/ebird_live.wls`, parameterized so
  it has no repo-path dependency.)

- [ ] **Step 4: Run test** → `PASS: 3/3`.

- [ ] **Step 5: Commit**
```bash
git add community/birdflightpaths_helpers.wl tests/test_helpers.wls
git commit -m "feat: notebook helper package"
```

---

### Task 13: Build the community notebook (`build_notebook.wls`)

**Files:**
- Create: `community/build_notebook.wls`
- Output: `community/bird_migration.nb`, `community/bird_migration.pdf`
- Test: `tests/test_notebook.wls`

**Interfaces:**
- Consumes: all `docs/images/*.png|gif`, `data/path_lengths.csv`,
  `data/gbif_dois.json`.
- Produces: the notebook with blue headers + title + hero + all 11 sections + no
  how-to-cite section.

- [ ] **Step 1: Inspect reference header blue**
Run: `wolframscript -code 'nb=Import["/Users/thiel/Desktop/125916155.nb"]; Cases[nb, Cell[_,"Section",o___]:>{o}, Infinity]//Short'`
Record the `FontColor`/style used; reuse it for `hd1`/`hd2`.

- [ ] **Step 2: Write the failing test** — `tests/test_notebook.wls`
```wolfram
nb = FileNameJoin[{DirectoryName[$InputFileName,2],"community","bird_migration.nb"}];
If[!FileExistsQ[nb], Print["FAIL: no notebook"]; Exit[1]];
e = Import[nb];
titleOk = Length[Cases[e, Cell[_,"Title",___], Infinity]] >= 1;
noCite = Cases[e, Cell[t_String,___]/;StringContainsQ[t,"How to cite",IgnoreCase->True]:>t, Infinity] === {};
secOk = Length[Cases[e, Cell[_,"Section",___], Infinity]] >= 8;
heroOk = Length[Cases[e, _AnimatedImage, Infinity]] >= 1 ||
         FileByteCount[nb] > 2*10^6;  (* hero raster embedded *)
Print["title:",titleOk," noCite:",noCite," sections:",secOk," hero:",heroOk];
If[!(titleOk && noCite && secOk && heroOk), Exit[1]];
Print["PASS notebook"];
```

- [ ] **Step 3: Run to verify it fails** → FAIL.

- [ ] **Step 4: Write `community/build_notebook.wls`**
Port the ENSO builder's cell-helper architecture (`title`, `subtitle`, `hd1/2/3`,
`para`, `abstractCell`, `imgCell`, `animCell`, `captionCell`, `wlIn`, `codeIn`,
`aiNote`, `link`) verbatim as the foundation, then assemble the 11 sections from
the spec (§8). Set `hd1`/`hd2` `FontColor` to the blue recorded in Step 1. Embed
`hero.gif` via `animCell` directly under the title. Include the runnable `Input`
cells that reproduce each figure (the same code from `wolfram/*.wls`, lightly
adapted to call the helper package). End with References, Acknowledgements (eBird
citizen scientists + Cornell Lab + GBIF; both licenses), Reproducibility (the DOI
from `gbif_dois.json`). **No "How to cite" section.** Export `.nb` and `.pdf`.

- [ ] **Step 5: Run builder + test**
Run: `wolframscript -file community/build_notebook.wls` then
`wolframscript -file tests/test_notebook.wls` → `PASS notebook`.

- [ ] **Step 6: Commit**
```bash
git add community/build_notebook.wls community/bird_migration.nb community/bird_migration.pdf tests/test_notebook.wls
git commit -m "feat: build community notebook (bird_migration.nb + pdf)"
```

---

### Task 14: Final review pass

**Files:** README.md, CLAUDE.md (touch-ups only)

- [ ] **Step 1:** Run the whole pipeline clean: `wolframscript -file wolfram/run_all.wls` then `wolframscript -file community/build_notebook.wls`.
- [ ] **Step 2:** Open `community/bird_migration.nb` in the FrontEnd; confirm hero plays, headers are blue, no how-to-cite, all figures present, licenses/DOI correct.
- [ ] **Step 3:** Run every test: `for t in tests/*.wls; do wolframscript -file $t; done` — all PASS.
- [ ] **Step 4:** Secret-scan the whole repo against the config-derived secrets
  (reuse the Global Constraints guard's `$SECRETS`): `git grep -nE "$SECRETS" || echo CLEAN`.
- [ ] **Step 5:** Commit any touch-ups; offer to push / use `finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:** §1 goal → Tasks 13–14; §2 licensing → Tasks 8,9,13; §3 layout →
all; §4 Path A → Tasks 2,8; §5 method (gridding/spherical/path) → Task 4; §6 Path B
→ Task 9; §6b Path C → Task 6; §7 hero → Task 7; §8 notebook → Tasks 12,13; §9
credentials → Tasks 1,8,9; §10 defaults → Tasks 4,8. All covered.

**Placeholder scan:** Code provided for every code step. Two tasks (7 hero polish,
13 builder) carry explicit "port from ENSO / iterate visually" guidance with a
concrete starting implementation and a gating test — intentional, since graphics
polish and a 2000-line builder are iterative; the tests bound the deliverable.

**Type consistency:** CSV schema `lat,lon,month,year,count` is identical across
sampler (Task 2), loader (Task 3), and full download (Task 8) so
`loadOccurrences[key,"full"]` works unchanged. `monthlyCentroids` returns 12×3
`{month,lat,lon}` consumed identically by Tasks 5,7,10. Species records expose
`key`/`code`/`common`/`sci` used consistently.
