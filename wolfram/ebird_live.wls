#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
token = loadConfig["ebird_api_key.txt"];
hdr = {"X-eBirdApiToken" -> token};
regions = {"US","CA","GB","IE","IS","NO","SE","FI","NL","FR","ES","PT","DE","DK",
           "ZA","AU","NZ","AR","CL","BR","MX","SN","MA","NA","IN","JP","RU"};
fetch[code_, reg_] := Module[{j},
  j = httpGetJSON["https://api.ebird.org/v2/data/obs/" <> reg <> "/recent/" <> code <>
        "?back=30&maxResults=200", hdr];
  If[j === $Failed || ! ListQ[j], {},
    (* privacy: round to 1 dp, keep only lat/lon/date, drop locName *)
    {Round[#["lat"], 0.1], Round[#["lng"], 0.1], Lookup[#, "obsDt", ""]} & /@
      Select[j, NumberQ[#["lat"]] && NumberQ[#["lng"]] &]]];

Do[ Module[{rows, pts, map},
   rows = DeleteDuplicates[Join @@ (fetch[sp["code"], #] & /@ regions)];
   Export[FileNameJoin[{$repoRoot, "data", "live_" <> ToString[sp["key"]] <> ".csv"}],
     Prepend[rows, {"lat","lon","obsDt"}], "CSV"];
   pts = {#[[1]], #[[2]]} & /@ rows;
   map = If[Length[pts] > 0,
     GeoListPlot[GeoPosition /@ pts, GeoRange -> "World",
       GeoProjection -> "Robinson", GeoBackground -> GrayLevel[0.15],
       PlotStyle -> Directive[Orange, Opacity[0.7], PointSize[0.006]],
       PlotLabel -> sp["common"] <> " \[LongDash] recent eBird sightings (last 30 d)\nSource: eBird.org (Cornell Lab of Ornithology)",
       ImageSize -> 900],
     (* fallback: blank world map when no observations in any region *)
     GeoListPlot[{}, GeoRange -> "World",
       GeoProjection -> "Robinson", GeoBackground -> GrayLevel[0.15],
       PlotLabel -> sp["common"] <> " \[LongDash] recent eBird sightings (last 30 d)\nSource: eBird.org (Cornell Lab of Ornithology)",
       ImageSize -> 900]];
   Export[FileNameJoin[{$repoRoot, "docs", "images", "live_" <> ToString[sp["key"]] <> ".png"}],
     map, "PNG", ImageResolution -> 120];
   Print[sp["common"], ": ", Length[pts], " live points"];
 ], {sp, $speciesList}];
