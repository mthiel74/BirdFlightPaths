#!/usr/bin/env wolframscript
(* GBIF Download API -> citable DOI + full SIMPLE_CSV data.

   Mints (or resumes) one GBIF download per species, polls until ready,
   parses the SIMPLE_CSV into the tidy lat,lon,month,year,count schema used by
   loadOccurrences[key,"full"], and records the DOIs.

   Resume-aware: if data/raw/gbif_download_keys.json exists it polls those
   downloadKeys instead of submitting new requests (so an interrupted run, or a
   run whose requests were submitted out-of-band, just continues). Delete that
   file to force fresh submissions.

   data/raw/ is git-ignored (bulk + transient); only data/gbif_dois.json is
   committed. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
cfg = loadConfig["gbif_credentials.json"];
EOD = "4fa7b334-ce0d-4e88-aaae-2e0c138d049e";
rawDir = FileNameJoin[{$repoRoot, "data", "raw"}];
keysFile = FileNameJoin[{rawDir, "gbif_download_keys.json"}];

predicate[key_] := ExportString[<|
  "creator" -> cfg["username"], "notificationAddresses" -> {cfg["email"]},
  "sendNotification" -> False, "format" -> "SIMPLE_CSV",
  "predicate" -> <|"type" -> "and", "predicates" -> {
     <|"type" -> "equals", "key" -> "TAXON_KEY", "value" -> ToString[key]|>,
     <|"type" -> "equals", "key" -> "DATASET_KEY", "value" -> EOD|>,
     <|"type" -> "equals", "key" -> "HAS_COORDINATE", "value" -> "true"|>,
     <|"type" -> "equals", "key" -> "BASIS_OF_RECORD", "value" -> "HUMAN_OBSERVATION"|>,
     <|"type" -> "and", "predicates" -> {
        <|"type" -> "greaterThanOrEquals", "key" -> "YEAR", "value" -> "2014"|>,
        <|"type" -> "lessThanOrEquals", "key" -> "YEAR", "value" -> "2024"|>}|>}|>
  |>, "RawJSON"];

submitOne[key_] := Module[{r},
  r = URLRead[HTTPRequest["https://api.gbif.org/v1/occurrence/download/request",
     <|Method -> "POST",
       "Headers" -> {"User-Agent" -> $userAgent, "Content-Type" -> "application/json"},
       "Body" -> predicate[key],
       "Username" -> cfg["username"], "Password" -> cfg["password"]|>]];
  If[r["StatusCode"] =!= 201,
     Print["submit failed for ", key, ": ", r["StatusCode"], " ",
        ByteArrayToString[r["BodyByteArray"], "UTF-8"]]; Abort[]];
  StringTrim[ByteArrayToString[r["BodyByteArray"], "UTF-8"]]];

keys = If[FileExistsQ[keysFile],
  Print["Resuming from existing downloadKeys in ", keysFile];
  Import[keysFile, "RawJSON"],
  Module[{m = Association[ToString[#["key"]] -> submitOne[#["key"]] & /@ $speciesList]},
    If[! DirectoryQ[rawDir], CreateDirectory[rawDir, CreateIntermediateDirectories -> True]];
    Export[keysFile, m, "RawJSON"];
    Print["Submitted: ", m]; m]];

waitFor[dk_] := Module[{status = "", meta},
  While[! MemberQ[{"SUCCEEDED", "KILLED", "FAILED", "CANCELLED"}, status],
    Pause[20];
    meta = httpGetJSON["https://api.gbif.org/v1/occurrence/download/" <> dk];
    If[meta === $Failed, Continue[]];
    status = meta["status"];
    Print["  ", dk, ": ", status,
       If[NumberQ[meta["totalRecords"]], " (" <> ToString[meta["totalRecords"]] <> " records)", ""]]];
  meta];

parseCsv[csv_] := Module[{d, h, body, la, lo, mo, yr, ctp},
  d = Import[csv, "TSV"];                 (* SIMPLE_CSV is tab-separated *)
  h = First[d]; body = Rest[d];
  la = Position[h, "decimalLatitude"][[1, 1]];
  lo = Position[h, "decimalLongitude"][[1, 1]];
  mo = Position[h, "month"][[1, 1]];
  yr = Position[h, "year"][[1, 1]];
  ctp = Position[h, "individualCount"]; ctp = If[ctp === {}, 0, ctp[[1, 1]]];
  Select[
    {ToExpression[#[[la]]], ToExpression[#[[lo]]], ToExpression[#[[mo]]],
     ToExpression[#[[yr]]],
     If[ctp == 0, 1, With[{c = ToExpression[#[[ctp]]]}, If[NumberQ[c], c, 1]]]} & /@ body,
    NumberQ[#[[1]]] && NumberQ[#[[2]]] && IntegerQ[#[[3]]] &]];

processOne[speciesKey_, dk_] := Module[{meta, zip, dir, csv, rows, rr},
  Print["== ", speciesKey, " (", dk, ") =="];
  meta = waitFor[dk];
  If[meta["status"] =!= "SUCCEEDED",
     Print["  not SUCCEEDED (", meta["status"], ") -- skipping"]; Return[$Failed]];
  zip = FileNameJoin[{rawDir, dk <> ".zip"}];
  rr = URLRead[HTTPRequest[meta["downloadLink"], <|"Headers" -> {"User-Agent" -> $userAgent}|>]];
  If[rr["StatusCode"] =!= 200, Print["  zip dl failed ", rr["StatusCode"]]; Return[$Failed]];
  BinaryWrite[zip, rr["BodyByteArray"]]; Close[zip];
  dir = FileNameJoin[{rawDir, "extract_" <> ToString[speciesKey]}];
  ExtractArchive[zip, dir, OverwriteTarget -> True];
  csv = First@FileNames["*.csv", dir];
  rows = parseCsv[csv];
  Export[FileNameJoin[{rawDir, "occ_" <> ToString[speciesKey] <> ".csv"}],
     Prepend[rows, {"lat", "lon", "month", "year", "count"}], "CSV"];
  Print["  parsed ", Length[rows], " rows"];
  <|"doi" -> "https://doi.org/" <> meta["doi"], "downloadKey" -> dk, "n" -> Length[rows]|>];

res = Association[# -> processOne[#, keys[#]] & /@ Keys[keys]];
Export[FileNameJoin[{$repoRoot, "data", "gbif_dois.json"}], res, "RawJSON"];
Print["DOIs: ", (#["doi"] & /@ Values[res])];
Print["counts: ", (#["n"] & /@ Values[res])];
