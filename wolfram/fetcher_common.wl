(* ::Package:: *)
$repoRoot = ParentDirectory[DirectoryName[$InputFileName]];
$userAgent = "BirdFlightPaths/0.1 (marco_thiel@yahoo.com)";

$speciesList = {
  <|"common"->"Arctic tern", "sci"->"Sterna paradisaea", "key"->5229230, "code"->"arctir1"|>,
  <|"common"->"Common swift","sci"->"Apus apus",          "key"->5228676, "code"->"comswi"|>,
  <|"common"->"Red knot",     "sci"->"Calidris canutus",   "key"->2481765, "code"->"redkno"|>
};

reqHeaders[extra_List] := Join[{"User-Agent" -> $userAgent}, extra];

httpGetString[url_String, headers_:{}] := Module[{r},
  r = URLRead[HTTPRequest[url, <|"Headers" -> reqHeaders[headers]|>]];
  If[r["StatusCode"] =!= 200,
    Print["HTTP ", r["StatusCode"], " for ", url]; Return[$Failed]];
  r["Body"]];

httpGetJSON[url_String, headers_:{}] := Module[{b = httpGetString[url, headers]},
  If[b === $Failed, $Failed, ImportString[b, "RawJSON"]]];

loadConfig[name_String] := Module[{p = FileNameJoin[{$repoRoot, "config", name}]},
  If[! FileExistsQ[p], Print["MISSING config/", name]; Abort[]];
  If[StringEndsQ[name, ".json"], Import[p, "RawJSON"], StringTrim@Import[p, "Text"]]];
