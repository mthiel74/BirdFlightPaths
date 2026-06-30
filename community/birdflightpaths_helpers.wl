(* ::Package:: *)

(* ============================================================================
   BirdFlightPaths — companion package for the Wolfram Community notebook
   community/birdflightpaths_helpers.wl

   SELF-CONTAINED. To run the notebook you need only TWO files in the same
   folder: the notebook (bird_migration.nb) and this package. Everything the
   runnable cells need is here — there are no other file dependencies and no
   bundled data: the analysis FETCHES its data live from public sources.

   ----------------------------------------------------------------------------
   WHAT YOU NEED (and where to get it)
   ----------------------------------------------------------------------------
   * Core analysis (occurrences, centroids, maps, globes):
       NOTHING. It pulls eBird observations through GBIF's public API
       (the eBird Observation Dataset, CC BY 4.0) anonymously — no account.

   * Live "recent sightings" layer (LoadLiveSightings):
       a free eBird API 2.0 token. Get one in 1 minute:
         1. make/sign in to an eBird account at  https://ebird.org
         2. request a token at                   https://ebird.org/api/keygen
         3. paste it into $ebirdApiToken below (replace the placeholder).

   * eBird Status & Trends cross-check (the §"Status & Trends" code):
       the R package `ebirdst` plus a free Status & Trends access key from
         https://science.ebird.org/en/status-and-trends/download-data
       (research/education; non-commercial — see the notebook's licensing note).

   * Citable GBIF DOI download (optional, for the exact archived snapshot):
       a free GBIF account at  https://www.gbif.org  (the anonymous fetch used
       here needs no account; the DOI download does).

   NO credentials are stored in this file or the notebook — only placeholders.
   ============================================================================ *)

(* ── CREDENTIAL PLACEHOLDER (replace before using the live layer) ──────────── *)
$ebirdApiToken = "<<PASTE-YOUR-EBIRD-API-2.0-TOKEN — https://ebird.org/api/keygen>>";

(* ── Species metadata ─────────────────────────────────────────────────────── *)
(* GBIF usageKeys; eBird species codes; per-flyway boxes {lonMin,lonMax,latMin,latMax} *)
speciesColors[5229230] := RGBColor[1, 0.4, 0.25];   (* Arctic tern  — orange *)
speciesColors[5228676] := RGBColor[0.35, 0.9, 1.];  (* Common swift — cyan   *)
speciesColors[2481765] := RGBColor[1, 0.85, 0.25];  (* Red knot     — gold   *)
speciesName[5229230] := "Arctic tern";
speciesName[5228676] := "Common swift";
speciesName[2481765] := "Red knot";
speciesCode[5229230] := "arcter";    (* eBird codes, for LoadLiveSightings *)
speciesCode[5228676] := "comswi";
speciesCode[2481765] := "redkno";
flywayBox[5229230] := {-80, 20, -90, 90};      (* Arctic tern — Atlantic basin     *)
flywayBox[5228676] := {-30, 145, -40, 75};     (* Common swift — Afro-Palearctic   *)
flywayBox[2481765] := {-110, -30, -56, 85};    (* Red knot — Americas flyway       *)
monthNames = DateString[{2020, #, 1}, "MonthName"] & /@ Range[12];

(* ── HTTP / JSON (decode from response bytes: avoids a WL UTF-8 round-trip bug) ─ *)
$BFPuserAgent = "BirdFlightPaths-notebook/1.0 (https://github.com/mthiel74/BirdFlightPaths)";
bfpGetJSON[url_String, headers_: {}] := Module[{r},
  r = URLRead[HTTPRequest[url,
     <|"Headers" -> Join[{"User-Agent" -> $BFPuserAgent}, headers]|>]];
  If[r["StatusCode"] =!= 200, Return[$Failed]];
  Quiet @ ImportByteArray[r["BodyByteArray"], "RawJSON"]];

(* ── Spherical centroid: weighted mean of (lat,lon) on the sphere ─────────────
   Returns {lat,lon} in degrees, or Missing["DegenerateCentroid"] when the
   resultant vector ~0 (antipodally-smeared points) — never a fake longitude. *)
sphericalCentroid[lats_List, lons_List, w_List] := Module[{v, m},
  v = MapThread[Function[{la, lo, wt},
        wt {Cos[la Degree] Cos[lo Degree], Cos[la Degree] Sin[lo Degree], Sin[la Degree]}],
        {lats, lons, w}];
  m = Total[v];
  If[Norm[m] < 10^-9, Return[Missing["DegenerateCentroid"]]];
  m = m/Norm[m];
  {ArcSin[m[[3]]]/Degree, ArcTan[m[[1]], m[[2]]]/Degree}];

(* ── Fetch eBird occurrences via GBIF (anonymous, no account) ─────────────────
   Pulls up to perMonth records for each calendar month of the eBird Observation
   Dataset (datasetKey 4fa7b334-…, CC BY 4.0) for a species, 2014–2024, with
   coordinates. Returns {{lat,lon,month}, …}. Results are memoised so repeated
   figure cells don't refetch. *)
$BFP$EOD = "4fa7b334-ce0d-4e88-aaae-2e0c138d049e";
FetchOccurrences[key_Integer, perMonth_: 300] := FetchOccurrences[key, perMonth] =
  Module[{rows},
   rows = Join @@ Table[
     Module[{j = bfpGetJSON[
        "https://api.gbif.org/v1/occurrence/search?taxonKey=" <> ToString[key] <>
        "&datasetKey=" <> $BFP$EOD <> "&hasCoordinate=true&month=" <> ToString[m] <>
        "&year=2014,2024&limit=" <> ToString[perMonth]]},
       If[j === $Failed || ! KeyExistsQ[j, "results"], {},
        Select[{#["decimalLatitude"], #["decimalLongitude"], m} & /@ j["results"],
          NumberQ[#[[1]]] && NumberQ[#[[2]]] &]]],
     {m, 12}];
   rows];

(* ── Monthly per-flyway population centroid (fetch → grid → spherical mean) ────
   ~2° presence-weighted grid inside the species' flyway box. Returns the
   observed-month track {{month,lat,lon}, …} (Missing months dropped). *)
monthlyCentroids[key_Integer] := monthlyCentroids[key] =
  Module[{occ, box = flywayBox[key], inBox, res},
   occ = FetchOccurrences[key];
   inBox = Select[occ,
     box[[1]] <= #[[2]] <= box[[2]] && box[[3]] <= #[[1]] <= box[[4]] &];
   res = Table[
     Module[{pts = Select[inBox, #[[3]] == m &], cells},
       If[pts === {}, Nothing,
        cells = Values @ GroupBy[pts, {Round[#[[1]]/2], Round[#[[2]]/2]} &,
           {Mean[#[[All, 1]]], Mean[#[[All, 2]]]} &];   (* one point per occupied cell *)
        With[{c = sphericalCentroid[cells[[All, 1]], cells[[All, 2]],
              ConstantArray[1., Length[cells]]]},
          If[Head[c] === List, {m, c[[1]], c[[2]]}, Nothing]]]],
     {m, 12}];
   res];

(* ── Globe of a species' centroid track (vector basemap = reliable everywhere) ─ *)
centroidGlobe[key_Integer] := Module[{rows = monthlyCentroids[key], col = speciesColors[key], pts},
  If[rows === {}, Return[$Failed]];
  pts = {#[[2]], #[[3]]} & /@ rows;
  GeoGraphics[
    {col, Thick, GeoPath[GeoPosition /@ pts],
     {col, PointSize[0.02], Point[GeoPosition /@ pts]},
     MapThread[Text[Style[ToString[#2], 8, White, Bold], GeoPosition[#1]] &,
        {pts, rows[[All, 1]]}]},
    GeoProjection -> {"Orthographic", "Centering" -> GeoPosition[Mean[pts]]},
    GeoBackground -> Automatic,
    PlotLabel -> speciesName[key] <> " — monthly population centroid",
    ImageSize -> 520]];

(* ── Live eBird "recent sightings" (needs your eBird API 2.0 token) ───────────
   code: eBird species code (e.g. speciesCode[5229230]); token: your key.
   Returns {{lat,lon}, …} rounded to 0.1° (privacy). Attribute eBird.org. *)
LoadLiveSightings[code_String, token_String] := Module[{regions, fetch},
  If[StringContainsQ[token, "PASTE"],
    Message[LoadLiveSightings::notoken]; Return[$Failed]];
  regions = {"US","CA","GB","IE","IS","NO","SE","FI","NL","FR","ES","PT","DE","DK",
             "ZA","AU","NZ","AR","CL","BR","MX","SN","MA","NA","IN","JP","RU"};
  fetch[reg_] := Module[{j = bfpGetJSON[
     "https://api.ebird.org/v2/data/obs/" <> reg <> "/recent/" <> code <>
     "?back=30&maxResults=200", {"X-eBirdApiToken" -> token}]},
    If[j === $Failed || ! ListQ[j], {},
     Select[{Round[#["lat"], 0.1], Round[#["lng"], 0.1]} & /@ j,
       NumberQ[#[[1]]] && NumberQ[#[[2]]] &]]];
  DeleteDuplicates[Join @@ (fetch /@ regions)]];
LoadLiveSightings::notoken =
  "Set $ebirdApiToken to your eBird API 2.0 key first (free: https://ebird.org/api/keygen).";

(* Quick check that the package loaded. *)
Print["BirdFlightPaths helpers loaded. Try:  centroidGlobe[5229230]   (fetches public GBIF data; no login)."];
