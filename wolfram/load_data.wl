(* ::Package:: *)

(* --- Spherical centroid helpers ------------------------------------------ *)

sphericalCentroid[lats_List, lons_List, w_List] := Module[{v, m},
  v = MapThread[Function[{la, lo, wt},
        wt * {Cos[la Degree] Cos[lo Degree], Cos[la Degree] Sin[lo Degree], Sin[la Degree]}],
        {lats, lons, w}];
  m = Total[v];
  If[Norm[m] < 10^-9, Return[{Mean[lats], Mean[lons]}]];
  m = m / Norm[m];
  {ArcSin[m[[3]]]/Degree, ArcTan[m[[1]], m[[2]]]/Degree}];

(* Group points into ~2-degree cells; return {meanLat, meanLon, totalCount}
   per occupied cell. *)
gridCells[lat_, lon_, cnt_] := Module[{g},
  g = GroupBy[Transpose[{lat, lon, cnt}], {Round[#[[1]]/2], Round[#[[2]]/2]} &];
  KeyValueMap[Function[{k, rows},
     {Mean[rows[[All,1]]], Mean[rows[[All,2]]], Total[rows[[All,3]]]}], g]];

(* Compute 12 monthly centroids for one species; write data/centroids_<key>.csv.
   Returns a 12x3 list {{month, lat, lon}, ...}. *)
monthlyCentroids[key_Integer, source_:"sample"] := Module[{o, res},
  o = loadOccurrences[key, source];
  res = Table[
    Module[{idx = Flatten@Position[o["month"], m], cells},
      If[idx === {}, {m, Missing[], Missing[]},
        cells = gridCells[o["lat"][[idx]], o["lon"][[idx]], o["count"][[idx]]];
        With[{c = sphericalCentroid[cells[[All,1]], cells[[All,2]], cells[[All,3]]]},
          {m, c[[1]], c[[2]]}]]],
    {m, 12}];
  res = res /. {mm_, _Missing, _} :> {mm,
        Sequence @@ sphericalCentroid[
          DeleteMissing[res[[All,2]]], DeleteMissing[res[[All,3]]],
          ConstantArray[1., Length@DeleteMissing[res[[All,2]]]]]};
  Export[FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[key] <> ".csv"}],
    Prepend[res, {"month","lat","lon"}], "CSV"];
  res];

(* Total great-circle km around the 12-month loop; returns a plain number. *)
centroidPathLengthKm[cs_List] := Total[
  GeoDistance[{cs[[#,2]], cs[[#,3]]}, {cs[[Mod[#,12]+1,2]], cs[[Mod[#,12]+1,3]]}] & /@ Range[12]
] /. q_Quantity :> QuantityMagnitude[UnitConvert[q, "Kilometers"]];

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
