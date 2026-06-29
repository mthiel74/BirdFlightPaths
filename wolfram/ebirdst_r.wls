#!/usr/bin/env wolframscript
(* eBird Status & Trends PRIVATE validation of the GBIF centroid tracks.

   Cornell Lab terms forbid redistributing (modified) S&T Data Products.  Every
   artifact this script produces -- the downloaded rasters under
   data/raw/ebirdst/, data/centroids_st_<key>.csv, data/raw/ebirdst/validation.json
   -- is GIT-IGNORED and stays LOCAL.  Only this script + its test are committed.

   For each flyway species we ask R (via ExternalEvaluate) + ebirdst + terra to
   download the WEEKLY 27km relative-abundance raster, project to lon/lat, crop to
   the SAME flyway box used for the GBIF primary track, and return 52 weekly
   abundance-weighted centroids.  WL resamples those to 12 monthly means and
   measures the great-circle separation from the GBIF monthly track. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];  (* sphericalCentroid *)

key = loadConfig["ebirdst_key.txt"];  (* never printed *)

(* Per-flyway lon/lat boxes {lonmin,lonmax,latmin,latmax} and scientific names.
   These MUST match wolfram/centroids.wls. *)
boxes = <|5228676 -> {-30, 145, -40, 75},
          2481765 -> {-110, -30, -56, 85},
          5229230 -> {-80, 20, -90, 90}|>;
sci   = <|5228676 -> "Apus apus",
          2481765 -> "Calidris canutus",
          5229230 -> "Sterna paradisaea"|>;
keys  = {5228676, 2481765, 5229230};

valDir = FileNameJoin[{$repoRoot, "data", "raw", "ebirdst"}];
If[! DirectoryQ[valDir], CreateDirectory[valDir, CreateIntermediateDirectories -> True]];

(* ---- week -> month mapping (non-leap cumulative day-of-year ends) ---------- *)
monthEnds = {31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365};
weekMonth[i_, n_] := Module[{doy = Clip[Round[(i - 0.5)*365.0/n], {1, 365}]},
  SelectFirst[Range[12], doy <= monthEnds[[#]] &, 12]];

(* ---- 52 weekly {week,lat,lon} -> 12 monthly {month,lat,lon} (or Missing) --- *)
weeklyToMonthly[weeks_List, lats_List, lons_List] := Module[{n = Length[weeks], wm, allpts},
  wm = weekMonth[#, n] & /@ weeks;
  allpts = Transpose[{lats, lons}];
  Table[
    Module[{pts, c},
      pts = Select[Pick[allpts, wm, m], NumberQ[#[[1]]] && NumberQ[#[[2]]] &];
      If[pts === {},
        {m, Missing[], Missing[]},
        c = sphericalCentroid[pts[[All, 1]], pts[[All, 2]], ConstantArray[1., Length[pts]]];
        If[MatchQ[c, _Missing], {m, Missing[], Missing[]}, {m, c[[1]], c[[2]]}]]],
    {m, 12}]];

(* ---- great-circle separation (km) over months finite in BOTH tracks ------- *)
sepKm[stMonthly_List, gbifMonthly_Association] := Module[{ds},
  ds = Cases[stMonthly,
    {m_, la_?NumberQ, lo_?NumberQ} /;
      KeyExistsQ[gbifMonthly, m] && NumberQ[gbifMonthly[m][[1]]] :>
      QuantityMagnitude@UnitConvert[
        GeoDistance[{la, lo}, {gbifMonthly[m][[1]], gbifMonthly[m][[2]]}], "Kilometers"]];
  <|"mean" -> If[ds === {}, Missing[], Mean[ds]],
    "max"  -> If[ds === {}, Missing[], Max[ds]],
    "months" -> Length[ds]|>];

(* ---- read a GBIF monthly track -> <|month -> {lat,lon} | Missing|> --------- *)
readGbif[k_] := Module[{p, rows},
  p = FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[k] <> ".csv"}];
  If[! FileExistsQ[p], Return[$Failed]];
  rows = Rest[Import[p, "CSV"]];  (* drop header; cells "" -> Missing month *)
  Association[(#[[1]] -> If[NumberQ[#[[2]]] && NumberQ[#[[3]]], {#[[2]], #[[3]]}, Missing[]]) & /@ rows]];

(* ===================== R session ========================================== *)
sess = StartExternalSession["R"];
ExternalEvaluate[sess, "suppressMessages({library(ebirdst); library(terra)})"];
ExternalEvaluate[sess, "set_ebirdst_access_key('" <> key <> "', overwrite=TRUE)"];

(* Resolve a scientific name to its S&T species_code; "" when absent. *)
ExternalEvaluate[sess, "
resolveCode <- function(sci) {
  r <- ebirdst_runs[grepl(sci, ebirdst_runs$scientific_name, ignore.case=TRUE), ]
  if (nrow(r) == 0) '' else as.character(r$species_code[1])
}"];

(* Download (median weekly abundance only) + load 27km weekly abundance,
   project to EPSG:4326, crop to box, return 52 weekly abundance-weighted
   centroids as a data.frame {week,lat,lon}. *)
ExternalEvaluate[sess, "
stCentroids <- function(sp, lonmin, lonmax, latmin, latmax, dpath) {
  ebirdst_download_status(sp, path=dpath, download_abundance=TRUE,
                          pattern='abundance_median', show_progress=FALSE)
  r <- load_raster(sp, product='abundance', period='weekly', resolution='27km', path=dpath)
  r <- terra::project(r, 'EPSG:4326')
  r <- terra::crop(r, terra::ext(lonmin, lonmax, latmin, latmax))
  xy <- terra::xyFromCell(r, 1:terra::ncell(r))
  vals <- terra::values(r)
  vals[is.na(vals)] <- 0
  sw <- colSums(vals)
  lon <- ifelse(sw > 0, colSums(xy[,1]*vals)/sw, NA)
  lat <- ifelse(sw > 0, colSums(xy[,2]*vals)/sw, NA)
  data.frame(week=seq_len(terra::nlyr(r)), lat=as.numeric(lat), lon=as.numeric(lon))
}"];

results = <||>;
unavailable = {};

Do[
  Module[{k = keys[[ix]], box, name, codeRaw, code, df, cols, weeks, lats, lons, stMonthly,
          gbif, sep, stCsv},
    box = boxes[k]; name = sci[k];
    Print["[", name, " / ", k, "] resolving in ebirdst_runs ..."];
    (* ExternalEvaluate returns a length-1 R character vector as a WL List. *)
    codeRaw = ExternalEvaluate[sess, "resolveCode('" <> name <> "')"];
    code = Which[
      StringQ[codeRaw], codeRaw,
      ListQ[codeRaw] && Length[codeRaw] >= 1 && StringQ[First[codeRaw]], First[codeRaw],
      True, ""];
    If[! StringQ[code] || code === "",
      Print["  NOT in S&T -- skipping (recorded unavailable)."];
      AppendTo[unavailable, k]; Continue[]];
    Print["  species_code = ", code, "; downloading + loading 27km weekly raster (slow) ..."];
    df = ExternalEvaluate[sess,
      "stCentroids('" <> code <> "', " <>
        ToString[box[[1]]] <> ", " <> ToString[box[[2]]] <> ", " <>
        ToString[box[[3]]] <> ", " <> ToString[box[[4]]] <> ", '" <> valDir <> "')"];
    If[FailureQ[df] || ! MatchQ[df, _RDataFrame],
      Print["  R FAILED for ", code, ": ", df];
      AppendTo[unavailable, k]; Continue[]];
    cols  = List @@ First[Cases[df, _RData, {0, Infinity}]];
    weeks = cols[[1]]; lats = cols[[2]]; lons = cols[[3]];
    Print["  got ", Length[weeks], " weekly centroids."];

    (* write git-ignored data/centroids_st_<key>.csv (52 weekly rows) *)
    stCsv = Prepend[
      Transpose[{weeks, lats /. Missing[] -> "", lons /. Missing[] -> ""}],
      {"week", "lat", "lon"}];
    Export[FileNameJoin[{$repoRoot, "data", "centroids_st_" <> ToString[k] <> ".csv"}],
      stCsv, "CSV"];

    stMonthly = weeklyToMonthly[weeks, lats, lons];
    gbif = readGbif[k];
    If[gbif === $Failed,
      Print["  no GBIF track data/centroids_", k, ".csv -- cannot compare."];
      AppendTo[unavailable, k]; Continue[]];
    sep = sepKm[stMonthly, gbif];
    Print["  meanSepKm = ", sep["mean"], "  maxSepKm = ", sep["max"],
          "  (months compared: ", sep["months"], ")"];
    results[ToString[k]] = <|"meanSepKm" -> sep["mean"], "maxSepKm" -> sep["max"],
                             "weeks" -> Length[weeks], "monthsCompared" -> sep["months"],
                             "speciesCode" -> code|>;
  ],
  {ix, Length[keys]}];

DeleteObject[sess];

results["_unavailable"] = unavailable;
(* RawJSON cannot encode Missing[]; emit null for any species with no overlap. *)
Export[FileNameJoin[{valDir, "validation.json"}], results /. _Missing -> Null, "RawJSON"];
Print["wrote ", FileNameJoin[{valDir, "validation.json"}], " (git-ignored)"];
Print["DONE. validated ", Length[KeyDrop[results, "_unavailable"]], " species; unavailable: ", unavailable];
