#!/usr/bin/env wolframscript
(* journey_metrics.wls — speed, stopovers, daylight, and a photoperiod test.

   From each species' monthly centroid track (data/centroids_<key>.csv):
     - centroid ground speed (km/day) month-to-month                     [item 13]
     - stopover detection: months of unusually low displacement          [item 14]
     - daylight hours experienced along the route (pole-safe formula)    [item 9]
     - testable idea #2: correlation between centroid speed and the
       rate of change of day length along the track                      [item 15]

   Outputs: docs/images/speed_profile.png, docs/images/daylight.png,
            data/journey_metrics.json. Pure Wolfram Language. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
img = FileNameJoin[{$repoRoot, "docs", "images"}];

cols = <|5229230 -> RGBColor[1, 0.4, 0.25], 5228676 -> RGBColor[0.35, 0.9, 1.0],
         2481765 -> RGBColor[0.9, 0.7, 0.1]|>;
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
keys = {5229230, 5228676, 2481765};
loadTrack[key_] := Select[
   Rest @ Import[FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[key] <> ".csv"}], "CSV"],
   NumberQ[#[[2]]] && NumberQ[#[[3]]] &];
tracks = Association[# -> loadTrack[#] & /@ keys];

(* representative day-of-year for the middle of calendar month m *)
midDOY[m_] := Floor[(m - 0.5) * 365/12];
(* daylight hours from latitude + solar declination (pole-safe, fast) *)
daylightHours[lat_, m_] := Module[{decl, cosH0},
  decl = 23.44 * Sin[360. (284 + midDOY[m])/365 Degree];
  cosH0 = -Tan[lat Degree] Tan[decl Degree];
  Which[cosH0 <= -1, 24., cosH0 >= 1, 0., True, 2. ArcCos[cosH0]/Degree/15.]];

(* km between consecutive monthly centroids -> speed km/day (closed 12-month loop) *)
daysPerMonth = 365./12.;
monthlyStep[tr_] := Table[
   QuantityMagnitude@UnitConvert[
     GeoDistance[{tr[[i, 2]], tr[[i, 3]]}, {tr[[Mod[i, 12] + 1, 2]], tr[[Mod[i, 12] + 1, 3]]}],
     "Kilometers"], {i, 12}];

metric[key_] := Module[{tr = tracks[key], steps, speeds, dl, dlChange, loThresh, loMonths, r, permR, pCyc},
  steps = monthlyStep[tr];                              (* km, step from month i to i+1 *)
  speeds = steps/daysPerMonth;                          (* km/day *)
  dl = daylightHours[tr[[#, 2]], tr[[#, 1]]] & /@ Range[12];      (* hours, per month *)
  dlChange = Table[Abs[dl[[Mod[i, 12] + 1]] - dl[[i]]], {i, 12}]; (* |Δ daylight| per step *)
  loThresh = 0.4 Mean[speeds];                          (* "slow" = < 40% of mean speed *)
  loMonths = Select[Range[12], speeds[[#]] < loThresh &];
  r = If[Variance[speeds] > 0 && Variance[dlChange] > 0, Correlation[speeds, dlChange], 0.];
  (* cyclic-permutation p-value: respects the annual autocorrelation (n=12 is small,
     and both series share a seasonal cycle, so a naive Pearson p is meaningless).
     Null = all 12 cyclic rotations of |Δdaylight| against speed. *)
  permR = Table[Correlation[speeds, RotateRight[dlChange, s]], {s, 0, 11}];
  pCyc = N@Mean[Boole[Abs[#] >= Abs[r] & /@ permR]];
  <|"species" -> names[key], "key" -> key,
    "meanSpeedKmDay" -> Round[Mean[speeds], 0.1], "maxSpeedKmDay" -> Round[Max[speeds], 0.1],
    "speeds" -> Round[speeds, 0.1], "daylightHrs" -> Round[dl, 0.1],
    "lowDisplacementMonths" -> loMonths, "speedDaylightR" -> Round[r, 0.01],
    "speedDaylightPcyclic" -> Round[pCyc, 0.001]|>];
M = Association[# -> metric[#] & /@ keys];

(* ---------- item 13/14: speed profile + stopovers ---------- *)
speedFig = ListLinePlot[
   Table[Transpose[{Range[12], M[k]["speeds"]}], {k, keys}],
   PlotStyle -> (cols /@ keys), Mesh -> All, PlotLegends -> (names /@ keys),
   Frame -> True, FrameLabel -> {"month", "centroid speed (km/day)"},
   PlotLabel -> Style["Population-centroid speed along the year (low months = stopover/turn-around)", 13],
   GridLines -> {Range[12], Automatic}, PlotRange -> {{1, 12}, {0, All}}, ImageSize -> 900,
   Epilog -> Flatten@Table[With[{sp = M[k]["speeds"]},
      {cols[k], PointSize[0.02], Opacity[0.5],
       Point[{#, sp[[#]]}] & /@ M[k]["lowDisplacementMonths"]}], {k, keys}]];
Export[FileNameJoin[{img, "speed_profile.png"}], speedFig, "PNG", ImageResolution -> 130];
Print["wrote speed_profile.png"];

(* ---------- item 9: daylight along the route ---------- *)
dayFig = ListLinePlot[
   Table[Transpose[{Range[12], M[k]["daylightHrs"]}], {k, keys}],
   PlotStyle -> (cols /@ keys), Mesh -> All, PlotLegends -> (names /@ keys),
   Frame -> True, FrameLabel -> {"month", "day length at the centroid (hours)"},
   PlotLabel -> Style["Daylight the population experiences along the route", 13],
   GridLines -> {Range[12], {12, 24}}, PlotRange -> {{1, 12}, {0, 24}}, ImageSize -> 900];
Export[FileNameJoin[{img, "daylight.png"}], dayFig, "PNG", ImageResolution -> 130];
Print["wrote daylight.png"];

Export[FileNameJoin[{$repoRoot, "data", "journey_metrics.json"}], Values[M], "RawJSON"];
Do[Print["  ", M[k]["species"], ": mean ", M[k]["meanSpeedKmDay"], " km/day, max ",
   M[k]["maxSpeedKmDay"], ", stopover months ", M[k]["lowDisplacementMonths"],
   ", speed~|Δdaylight| r=", M[k]["speedDaylightR"]], {k, keys}];
Print["journey_metrics: OK"];
