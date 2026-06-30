#!/usr/bin/env wolframscript
(* compare.wls — cross-species synthesis figures.

   item 17: a comparison "scorecard" of the three migrants on common axes
            (distance, speed, latitude span, energy, fuel).
   item 18: per-species annual-profile small-multiples — latitude, centroid
            speed, day length, and magnetic dip vs month on shared axes.

   Reads existing outputs (journey_metrics.json, energetics.json, the centroid
   CSVs, and the cached geomag grid). Output: docs/images/comparison.png,
   docs/images/annual_profiles.png. Pure Wolfram Language. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
img = FileNameJoin[{$repoRoot, "data"}]; (* reuse var name below *)
imgD = FileNameJoin[{$repoRoot, "docs", "images"}];
dataD = FileNameJoin[{$repoRoot, "data"}];

cols = <|5229230 -> RGBColor[1, 0.45, 0.25], 5228676 -> RGBColor[0.35, 0.9, 1.0],
         2481765 -> RGBColor[1, 0.82, 0.2]|>;
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
keys = {5229230, 5228676, 2481765};

jm = Association[(#["key"]) -> # & /@ Import[FileNameJoin[{dataD, "journey_metrics.json"}], "RawJSON"]];
en = Import[FileNameJoin[{dataD, "energetics.json"}], "RawJSON"];   (* list, same order as keys *)
enr = Association[MapThread[#1 -> #2 &, {keys, en}]];
loadTrack[key_] := Select[Rest@Import[FileNameJoin[{dataD,
   "centroids_" <> ToString[key] <> ".csv"}], "CSV"], NumberQ[#[[2]]] && NumberQ[#[[3]]] &];
tracks = Association[# -> loadTrack[#] & /@ keys];

(* inclination interpolation from the cached grid *)
grid = Rest@Import[FileNameJoin[{dataD, "geomag_grid.csv"}], "CSV"];
inclIF = Interpolation[{{#[[1]], #[[2]]}, #[[3]]} & /@ grid, InterpolationOrder -> 1];
inclAt[la_, lo_] := inclIF[Clip[lo, {-180, 180}], Clip[la, {-84, 84}]];

(* ---------- item 17: comparison scorecard ---------- *)
latSpan[key_] := Round[Max[tracks[key][[All, 2]]] - Min[tracks[key][[All, 2]]]];
rows = {{"", "Arctic tern", "Common swift", "Red knot"},
   {"flyway", "Atlantic basin", "Afro-Palearctic", "Americas"},
   {"body mass (g)", 110, 40, 135},
   {"annual centroid path (km)", Sequence @@ (enr[#]["annualCentroidKm"] & /@ keys)},
   {"mean centroid speed (km/day)", Sequence @@ (jm[#]["meanSpeedKmDay"] & /@ keys)},
   {"peak centroid speed (km/day)", Sequence @@ (jm[#]["maxSpeedKmDay"] & /@ keys)},
   {"latitude span (\[Degree])", Sequence @@ (latSpan /@ keys)},
   {"min-power airspeed (km/h)", Sequence @@ (enr[#]["VmpKmh"] & /@ keys)},
   {"cost of transport (kJ/km)", Sequence @@ (enr[#]["COTkJkm"] & /@ keys)},
   {"fat burned /1000 km (%)", Sequence @@ (Round[100 enr[#]["fatFracPer1000km"]] & /@ keys)}};
With[{vf = FileNameJoin[{dataD, "raw", "ebirdst", "validation.json"}]},
  If[FileExistsQ[vf],
    Module[{vv = Import[vf, "RawJSON"]},
      rows = Append[rows, {"GBIF vs S&T centroid (km)",
         Sequence @@ (Round[Lookup[Lookup[vv, ToString[#], <||>], "meanSepKm", 0]] & /@ keys)}]]]];
scorecard = Grid[rows,
   Background -> {None, {RGBColor[0.85, 0.9, 0.97]}}, Frame -> All,
   FrameStyle -> GrayLevel[0.8], Alignment -> {{Left, Center, Center, Center}},
   Spacings -> {1.5, 1}, ItemStyle -> 11,
   Dividers -> {{2 -> GrayLevel[0.5]}, {2 -> GrayLevel[0.5]}}];
Export[FileNameJoin[{imgD, "comparison.png"}],
   Framed[scorecard, FrameStyle -> None, Background -> White, FrameMargins -> 18],
   "PNG", ImageResolution -> 140];
Print["wrote comparison.png"];

(* ---------- item 18: per-species annual profiles ---------- *)
profileRow[key_] := Module[{tr = tracks[key], c = cols[key], lat, spd, day, inc, mk},
  lat = Transpose[{tr[[All, 1]], tr[[All, 2]]}];
  spd = Transpose[{Range[12], jm[key]["speeds"]}];
  day = Transpose[{Range[12], jm[key]["daylightHrs"]}];
  inc = Table[{m, inclAt[tr[[m, 2]], tr[[m, 3]]]}, {m, 12}];
  mk[data_, lab_, rng_] := ListLinePlot[data, PlotStyle -> c, Mesh -> All, MeshStyle -> c,
     Frame -> True, FrameLabel -> {None, lab}, PlotRange -> {{1, 12}, rng},
     GridLines -> {Range[2, 12, 2], None}, ImageSize -> 250, AspectRatio -> 0.7,
     PlotLabel -> Style[names[key], c, 11]];
  {mk[lat, "latitude \[Degree]", {-60, 85}], mk[spd, "speed km/day", {0, All}],
   mk[day, "daylight h", {0, 24}], mk[inc, "mag. dip \[Degree]", {-90, 90}]}];
profiles = Grid[profileRow /@ keys, Spacings -> {0.5, 0.6}];
Export[FileNameJoin[{imgD, "annual_profiles.png"}], profiles, "PNG", ImageResolution -> 130];
Print["wrote annual_profiles.png"];
Print["compare: OK"];
