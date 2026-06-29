#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
src = If[Length[$ScriptCommandLine] > 1, $ScriptCommandLine[[2]], "sample"];

writeCentroids[file_, cs_] := Export[
  FileNameJoin[{$repoRoot, "data", file}],
  Prepend[cs, {"month", "lat", "lon"}], "CSV"];

(* Common swift (5228676): one coherent Afro-Palearctic flyway; drop New-World
   vagrants. PRIMARY track. *)
swift = monthlyCentroids[5228676, src, <|"lon" -> {-30, 145}, "lat" -> {-40, 75}|>];
writeCentroids["centroids_5228676.csv", swift];

(* Red knot (2481765): PRIMARY = Americas flyway (rufa/roselaari). *)
knot = monthlyCentroids[2481765, src, <|"lon" -> {-110, -30}, "lat" -> {-56, 85}|>];
writeCentroids["centroids_2481765.csv", knot];

(* Red knot: broken GLOBAL version (no filter) -- teaching contrast only. *)
knotG = monthlyCentroids[2481765, src, All];
writeCentroids["centroids_2481765_global.csv", knotG];

(* Arctic tern (5229230): PRIMARY = Atlantic-basin centroid (clean pole-to-pole
   map). *)
tern = monthlyCentroids[5229230, src, <|"lon" -> {-80, 20}, "lat" -> {-90, 90}|>];
writeCentroids["centroids_5229230.csv", tern];

(* Arctic tern: global latitude-vs-month curve -- the true N-S signal. *)
ternLat = latitudeByMonth[5229230, src];
Export[FileNameJoin[{$repoRoot, "data", "latitude_5229230.csv"}],
  Prepend[ternLat, {"month", "lat"}], "CSV"];

(* Path lengths over observed edges only. *)
mkRow[key_, common_, track_, cs_] := Module[{p = centroidPathLengthKm[cs]},
  {key, common, track, p["km"], p["edges"], p["maxEdgeKm"]}];
header = {"key", "common", "track", "km", "edges", "maxEdgeKm"};
rows = {
  mkRow[5228676, "Common swift", "Afro-Palearctic", swift],
  mkRow[2481765, "Red knot", "Americas", knot],
  mkRow[2481765, "Red knot", "global-BROKEN", knotG],
  mkRow[5229230, "Arctic tern", "Atlantic", tern]
};
Export[FileNameJoin[{$repoRoot, "data", "path_lengths.csv"}],
  Prepend[rows, header], "CSV"];
Print["path_lengths.csv:"];
Print[TableForm[rows, TableHeadings -> {None, header}]];
