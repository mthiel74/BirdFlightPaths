Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
asserts = {
  StringQ[$repoRoot] && DirectoryQ[$repoRoot],
  Length[$speciesList] === 3,
  AssociationQ[First@$speciesList] && First[$speciesList]["key"] === 5229230,
  httpGetJSON["https://api.gbif.org/v1/species/5229230"]["scientificName"] =!= Missing
};
Print["PASS count: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print["FAILS: ", Position[asserts, False]]; Exit[1]];
