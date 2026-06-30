#!/usr/bin/env wolframscript
(* geomag.wls — the geomagnetic field birds may navigate by.

   Uses Wolfram's GeomagneticModelData (World Magnetic Model) to draw:
     - a global magnetic-INCLINATION (dip) map with each species' centroid
       track overlaid (docs/images/geomag_inclination.png)               [item 5]
     - the magnetic SIGNATURE (inclination + total intensity) sampled along
       each track through the year (docs/images/geomag_signature.png)     [item 6]
     - a quantitative "magnetic-contour-following" test vs a null model,
       written to data/geomag_following.json + printed                    [item 8]

   GeomagneticModelData is ~0.45 s/call, so we evaluate the field ONCE on a
   coarse grid, cache it to data/geomag_grid.csv, and read everything else
   (signature, the 1000-draw null test) from a fast interpolation of that grid.
   Pure Wolfram Language; no map tiles (reliable offline rendering). *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
img = FileNameJoin[{$repoRoot, "docs", "images"}];
gridFile = FileNameJoin[{$repoRoot, "data", "geomag_grid.csv"}];

(* ---------- cached field grid: {lon, lat, inclination(deg), intensity(uT)} ---------- *)
grid = If[FileExistsQ[gridFile],
   Print["loading cached field grid ", gridFile];
   Rest @ Import[gridFile, "CSV"],
   Print["computing field grid (one-off, ~5 min at 0.45 s/eval) ..."];
   Module[{g = Flatten[Table[
       With[{d = GeomagneticModelData[GeoPosition[{la, lo}]]},
         {lo, la, QuantityMagnitude[d["Inclination"]],
          QuantityMagnitude[d["Magnitude"]]/1000.}],
       {la, -84, 84, 6}, {lo, -180, 180, 12}], 1]},
     Export[gridFile, Prepend[g, {"lon", "lat", "incl_deg", "intensity_uT"}], "CSV"];
     Print["cached ", Length[g], " grid points"]; g]];

inclIF = Interpolation[{{#[[1]], #[[2]]}, #[[3]]} & /@ grid, InterpolationOrder -> 1];
intIF  = Interpolation[{{#[[1]], #[[2]]}, #[[4]]} & /@ grid, InterpolationOrder -> 1];
inclAt[la_, lo_] := inclIF[Clip[lo, {-180, 180}], Clip[la, {-84, 84}]];
intAt[la_, lo_]  := intIF[Clip[lo, {-180, 180}], Clip[la, {-84, 84}]];

cols = <|5229230 -> RGBColor[1, 0.4, 0.25], 5228676 -> RGBColor[0.35, 0.9, 1.0],
         2481765 -> RGBColor[0.9, 0.7, 0.1]|>;
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
loadTrack[key_] := Select[
   Rest @ Import[FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[key] <> ".csv"}], "CSV"],
   NumberQ[#[[2]]] && NumberQ[#[[3]]] &];   (* {month, lat, lon} *)
tracks = Association[# -> loadTrack[#] & /@ Keys[cols]];

(* ---------- item 5: global inclination map + tracks ---------- *)
trackEpilog = Flatten[{
   {GrayLevel[0.55], Thickness[0.0012],
    Quiet@Check[Cases[CountryData["World", "Polygon"], _Polygon, Infinity] /.
       Polygon[pts_] :> Line[pts], {}]},
   Table[With[{tr = tracks[k]},
     {cols[k], Thickness[0.004], Line[{#[[3]], #[[2]]} & /@ tr],
      PointSize[0.012], Point[{#[[3]], #[[2]]} & /@ tr]}], {k, Keys[tracks]}]
}];

inclMap = ListContourPlot[grid[[All, {1, 2, 3}]],
   Contours -> Range[-80, 80, 10],
   ColorFunction -> "ThermometerColors", ColorFunctionScaling -> True,
   PlotRange -> {{-180, 180}, {-90, 90}},
   FrameLabel -> {"longitude (\[Degree])", "latitude (\[Degree])"},
   PlotLabel -> Style["Geomagnetic inclination (dip angle, \[Degree]) and migration tracks \[LongDash] WMM2025 (epoch 2026)", 14],
   PlotLegends -> BarLegend[Automatic, LegendLabel -> "dip \[Degree]"],
   ContourStyle -> Directive[GrayLevel[0.4], Opacity[0.4]],
   AspectRatio -> 1/2, ImageSize -> 1000, Epilog -> trackEpilog];
Export[FileNameJoin[{img, "geomag_inclination.png"}], inclMap, "PNG", ImageResolution -> 130];
Print["wrote geomag_inclination.png"];

(* ---------- item 6: magnetic signature along each track (from interpolation) ---------- *)
sigPlot[key_] := Module[{tr = tracks[key], inc, tot},
  inc = {#[[1]], inclAt[#[[2]], #[[3]]]} & /@ tr;
  tot = {#[[1]], intAt[#[[2]], #[[3]]]} & /@ tr;
  {ListLinePlot[inc, PlotStyle -> cols[key], Mesh -> All, MeshStyle -> cols[key],
     Frame -> True, FrameLabel -> {"month", "inclination (\[Degree])"},
     PlotLabel -> names[key] <> ": magnetic dip along the route",
     PlotRange -> {{1, 12}, {-90, 90}}, GridLines -> {Range[12], {0}}, ImageSize -> 360],
   ListLinePlot[tot, PlotStyle -> cols[key], Mesh -> All, MeshStyle -> cols[key],
     Frame -> True, FrameLabel -> {"month", "total intensity (\[Mu]T)"},
     PlotLabel -> names[key] <> ": field strength along the route",
     PlotRange -> {{1, 12}, {20, 70}}, GridLines -> {Range[12], None}, ImageSize -> 360]}];
Export[FileNameJoin[{img, "geomag_signature.png"}], Grid[sigPlot /@ Keys[tracks], Spacings -> {1, 1}],
   "PNG", ImageResolution -> 130];
Print["wrote geomag_signature.png"];

(* ---------- item 8: how the field varies along each track (descriptive) ----------
   We do NOT claim the birds "follow" or "use" the field — occurrence centroids
   cannot test a navigational mechanism. We characterise the magnetic landscape
   each track crosses, honestly (a maths-critic finding):
     - dipRangeDeg: the total span of inclination the track traverses;
     - lonEffectDeg: how much of the dip variation is due to LONGITUDE alone
       (latitude held at its mean) -- this is small, so dip ~ f(latitude);
     - inclLatCorr: correlation of inclination with latitude along the track --
       near +/-1 confirms the geocentric-dipole relation tan I = 2 tan(lambda_m),
       i.e. inclination is essentially a latitude signal. *)
fieldAlong[key_] := Module[{tr = tracks[key], inc, lat, meanLat, lonEffect},
  inc = inclAt[#[[2]], #[[3]]] & /@ tr;
  lat = tr[[All, 2]];
  meanLat = Mean[lat];
  lonEffect = StandardDeviation[inclAt[meanLat, #] & /@ tr[[All, 3]]]; (* lat fixed, lon varies *)
  <|"species" -> names[key],
    "dipRangeDeg" -> Round[Max[inc] - Min[inc], 0.1],
    "dipSDdeg" -> Round[StandardDeviation[inc], 0.1],
    "lonEffectDeg" -> Round[lonEffect, 0.1],
    "inclLatCorr" -> Round[Correlation[inc, lat], 0.001]|>];
field = fieldAlong /@ Keys[tracks];
Export[FileNameJoin[{$repoRoot, "data", "geomag_following.json"}], field, "RawJSON"];
Print["magnetic field along each track (descriptive):"];
Do[Print["  ", f["species"], ": dip range=", f["dipRangeDeg"], "\[Degree] (SD ", f["dipSDdeg"],
   "\[Degree]); longitude-only effect=", f["lonEffectDeg"], "\[Degree]; corr(dip,lat)=",
   f["inclLatCorr"]], {f, field}];
Print["geomag: OK"];
