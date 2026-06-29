(* ::Package:: *)

(* --- Spherical centroid helpers ------------------------------------------ *)

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

(* Coarse 2-degree lat/lon effort mitigation (NOT equal-area: cells shrink
   ~ cos(lat)). Each occupied cell contributes PRESENCE weight 1.0 -- this is
   what damps observer-effort bias; summing individualCount lets hotspots
   dominate and defeats the gridding. Returns {meanLat, meanLon, 1.0} per
   occupied cell. cnt is retained in the signature but intentionally unused. *)
gridCells[lat_, lon_, cnt_] := Module[{g},
  g = GroupBy[Transpose[{lat, lon}], {Round[#[[1]]/2], Round[#[[2]]/2]} &];
  KeyValueMap[Function[{k, rows},
     {Mean[rows[[All, 1]]], Mean[rows[[All, 2]]], 1.0}], g]];

(* Filter an occurrence association to a lon/lat box (all 5 lists kept
   consistent). box is All (returns o unchanged) or
   <|"lon"->{lo,hi}, "lat"->{lo,hi}|>. *)
regionFilter[o_Association, box_] := If[box === All, o,
  Module[{lon = box["lon"], lat = box["lat"], mask, pick},
    mask = MapThread[
      (lon[[1]] <= #2 <= lon[[2]] && lat[[1]] <= #1 <= lat[[2]]) &,
      {o["lat"], o["lon"]}];
    pick = Pick[#, mask] &;
    <|"lat" -> pick[o["lat"]], "lon" -> pick[o["lon"]],
      "month" -> pick[o["month"]], "year" -> pick[o["year"]],
      "count" -> pick[o["count"]]|>]];

(* 12 monthly centroids for one species, optionally restricted to a region box.
   Returns a 12x3 list {{month, lat, lon}, ...}; empty or degenerate months stay
   Missing (no imputation from the annual mean). Writes NO file -- the driver
   names and writes the CSVs. *)
monthlyCentroids[key_Integer, source_:"sample", box_:All] := Module[{o},
  o = regionFilter[loadOccurrences[key, source], box];
  Table[
    Module[{idx = Flatten@Position[o["month"], m], cells, c},
      If[idx === {},
        {m, Missing["NoData"], Missing["NoData"]},
        cells = gridCells[o["lat"][[idx]], o["lon"][[idx]], o["count"][[idx]]];
        c = sphericalCentroid[cells[[All, 1]], cells[[All, 2]], cells[[All, 3]]];
        If[MissingQ[c],
          {m, Missing["DegenerateCentroid"], Missing["DegenerateCentroid"]},
          {m, c[[1]], c[[2]]}]]],
    {m, 12}]];

(* Great-circle path length around the 12-month loop, OBSERVED EDGES ONLY: an
   edge (month i -> i+1, wrapping 12->1) counts only if BOTH endpoints are
   present. GeoDistance defaults to Miles here, so convert to km. Returns
   <|"km"->total, "edges"->count, "maxEdgeKm"->largest single edge|>. *)
centroidPathLengthKm[cs_List] := Module[{edges, dists},
  edges = Table[{cs[[i]], cs[[Mod[i, 12] + 1]]}, {i, 12}];
  dists = Cases[edges,
    {{_, la1_?NumberQ, lo1_?NumberQ}, {_, la2_?NumberQ, lo2_?NumberQ}} :>
      QuantityMagnitude@UnitConvert[GeoDistance[{la1, lo1}, {la2, lo2}], "Kilometers"]];
  <|"km" -> Total[dists], "edges" -> Length[dists],
    "maxEdgeKm" -> If[dists === {}, 0., Max[dists]]|>];

(* Global latitude-vs-month curve (the true N-S signal; longitude is
   meaningless for a circumpolar breeder). Presence-weighted mean of gridded
   cell latitudes per month -> 12x2 {{month, meanLat}, ...}; Missing for empty
   months. *)
latitudeByMonth[key_Integer, source_:"sample"] := Module[{o},
  o = loadOccurrences[key, source];
  Table[
    Module[{idx = Flatten@Position[o["month"], m], cells},
      If[idx === {},
        {m, Missing["NoData"]},
        cells = gridCells[o["lat"][[idx]], o["lon"][[idx]], o["count"][[idx]]];
        {m, Mean[cells[[All, 1]]]}]],
    {m, 12}]];

(* --- Occurrence loader ---------------------------------------------------- *)

loadOccurrences[key_Integer, source_:"sample"] := Module[{dir, f, d, cols},
  dir = If[source === "full",
    FileNameJoin[{$repoRoot, "data", "raw"}],
    FileNameJoin[{$repoRoot, "data", "raw", "sample"}]];
  f = FileNameJoin[{dir, "occ_" <> ToString[key] <> ".csv"}];
  If[! FileExistsQ[f], Print["MISSING ", f]; Abort[]];
  d = Rest@Import[f, "CSV"];                 (* drop header *)
  d = Select[d, Length[#] >= 5 && NumberQ[#[[1]]] && NumberQ[#[[2]]] &];
  cols = Transpose[d];
  <|"lat"->cols[[1]], "lon"->cols[[2]], "month"->Round@cols[[3]],
    "year"->Round@cols[[4]], "count"->(If[NumberQ[#], #, 1]& /@ cols[[5]])|>];
