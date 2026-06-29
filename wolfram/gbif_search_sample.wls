#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
EOD = "4fa7b334-ce0d-4e88-aaae-2e0c138d049e";
outDir = FileNameJoin[{$repoRoot, "data", "raw", "sample"}];
If[! DirectoryQ[outDir], CreateDirectory[outDir, CreateIntermediateDirectories->True]];

(* WL's URLRead["Body"] correctly decodes UTF-8 to Unicode, but ImportString then
   re-encodes as Latin-1 bytes before parsing JSON — causing parse failures on
   non-ASCII characters in GBIF location fields (e.g. "Sør-Trøndelag").
   Fix: use BodyByteArray decoded as ISO8859-1; the round-trip restores valid UTF-8
   bytes so ImportString's JSON parser succeeds. *)
httpGetJSONFixed[url_] := Module[{r, j},
  r = URLRead[HTTPRequest[url, <|"Headers" -> {"User-Agent" -> $userAgent}|>]];
  If[r["StatusCode"] =!= 200, Print["HTTP ", r["StatusCode"], " for ", url]; Return[$Failed]];
  j = Quiet[ImportString[FromCharacterCode[Normal[r["BodyByteArray"]], "ISO8859-1"], "RawJSON"]];
  If[! AssociationQ[j], Print["JSON parse failed for ", url]; Return[$Failed]];
  j];

perMonth = 300;
fetchMonth[key_, m_] := Module[{url, j},
  url = "https://api.gbif.org/v1/occurrence/search?taxonKey=" <> ToString[key] <>
        "&datasetKey=" <> EOD <> "&hasCoordinate=true&month=" <> ToString[m] <>
        "&year=2014,2024&limit=" <> ToString[perMonth];
  j = httpGetJSONFixed[url];
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
