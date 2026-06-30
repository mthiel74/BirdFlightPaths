#!/usr/bin/env wolframscript
(* bootstrap_halos.wls — how well-pinned is each monthly centroid?

   The monthly centroids are point estimates from finite, uneven samples. We put
   error bars on them by BLOCK BOOTSTRAP over years: for each month, resample the
   available years (2014-2024) with replacement, recompute the gridded spherical
   centroid from the occupied 2-degree cells of those years, repeat B times, and
   draw the 95% confidence ellipse of the resulting centroid cloud. Tight halos =
   well-constrained months; big halos = sparse, oceanic, poorly-sampled months.

   Output: docs/images/bootstrap_halos.png, data/bootstrap_halos.json. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];   (* sphericalCentroid *)
img = FileNameJoin[{$repoRoot, "docs", "images"}];
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
cols = <|5229230 -> RGBColor[1, 0.4, 0.25], 5228676 -> RGBColor[0.2, 0.55, 0.95],
         2481765 -> RGBColor[0.9, 0.7, 0.1]|>;
boxes = <|5228676 -> {-30, 145, -40, 75}, 2481765 -> {-110, -30, -56, 85},
          5229230 -> {-80, 20, -90, 90}|>;
keys = {5229230, 5228676, 2481765};
B = 300; SeedRandom[23];

(* per species: month -> (year -> list of occupied cell-centres {lat,lon}) *)
cellsByMonthYear[key_] := Module[{o, box, idx},
  o = loadOccurrences[key, "full"]; box = boxes[key];
  idx = Select[Range[Length[o["lat"]]],
     box[[1]] <= o["lon"][[#]] <= box[[2]] && box[[3]] <= o["lat"][[#]] <= box[[4]] &];
  GroupBy[
    Transpose[{o["month"][[idx]], o["year"][[idx]],
       2 Round[o["lat"][[idx]]/2], 2 Round[o["lon"][[idx]]/2]}],
    First,                                                (* month -> rows {m,y,clat,clon} *)
    GroupBy[#, (#[[2]] &) -> (#[[3 ;; 4]] &)] &]];        (* within month: year -> {{clat,clon}..} *)

(* 95% covariance ellipse (lat/lon) of a cloud of {lat,lon} points *)
ellipse[cloud_] := Module[{m, cov, ev, axes, t},
  m = Mean[cloud];
  cov = Covariance[cloud];
  If[! MatrixQ[cov] || Min[Eigenvalues[cov]] <= 0, Return[{m, {}}]];
  {ev, axes} = {Sqrt[Eigenvalues[cov]], Transpose[Eigenvectors[cov]]};
  (* 95% for 2 dof: scale 2.448 *)
  {m, Table[m + 2.448 axes.(ev {Cos[t], Sin[t]}), {t, 0, 2 Pi, 2 Pi/40}]}];

boot[key_] := Module[{bmy = cellsByMonthYear[key], res},
  res = Table[
    Module[{yc, years, cents},
      yc = Lookup[bmy, m, <||>];                          (* year -> cells *)
      years = Keys[yc];
      If[Length[years] < 2, Nothing,
        cents = Table[
          Module[{samp = RandomChoice[years, Length[years]], cells, c},
            cells = DeleteDuplicates[Join @@ (yc /@ samp)];
            c = sphericalCentroid[cells[[All, 1]], cells[[All, 2]], ConstantArray[1., Length[cells]]];
            If[Head[c] === List, c, Nothing]],
          {B}];
        {m, ellipse[cents], Mean[cents]}]],
    {m, 12}];
  DeleteCases[res, Nothing]];

bootAll = Association[# -> boot[#] & /@ keys];

panel[key_] := Module[{bx = boxes[key], data = bootAll[key]},
  GeoGraphics[
    {Flatten@Table[
       With[{m = d[[1]], ell = d[[2, 2]], ctr = d[[2, 1]]},
        {(* 95% halo *)
         If[ell === {}, {},
           {cols[key], Opacity[0.18], EdgeForm[{cols[key], Opacity[0.5]}],
            GeoPolygon[GeoPosition /@ ell]}],
         {cols[key], Opacity[0.9], PointSize[0.012], Point[GeoPosition[ctr]]},
         Text[Style[ToString[m], 8, White, Bold], GeoPosition[ctr]]}],
       {d, data}],
     {cols[key], Opacity[0.5], Thickness[0.003],
      GeoPath[GeoPosition /@ (#[[3]] & /@ data)]}},
    GeoRange -> {{bx[[3]], bx[[4]]}, {bx[[1]], bx[[2]]}},
    GeoProjection -> "Robinson", GeoBackground -> Automatic,
    PlotLabel -> Style[names[key] <> " \[LongDash] monthly centroid \[PlusMinus] 95% (year bootstrap)", 12],
    ImageSize -> 620]];
(* stack vertically: the three per-flyway globes have very different aspect
   ratios, so a Row overlaps them; a Column lays them out cleanly. *)
Export[FileNameJoin[{img, "bootstrap_halos.png"}], Column[panel /@ keys, Spacings -> 1.5, Alignment -> Center],
   "PNG", ImageResolution -> 110, Background -> White];
Print["wrote bootstrap_halos.png"];

(* json: per species per month the 95% ellipse "radius" (mean axis, km-ish via deg) *)
spanOf[d_] := If[d[[2, 2]] === {}, 0.,
   Round[Mean[(EuclideanDistance[d[[2, 1]], #] &) /@ d[[2, 2]]], 0.1]];
summ[key_] := <|"species" -> names[key],
   "months" -> (#[[1]] & /@ bootAll[key]),
   "ellipseSpanDeg" -> (spanOf /@ bootAll[key])|>;
Export[FileNameJoin[{$repoRoot, "data", "bootstrap_halos.json"}], summ /@ keys, "RawJSON"];
Do[Print["  ", names[k], ": ", Length[bootAll[k]], " months with halos"], {k, keys}];
Print["bootstrap_halos: OK"];
