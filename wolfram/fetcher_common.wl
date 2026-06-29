(* ::Package:: *)
$repoRoot = ParentDirectory[DirectoryName[$InputFileName]];
$userAgent = "BirdFlightPaths/0.1 (marco_thiel@yahoo.com)";

$speciesList = {
  <|"common"->"Arctic tern", "sci"->"Sterna paradisaea", "key"->5229230, "code"->"arcter"|>,
  <|"common"->"Common swift","sci"->"Apus apus",          "key"->5228676, "code"->"comswi"|>,
  <|"common"->"Red knot",     "sci"->"Calidris canutus",   "key"->2481765, "code"->"redkno"|>
};

reqHeaders[extra_List] := Join[{"User-Agent" -> $userAgent}, extra];

(* Return the raw HTTPResponse (status-checked) so callers can decode bytes
   themselves. Decoding from the response *bytes* avoids a WL roundtrip bug
   where URLRead["Body"] -> ImportString re-encodes UTF-8 as Latin-1 and
   corrupts non-ASCII text (e.g. "Sor-Trondelag"), breaking JSON parsing. *)
httpGet[url_String, headers_:{}] := Module[{r},
  r = URLRead[HTTPRequest[url, <|"Headers" -> reqHeaders[headers]|>]];
  If[r["StatusCode"] =!= 200,
    Print["HTTP ", r["StatusCode"], " for ", url]; Return[$Failed]];
  r];

httpGetString[url_String, headers_:{}] := Module[{r = httpGet[url, headers]},
  If[r === $Failed, $Failed, ByteArrayToString[r["BodyByteArray"], "UTF-8"]]];

httpGetJSON[url_String, headers_:{}] := Module[{r = httpGet[url, headers]},
  If[r === $Failed, $Failed, ImportByteArray[r["BodyByteArray"], "RawJSON"]]];

loadConfig[name_String] := Module[{p = FileNameJoin[{$repoRoot, "config", name}]},
  If[! FileExistsQ[p], Print["MISSING config/", name]; Abort[]];
  If[StringEndsQ[name, ".json"], Import[p, "RawJSON"], StringTrim@Import[p, "Text"]]];
