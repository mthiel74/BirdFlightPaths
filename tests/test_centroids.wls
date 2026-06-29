#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];

(* antimeridian: spherical mean near +/-180, not 0 *)
c = sphericalCentroid[{0., 0.}, {170., -170.}, {1., 1.}];
near180 = Abs[Abs[c[[2]]] - 180.] < 1.0;

(* degenerate -> Missing, NOT a fake coordinate *)
deg = sphericalCentroid[{0., 0.}, {0., 180.}, {1., 1.}];
degOk = MatchQ[deg, _Missing];

(* GeoDistance unit safety: known distance Reykjavik->NYC ~4200 km *)
unitOk = Abs[QuantityMagnitude@UnitConvert[GeoDistance[{64.1, -21.9}, {40.7, -74.0}], "Kilometers"] - 4200] < 400;

(* corrected knot (Americas) must be coherent: no single monthly edge > 8000 km *)
knot = monthlyCentroids[2481765, "sample", <|"lon" -> {-110, -30}, "lat" -> {-56, 85}|>];
kp = centroidPathLengthKm[knot];
knotCoherent = kp["maxEdgeKm"] < 8000;

(* The BROKEN global knot proves the contrast is real. DEVIATION FROM BRIEF:
   the brief predicted maxEdgeKm > 10000, but under the mandated PRESENCE
   weighting (which damps observer-effort hotspots) the global centroid does not
   teleport -- it sits as a STABLE but meaningless point in the open mid-Atlantic
   (lon ~ -57 vs the Americas track's ~ -77), so no single edge is huge
   (maxEdgeKm ~ 1800). The genuine pathology is that this lone global centroid
   MISrepresents the Americas (rufa/roselaari) flyway by thousands of km EVERY
   month. We assert that real, robust signal instead. *)
knotG = monthlyCentroids[2481765, "sample", All];
knotSep = MapThread[
   QuantityMagnitude@UnitConvert[
     GeoDistance[{#1[[2]], #1[[3]]}, {#2[[2]], #2[[3]]}], "Kilometers"] &,
   {knotG, knot}];
brokenIsBroken = Mean[knotSep] > 3000;

(* tern Atlantic primary coherent *)
tern = monthlyCentroids[5229230, "sample", <|"lon" -> {-80, 20}, "lat" -> {-90, 90}|>];
ternCoherent = centroidPathLengthKm[tern]["maxEdgeKm"] < 8000;

asserts = {near180, degOk, unitOk, Dimensions[knot] === {12, 3}, knotCoherent,
           brokenIsBroken, ternCoherent};
Print["PASS: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print["FAILS at ", Position[asserts, False]]; Exit[1]];
