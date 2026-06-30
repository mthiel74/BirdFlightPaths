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
    Module[{yc, ycU, years, cents},
      yc = Lookup[bmy, m, <||>];                          (* year -> cell records *)
      years = Keys[yc];
      ycU = DeleteDuplicates /@ yc;                        (* year -> unique occupied cells *)
      If[Length[years] < 2, Nothing,
        cents = Table[
          Module[{samp = RandomChoice[years, Length[years]], cnt, uc, c},
            (* true block bootstrap: a year drawn twice counts its cells twice.
               Done efficiently by weighting unique cells by resample multiplicity
               (Counts) instead of materialising duplicated cell lists. *)
            cnt = Counts[Join @@ (ycU /@ samp)];
            uc = Keys[cnt];
            c = sphericalCentroid[uc[[All, 1]], uc[[All, 2]], N@Values[cnt]];
            If[Head[c] === List, c, Nothing]],
          {B}];
        {m, ellipse[cents], Mean[cents]}]],
    {m, 12}];
  DeleteCases[res, Nothing]];

bootAll = Association[# -> boot[#] & /@ keys];

(* crop the map to the data (centroids + halo points), so there is no empty
   ocean padding; each species is exported as its OWN compact figure so notebook
   page breaks fall between figures, never through a panel (a brutal-critic fix). *)
panel[key_] := Module[{data = bootAll[key], pts, las, los, latR, lonR},
  pts = Join[#[[2, 1]] & /@ data, Join @@ (#[[2, 2]] & /@ data)];
  las = pts[[All, 1]]; los = pts[[All, 2]];
  latR = {Max[-90, Min[las] - 6], Min[90, Max[las] + 6]};
  lonR = {Max[-180, Min[los] - 6], Min[180, Max[los] + 6]};
  GeoGraphics[
    {Flatten@Table[
       With[{m = d[[1]], ell = d[[2, 2]], ctr = d[[2, 1]]},
        {If[ell === {}, {},
           {cols[key], Opacity[0.18], EdgeForm[{cols[key], Opacity[0.5]}],
            GeoPolygon[GeoPosition /@ ell]}],
         {cols[key], Opacity[0.9], PointSize[0.012], Point[GeoPosition[ctr]]},
         Text[Style[ToString[m], 8, White, Bold], GeoPosition[ctr]]}],
       {d, data}],
     {cols[key], Opacity[0.5], Thickness[0.003],
      GeoPath[GeoPosition /@ (#[[3]] & /@ data)]}},
    GeoRange -> {latR, lonR},
    GeoProjection -> "Robinson", GeoBackground -> Automatic,
    PlotLabel -> Style[names[key] <> " \[LongDash] monthly centroid \[PlusMinus] 95% (year bootstrap)", 12],
    ImageSize -> 560]];
Do[Export[FileNameJoin[{img, "bootstrap_halos_" <> ToString[key] <> ".png"}],
     panel[key], "PNG", ImageResolution -> 120, Background -> White];
   Print["wrote bootstrap_halos_", key, ".png"], {key, keys}];

(* json: per species per month the MEAN 95%-ellipse RADIUS in degrees
   (mean centre-to-boundary distance; lat/lon degrees combined) *)
spanOf[d_] := If[d[[2, 2]] === {}, 0.,
   Round[Mean[(EuclideanDistance[d[[2, 1]], #] &) /@ d[[2, 2]]], 0.1]];
summ[key_] := <|"species" -> names[key],
   "months" -> (#[[1]] & /@ bootAll[key]),
   "ellipseRadiusDeg" -> (spanOf /@ bootAll[key])|>;
Export[FileNameJoin[{$repoRoot, "data", "bootstrap_halos.json"}], summ /@ keys, "RawJSON"];
Do[Print["  ", names[k], ": ", Length[bootAll[k]], " months with halos"], {k, keys}];
Print["bootstrap_halos: OK"];
