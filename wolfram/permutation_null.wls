#!/usr/bin/env wolframscript
(* permutation_null.wls — is the seasonal centroid loop real, or an artifact of
   where observers happen to be? (a genuine statistical test)

   Null hypothesis: the month label carries no spatial information — the apparent
   migration is just a static, unevenly-sampled range mislabelled by month. We
   test it by PERMUTING the month labels among a species' occurrence records
   (locations preserved, month-location link broken) B times, recomputing the
   monthly centroid loop each time, and comparing the OBSERVED latitude span and
   loop length to the null distribution.

   If migration is real, the observed seasonal swing sits far in the upper tail.
   Output: docs/images/permutation_null.png, data/permutation_null.json. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];  (* sphericalCentroid *)
img = FileNameJoin[{$repoRoot, "docs", "images"}];

cols = <|5229230 -> RGBColor[1, 0.4, 0.25], 5228676 -> RGBColor[0.35, 0.9, 1.0],
         2481765 -> RGBColor[0.9, 0.7, 0.1]|>;
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
boxes = <|5228676 -> {-30, 145, -40, 75}, 2481765 -> {-110, -30, -56, 85},
          5229230 -> {-80, 20, -90, 90}|>;
keys = {5229230, 5228676, 2481765};
B = 500; capN = 60000; SeedRandom[11];

(* monthly centroids from a list of {month, cellId, {lat,lon}} cell records:
   per month, the occupied cells -> presence-weighted (=1) spherical centroid *)
monthlyLatSpan[recs_] := Module[{byMonth, cents},
  byMonth = GroupBy[recs, First];
  cents = Table[
    If[KeyExistsQ[byMonth, m],
      With[{cells = DeleteDuplicatesBy[byMonth[m], #[[2]] &]},
        First @ sphericalCentroid[cells[[All, 3, 1]], cells[[All, 3, 2]],
           ConstantArray[1., Length[cells]]]],
      Missing[]],
    {m, 12}];
  cents = DeleteMissing[cents];
  If[Length[cents] < 2, 0., Max[cents] - Min[cents]]];   (* latitude span (deg) *)

test[key_] := Module[{o, box, idx, lat, lon, mon, cellId, recs, obs, nulls, p},
  o = loadOccurrences[key, "full"];
  box = boxes[key];
  idx = Select[Range[Length[o["lat"]]],
     box[[1]] <= o["lon"][[#]] <= box[[2]] && box[[3]] <= o["lat"][[#]] <= box[[4]] &];
  If[Length[idx] > capN, idx = RandomSample[idx, capN]];
  lat = o["lat"][[idx]]; lon = o["lon"][[idx]]; mon = o["month"][[idx]];
  cellId = Transpose[{Round[lat/2], Round[lon/2]}];
  recs = Transpose[{mon, cellId, Transpose[{lat, lon}]}];
  obs = monthlyLatSpan[recs];
  nulls = Table[
    monthlyLatSpan[Transpose[{RandomSample[mon], cellId, Transpose[{lat, lon}]}]],
    {B}];
  p = N[(1 + Count[nulls, n_ /; n >= obs])/(B + 1)];     (* one-sided, +1 smoothing *)
  <|"species" -> names[key], "obsLatSpanDeg" -> Round[obs, 0.1],
    "nullMeanDeg" -> Round[Mean[nulls], 0.1], "nullMaxDeg" -> Round[Max[nulls], 0.1],
    "p" -> p, "nRecords" -> Length[idx], "nulls" -> nulls|>];
R = Association[# -> test[#] & /@ keys];

panel[key_] := Histogram[R[key]["nulls"], 24,
   ChartStyle -> Directive[GrayLevel[0.7], Opacity[0.7]],
   Frame -> True, FrameLabel -> {"latitude span under shuffled months (\[Degree])", "count"},
   PlotLabel -> Style[names[key] <> "  (observed " <> ToString[R[key]["obsLatSpanDeg"]] <>
      "\[Degree], p<" <> ToString[Ceiling[R[key]["p"], 0.001]] <> ")", 12],
   PlotRange -> {{0, 1.05 Max[R[key]["obsLatSpanDeg"], Max[R[key]["nulls"]]]}, Automatic},
   ImageSize -> 320,
   Epilog -> {cols[key], Thickness[0.012],
      Line[{{R[key]["obsLatSpanDeg"], 0}, {R[key]["obsLatSpanDeg"], 1*^9}}],
      Text[Style["observed", cols[key], 10, Bold],
         {R[key]["obsLatSpanDeg"], 0}, {1.1, -1.5}]}];
Export[FileNameJoin[{img, "permutation_null.png"}], Row[panel /@ keys, Spacer[6]],
   "PNG", ImageResolution -> 130];
Print["wrote permutation_null.png"];

Export[FileNameJoin[{$repoRoot, "data", "permutation_null.json"}],
   KeyDrop[#, "nulls"] & /@ Values[R], "RawJSON"];
Do[Print["  ", R[k]["species"], ": observed span ", R[k]["obsLatSpanDeg"],
   "\[Degree]; null mean ", R[k]["nullMeanDeg"], "\[Degree] (max ", R[k]["nullMaxDeg"],
   "\[Degree]); p=", R[k]["p"], " (n=", R[k]["nRecords"], ")"], {k, keys}];
Print["permutation_null: OK"];
