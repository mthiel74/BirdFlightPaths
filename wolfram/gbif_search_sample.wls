#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
EOD = "4fa7b334-ce0d-4e88-aaae-2e0c138d049e";
outDir = FileNameJoin[{$repoRoot, "data", "raw", "sample"}];
If[! DirectoryQ[outDir], CreateDirectory[outDir, CreateIntermediateDirectories->True]];

perMonth = 300;
fetchMonth[key_, m_] := Module[{url, j},
  url = "https://api.gbif.org/v1/occurrence/search?taxonKey=" <> ToString[key] <>
        "&datasetKey=" <> EOD <> "&hasCoordinate=true&month=" <> ToString[m] <>
        "&year=2014,2024&limit=" <> ToString[perMonth];
  j = httpGetJSON[url];
  If[j === $Failed, {},
    Select[#, NumberQ[#[[1]]] && NumberQ[#[[2]]] &] & @
     ({#["decimalLatitude"], #["decimalLongitude"], m,
       Lookup[#, "year", 2020], Lookup[#, "individualCount", 1] /. Except[_?NumberQ] -> 1} & /@ j["results"])]];

Do[ Module[{rows},
   rows = Join @@ Table[fetchMonth[sp["key"], m], {m, 12}];
   Export[FileNameJoin[{outDir, "occ_" <> ToString[sp["key"]] <> ".csv"}],
     Prepend[rows, {"lat","lon","month","year","count"}], "CSV"];
   Print[sp["common"], ": ", Length[rows], " rows"];
 ], {sp, $speciesList}];
