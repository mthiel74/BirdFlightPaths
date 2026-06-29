(* ::Package:: *)

(* ============================================================================
   BirdFlightPaths community notebook helper package
   community/birdflightpaths_helpers.wl

   Self-contained: no repo-path assumptions. All file I/O is relative to
   BFPDataDir[], which defaults to a "data" sub-folder beside the notebook
   (or Directory[] when loaded from a plain script). Override by setting the
   global $BFPDataDir to an absolute path string before calling Get[].

   Do NOT call the network at load time — LoadLiveSightings[] fetches only
   when explicitly invoked.
   ========================================================================== *)

(* ── Month names ──────────────────────────────────────────────────────────── *)
monthNames = {"January","February","March","April","May","June",
              "July","August","September","October","November","December"};

(* ── Species metadata ─────────────────────────────────────────────────────── *)
(* GBIF usageKeys: Arctic tern 5229230, Common swift 5228676, Red knot 2481765 *)

speciesColors[5229230] := RGBColor[1, 0.4, 0.25];    (* orange *)
speciesColors[5228676] := RGBColor[0.35, 0.9, 1];    (* cyan  *)
speciesColors[2481765] := RGBColor[1, 0.85, 0.25];   (* gold  *)

speciesName[5229230] := "Arctic tern";
speciesName[5228676] := "Common swift";
speciesName[2481765] := "Red knot";

(* ── Spherical centroid (ported verbatim from wolfram/load_data.wl) ───────── *)
(* Weighted spherical mean of (lat,lon) points. Returns {lat,lon} in degrees,
   or Missing["DegenerateCentroid"] when the resultant vector is ~0 (e.g.
   antipodal points cancel) -- do NOT fabricate an arithmetic-mean longitude. *)
sphericalCentroid[lats_List, lons_List, w_List] := Module[{v, m},
  v = MapThread[Function[{la, lo, wt},
        wt * {Cos[la Degree] Cos[lo Degree], Cos[la Degree] Sin[lo Degree], Sin[la Degree]}],
        {lats, lons, w}];
  m = Total[v];
  If[Norm[m] < 10^-9, Return[Missing["DegenerateCentroid"]]];
  m = m / Norm[m];
  {ArcSin[m[[3]]]/Degree, ArcTan[m[[1]], m[[2]]]/Degree}];

(* ── Data directory ───────────────────────────────────────────────────────── *)
(* Priority: explicit override > notebook context > cwd fallback. *)
BFPDataDir[] := Which[
  StringQ[$BFPDataDir],
    $BFPDataDir,
  StringQ[Quiet[NotebookDirectory[]]],
    FileNameJoin[{NotebookDirectory[], "data"}],
  True,
    Directory[]];

(* ── Centroid CSV loader ──────────────────────────────────────────────────── *)
(* Returns an N×3 numeric list {{month, lat, lon}, ...}; rows with Missing
   values (empty cells) are silently dropped, matching the notebook context
   where Missing months are simply absent from the track. *)
loadCentroidCSV[key_Integer] := Module[{f, rows},
  f = FileNameJoin[{BFPDataDir[], "centroids_" <> ToString[key] <> ".csv"}];
  If[! FileExistsQ[f],
    Message[loadCentroidCSV::nofile, f];
    Return[{}]];
  rows = Rest @ Import[f, "CSV"];   (* drop header *)
  Select[rows,
    Length[#] >= 3 &&
    NumberQ[#[[1]]] && NumberQ[#[[2]]] && NumberQ[#[[3]]] &]];

loadCentroidCSV::nofile =
  "Centroid CSV not found: `1`. Set $BFPDataDir to the folder containing centroids_<key>.csv.";

(* ── Globe visualization ──────────────────────────────────────────────────── *)
(* GeoGraphics orthographic globe (GeoBackground -> "ReliefMap") of a species'
   centroid track. Draws a colored GeoPath plus month-numbered points. *)
centroidGlobe[key_Integer] := Module[{rows, pts, col, center, path, markers},
  rows = loadCentroidCSV[key];
  If[rows === {}, Return[$Failed]];
  col   = speciesColors[key];
  pts   = {#[[2]], #[[3]]} & /@ rows;          (* {lat, lon} per month *)
  center = Mean[pts];
  path  = If[Length[pts] >= 2,
            {Directive[col, Thick],
             GeoPath[GeoPosition /@ pts]},
            Nothing];
  markers = MapThread[
    {Directive[col, PointSize[0.02]], Point[GeoPosition[#1]],
     Text[Style[ToString[Round[#2[[1]]]], 8, Black], GeoPosition[#1], {1.2, 0.}]} &,
    {pts, rows}];
  GeoGraphics[
    {path, markers},
    GeoProjection -> {"Orthographic",
                      "Centering" -> GeoPosition[center]},
    GeoBackground -> "ReliefMap",
    PlotLabel -> speciesName[key],
    ImageSize -> 500]];

(* ── Live eBird sightings ─────────────────────────────────────────────────── *)
(* Port of wolfram/ebird_live.wls. Fetches recent (last 30 days) observations
   for eBird species code `code` across a representative spread of regions.
   `token` is the caller's eBird API 2.0 key. Returns a list of {lat, lon}
   pairs rounded to 1 dp. Attribution (eBird / Cornell Lab) is the caller's
   responsibility. No network calls happen at package load time. *)
LoadLiveSightings[code_String, token_String] := Module[
    {hdr, regions, fetchRegion, allRows},
  hdr = {"X-eBirdApiToken" -> token};
  regions = {"US","CA","GB","IE","IS","NO","SE","FI","NL","FR","ES","PT","DE","DK",
             "ZA","AU","NZ","AR","CL","BR","MX","SN","MA","NA","IN","JP","RU"};
  fetchRegion[reg_] := Module[{url, resp, parsed},
    url = "https://api.ebird.org/v2/data/obs/" <> reg <> "/recent/" <> code <>
          "?back=30&maxResults=200";
    resp = Quiet @ URLRead[HTTPRequest[url, <|"Headers" -> hdr|>], "Body"];
    parsed = Quiet @ ImportString[resp, "RawJSON"];
    If[FailureQ[parsed] || ! ListQ[parsed], Return[{}]];
    Select[
      ({Round[Lookup[#, "lat", None], 0.1],
        Round[Lookup[#, "lng", None], 0.1]}) & /@ parsed,
      NumberQ[#[[1]]] && NumberQ[#[[2]]] &]];
  allRows = DeleteDuplicates[Join @@ (fetchRegion /@ regions)];
  allRows];
