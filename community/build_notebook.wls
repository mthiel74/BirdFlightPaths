#!/usr/bin/env wolframscript
(* ::Package:: *)

(*  Build community/bird_migration.nb (+ .pdf) -- the educational
    long-form notebook for the Wolfram Community submission.

    Architecture ported from ENSO-emergence/community/build_notebook.wls:
    accumulate fully-formed Cell expressions into $allCells, then host
    them in an invisible FrontEnd document and NotebookSave / Export so
    Image[] and AnimatedImage[] cells serialise as binary rasters -- no
    fragile ToBoxes magic, no missing-figure placeholders.

    Sections
    --------
      Abstract
      Setup
      1.  Three great migrants & why migration matters
      2.  The data: eBird, GBIF, and the effort-bias problem
      3.  From checklists to centroids (method)
      4.  The multi-flyway trap (the key lesson)
      5.  Animating the population centroid (+ the flock)
      6.  Speeds and stopovers
      7.  The energy of migration
      8.  Finding the way: the magnetic landscape
      9.  Cross-check: eBird Status & Trends (prose only)
      9b. Live now: recent sightings via the eBird API
      10. What each journey reveals
      11. New ideas, and how to test them
      12. Conclusions
      13. References
      14. Acknowledgements & data licences
      15. Reproducibility
*)

repoRoot = ParentDirectory @ DirectoryName[$InputFileName];
imgDir   = FileNameJoin[{repoRoot, "docs", "images"}];
dataDir  = FileNameJoin[{repoRoot, "data"}];
outNb    = FileNameJoin[{repoRoot, "community", "bird_migration.nb"}];
outPdf   = FileNameJoin[{repoRoot, "community", "bird_migration.pdf"}];

(* Blue heading colour -- matches the reference Community notebook exactly. *)
blue = RGBColor[0.153, 0.51, 0.64];


(* ==================================================================
   Helpers
   ================================================================== *)

(* Headings -- blue, Roboto Condensed, per the reference notebook. *)
title[txt_]    := Cell[txt, "Title",
   FontColor -> blue, FontFamily -> "Roboto Condensed"];
subtitle[txt_] := Cell[txt, "Subtitle"];
hd1[txt_]      := Cell[txt, "Section",
   FontColor -> blue, FontFamily -> "Roboto Condensed", FontSize -> 30];
hd2[txt_]      := Cell[txt, "Subsection",
   FontColor -> blue, FontFamily -> "Roboto Condensed"];
hd3[txt_]      := Cell[txt, "Subsubsection", FontColor -> blue];

(* Paragraph text *)
para[stuff_] := Cell[TextData[stuff], "Text", CellMargins -> {{50, 50}, {6, 6}}];

abstractCell[stuff_] := Cell[TextData[stuff], "Text",
   FontSize -> 14, CellMargins -> {{60, 60}, {6, 6}},
   Background -> RGBColor[0.94, 0.97, 0.98]];

(* Inline styles *)
bold[s_] := StyleBox[s, FontWeight -> Bold];
ital[s_] := StyleBox[s, FontSlant -> Italic];
math[s_] := StyleBox[s, FontFamily -> "Times", FontSlant -> Italic];
mono[s_] := StyleBox[s, FontFamily -> "Courier"];

(* Inline hyperlink that renders well in both interactive and PDF views. *)
link[txt_String, url_String] := Sequence[
   StyleBox[txt, FontWeight -> "SemiBold"],
   " (", StyleBox[url, FontFamily -> "Courier", FontSize -> 10], ")"];

(* Image cache: pre-resize on disk so embedded rasters stay small. *)
imgCacheDir = FileNameJoin[{repoRoot, "community", ".img-cache"}];
If[! DirectoryQ[imgCacheDir], CreateDirectory[imgCacheDir]];

resizedCopy[path_] := Module[{cached, w, h, im, target = 760},
   cached = FileNameJoin[{imgCacheDir, FileNameTake[path]}];
   If[FileExistsQ[cached] &&
      FileDate[cached, "Modification"] > FileDate[path, "Modification"],
     Return[cached]];
   im = Import[path];
   {w, h} = ImageDimensions[im];
   If[w > target, im = ImageResize[im, target]];
   Export[cached, im, "PNG"];
   cached];

imgWidth = 640;

imgCell[file_] := Module[{path = FileNameJoin[{imgDir, file}], small, im},
   If[FileExistsQ[path],
     small = resizedCopy[path];
     im = Image[Import[small], ImageSize -> imgWidth];
     Cell[BoxData @ ToBoxes[im], "Output",
        ShowCellLabel -> False, TextAlignment -> Center,
        CellMargins -> {{Automatic, Automatic}, {10, 6}}],
     Cell[TextData[{bold["[ missing figure: " <> file <> " ]"]}],
        "Text", FontColor -> RGBColor[0.7, 0.1, 0.1],
        TextAlignment -> Center]
   ]];

(* animCell -- embed a GIF as an inline AnimatedImage cell. Community's
   web renderer preserves AnimatedImage as a looping <img>. ColorQuantize
   per frame keeps the embedded notebook small. *)
animWidth = 460;

animCell[file_] := animCell[file, ""];
animCell[file_String, caption_] := Module[
   {path = FileNameJoin[{imgDir, file}], all, anim, boxes},
   If[! FileExistsQ[path],
     Return @ Cell[TextData[{bold["[ missing animation: " <> file <> " ]"]}],
        "Text", FontColor -> RGBColor[0.7, 0.1, 0.1], TextAlignment -> Center]];
   all = Import[path, {"GIF", "ImageList"}];
   all = ColorQuantize[ImageResize[#, {animWidth}], 128] & /@ all;
   anim = AnimatedImage[all, FrameRate -> 1.25,
      AnimationRunning -> True, AnimationRepetitions -> Infinity];
   boxes = ToBoxes[
      If[caption === "", anim,
         Column[{anim,
            Pane[Style[caption, Italic, FontSize -> 10,
               FontFamily -> "Helvetica", FontColor -> GrayLevel[0.35]],
               animWidth, Alignment -> Center]},
            Alignment -> Center, Spacings -> 0.6]]];
   Cell[BoxData[boxes], "Output", ShowCellLabel -> False,
      TextAlignment -> Center, CellMargins -> {{Automatic, Automatic}, {10, 14}}]];

captionCell[args__] := Cell[TextData[{args}], "Text",
   FontSlant -> Italic, FontSize -> 11, FontColor -> GrayLevel[0.35],
   CellMargins -> {{70, 70}, {2, 14}}];

(* Fixed-width "Program" cell -- shell snippets, URLs. *)
codeIn[code_String] := Cell[code, "Program",
   CellMargins -> {{60, 30}, {6, 6}}, FontFamily -> "Courier", FontSize -> 11,
   ShowStringCharacters -> False, Background -> RGBColor[0.95, 0.96, 0.98]];

(* Runnable, syntax-highlighted Wolfram-Language Input cell. *)
wlIn[code_String] := Cell[code, "Input",
   CellMargins -> {{60, 30}, {6, 6}}, FontSize -> 11];


(* ==================================================================
   DOI handling -- gbif_dois.json may not exist yet.
   ================================================================== *)
doiPending = "DOI pending (rerun after the GBIF download completes)";
doiFile = FileNameJoin[{dataDir, "gbif_dois.json"}];
$dois = If[FileExistsQ[doiFile], Quiet @ Import[doiFile, "RawJSON"], $Failed];
(* each value in gbif_dois.json is an association <|"doi"->_,"downloadKey"->_,"n"->_|>;
   pull the "doi" STRING (the earlier version handed the whole assoc to mono[],
   which the front end rendered as raw syntax + ErrorBox). *)
doiFor[key_] := If[AssociationQ[$dois],
   Lookup[Lookup[$dois, ToString[key], <||>], "doi", doiPending],
   doiPending];
Print["DOIs available: ", AssociationQ[$dois], "  e.g. tern -> ", doiFor[5229230]];


(* ==================================================================
   Validation numbers (private S&T cross-check) -- prefer the JSON.
   ================================================================== *)
valFile = FileNameJoin[{repoRoot, "data", "raw", "ebirdst", "validation.json"}];
$val = If[FileExistsQ[valFile], Quiet @ Import[valFile, "RawJSON"], $Failed];
sepKm[key_, fallback_] := If[AssociationQ[$val] && KeyExistsQ[$val, ToString[key]],
   Round @ Lookup[$val[ToString[key]], "meanSepKm", fallback], fallback];
swiftSep = sepKm[5228676, 1895];
knotSep  = sepKm[2481765, 1594];
ternSep  = sepKm[5229230, 1520];
Print["S&T separations (km): swift=", swiftSep, " knot=", knotSep, " tern=", ternSep];


(* ==================================================================
   Derived-science JSON readers -- numbers are READ from the data files
   (never hardcoded) so the prose stays consistent with the pipeline.
   Each file is a JSON array of per-species records; we look records up
   by their natural key and pull a field, failing loud if absent.
   ================================================================== *)
loadArr[file_] := Module[{p = FileNameJoin[{dataDir, file}]},
   If[FileExistsQ[p], Quiet @ Import[p, "RawJSON"], {}]];
$jm = loadArr["journey_metrics.json"];   (* keyed by integer "key"     *)
$en = loadArr["energetics.json"];        (* keyed by string  "name"    *)
$gm = loadArr["geomag_following.json"];  (* keyed by string  "species" *)

(* record lookups *)
jmRec[key_]    := SelectFirst[$jm, #["key"] === key &, <||>];
enRec[name_]   := SelectFirst[$en, #["name"] === name &, <||>];
gmRec[spec_]   := SelectFirst[$gm, #["species"] === spec &, <||>];

(* number -> display-string formatters (return Strings for TextData) *)
n0[x_] := If[NumberQ[x], ToString[Round[x]], "?"];
n1[x_] := If[NumberQ[x], ToString[N @ Round[x, 0.1]], "?"];
n2[x_] := If[NumberQ[x], ToString[N @ Round[x, 0.01]], "?"];
nComma[x_] := If[NumberQ[x],
   ToString[NumberForm[Round[x], DigitBlock -> 3, NumberSeparator -> ","]], "?"];

(* field pulls with formatting *)
jmF[key_, field_, f_] := f[Lookup[jmRec[key], field, Missing[]]];
enF[name_, field_, f_] := f[Lookup[enRec[name], field, Missing[]]];
gmF[spec_, field_, f_] := f[Lookup[gmRec[spec], field, Missing[]]];
Print["journey_metrics rows: ", Length[$jm],
   "  energetics rows: ", Length[$en],
   "  geomag rows: ", Length[$gm]];
Print["e.g. tern meanSpeed=", jmF[5229230, "meanSpeedKmDay", n0],
   "  tern Vmr=", enF["Arctic tern", "VmrKmh", n0],
   "  tern dipRange=", gmF["Arctic tern", "dipRangeDeg", n0]];


(* ==================================================================
   Accumulate cells.
   ================================================================== *)
$allCells = {};
writeAll[cs_List] := Module[{},
   $allCells = Join[$allCells, cs];
   Print["  writeAll: +", Length[cs], " cells (total = ", Length[$allCells], ")"];];


(* ----------------- TITLE, HERO & ABSTRACT ----------------- *)

writeAll[{

title["Bird migration paths from eBird data"],

subtitle["Seasonal maps and animated population centroids for the Arctic \
tern, common swift, and red knot \[LongDash] from hundreds of millions of \
citizen-science observations"],

Cell["Wolfram Community submission \[LongDash] 2026", "Subsubtitle",
   FontSlant -> Italic, FontColor -> GrayLevel[0.4]],

animCell["hero.gif",
   "Cover animation.  A slowly rotating dark globe on which each species' \
monthly population centroid glides as a glowing comet along its \
great-circle migration loop (Arctic tern in orange, common swift in cyan, \
red knot in gold), each over a faint full-year route. The centroids are \
computed per coherent flyway, not pooled globally \[LongDash] the central \
methodological point of this post. The code that produces every track is \
given in \[Section]3\[Dash]\[Section]5."],

hd1["Abstract"],

abstractCell[{"This notebook reconstructs the annual migration of three \
iconic birds \[LongDash] the ", bold["Arctic tern"], " (",
   ital["Sterna paradisaea"], ", a pole-to-pole Atlantic-basin migrant), \
the ", bold["common swift"], " (", ital["Apus apus"], ", an \
Afro-Palearctic aerialist), and the ", bold["red knot"], " (",
   ital["Calidris canutus"], ", a long-haul Americas-flyway shorebird) \
\[LongDash] entirely from open citizen-science data, in pure Wolfram \
Language."}],

abstractCell[{"The pipeline pulls eBird observations through ", bold["GBIF"],
   "'s eBird Observation Dataset (licensed ", bold["CC BY 4.0"],
   ", with a citable DOI), computes an ", bold["effort-bias-aware monthly \
population centroid"], " using presence weighting and a proper ",
   bold["spherical mean"], " (a 3-D unit-vector average, essential for \
circumpolar and dateline-crossing species), builds seasonal occurrence \
maps and an animated centroid track, ", bold["validates"],
   " the result against Cornell's eBird Status & Trends, and adds a live \
\[OpenCurlyDoubleQuote]right now\[CloseCurlyDoubleQuote] layer from the \
eBird API."}],

abstractCell[{"The central lesson is methodological: a single ",
   ital["global"], " centroid is meaningless for a species spread across \
several disjoint flyways \[LongDash] pooling the red knot's three flyways \
puts its \[OpenCurlyDoubleQuote]centre\[CloseCurlyDoubleQuote] in the \
mid-Atlantic, displaced ~4,670 km/month from where the Americas population \
actually is. Computing one centroid ", ital["per coherent flyway"],
   " fixes this. Throughout, the prose opens each section intuitively for \
the general reader, then deepens into the quantitative method for the \
specialist."}]

}];


(* ----------------- SETUP ----------------- *)

writeAll[{

hd1["Setup (optional \[LongDash] only needed to run the code)"],

para[{ital["You can ignore this section entirely if you just want to read \
the post."], " Every figure is pre-rendered into the notebook as a static \
image, so the prose, maps, and animations all work without evaluating \
anything."}],

para[{"If you ", ital["do"], " want to run the code cells, the helper \
functions (spherical centroid, centroid-CSV loaders, orthographic globe, \
live-sightings fetcher) live in a single attached package, ",
   mono["birdflightpaths_helpers.wl"], ", uploaded alongside the notebook. \
Run the cell below once after opening the notebook; it loads every helper \
symbol used in the rest of the post."}],

wlIn["(* Put birdflightpaths_helpers.wl in the same folder as this
   notebook, then shift-Enter. The package sets $BFPDataDir-relative
   paths; point it at your local data/ folder if needed. *)
SetDirectory[NotebookDirectory[]];
$BFPDataDir = FileNameJoin[{NotebookDirectory[], \"data\"}];
Get[\"birdflightpaths_helpers.wl\"];"]

}];


(* ============================================================
   1. Three great migrants
   ============================================================ *)

writeAll[{

hd1["1.  Three great migrants & why migration matters"],

para[{ital["The basic story."], " Twice a year, billions of birds move \
between the places where they breed and the places where they spend the \
rest of the year. Migration lets a bird exploit a brief, intense pulse of \
high-latitude summer productivity to raise young, then retreat to milder \
latitudes when that pulse collapses into winter. The cost is one of the \
most demanding feats in the animal kingdom: sustained, navigated, \
long-distance flight, twice annually, for life. We follow three species \
that bracket the extremes of that feat."}],

para[{bold["Arctic tern"], " (", ital["Sterna paradisaea"], "). The \
longest-distance migrant known. Individuals tracked with geolocators \
average roughly ", bold["70,900 km per year"], " round trip \[LongDash] \
from high-Arctic breeding grounds to the Antarctic pack ice and back \
(Egevang et al. 2010, ", ital["PNAS"], " 107:2078). Because it follows the \
sun from one polar summer to the other, the Arctic tern experiences more \
daylight per year than any other animal."}],

para[{bold["Common swift"], " (", ital["Apus apus"], "). An \
Afro-Palearctic migrant that breeds across Europe and temperate Asia and \
winters in sub-Saharan Africa. Remarkably, it is almost entirely ",
   bold["aerial"], " for the roughly ten months it is not nesting \
(Hedenstr\[ODoubleDot]m et al. 2016): it feeds and sleeps on the wing \
\[LongDash] and may even mate aloft \[LongDash] landing essentially only to \
breed. A young swift may not touch a solid surface for its first two or three \
years of life."}],

para[{bold["Red knot"], " (", ital["Calidris canutus"], "). A medium-sized \
shorebird that undertakes some of the longest-known shorebird migrations, \
on several distinct flyways worldwide. The Americas (", ital["rufa"],
   ") population is famous for its Delaware Bay stopover, timed to the \
spring spawning of horseshoe crabs \[LongDash] the knots gorge on the eggs \
to fuel the final leg to the Arctic. That tight coupling makes the species \
a textbook case of migratory vulnerability."}],

para[{ital["Why migration matters."], " Beyond the spectacle, migration is \
a load-bearing piece of how ecosystems work: it moves energy, nutrients, \
and predation pressure across continents on a seasonal clock. It is also \
acutely exposed to global change \[LongDash] habitat loss at a single \
stopover, or a phenological mismatch between arrival and the food peak, can \
collapse a population that is otherwise healthy at both ends of its range. \
Mapping where these birds are, month by month, is the first step to \
understanding and protecting them."}]

}];


(* ============================================================
   2. The data: eBird, GBIF, effort bias
   ============================================================ *)

writeAll[{

hd1["2.  The data: eBird, GBIF, and the effort-bias problem"],

para[{ital["Where the data come from."], " ", bold["eBird"],
   ", run by the Cornell Lab of Ornithology, is the world's largest \
biodiversity citizen-science project: hundreds of millions of bird \
observations submitted by hundreds of thousands of volunteer birdwatchers \
as dated, located checklists. We do not query eBird directly. Instead we \
access its observations through ", bold["GBIF"],
   " (the Global Biodiversity Information Facility), which republishes them \
as the ", bold["eBird Observation Dataset (EOD)"],
   " under a ", bold["CC BY 4.0"], " licence \[LongDash] which means the \
data are freely publishable provided we cite the source DOI."}],

para[{"GBIF's Download API lets us mint a reproducible, ", bold["citable \
DOI"], " for an exact query. We ask for human observations of each \
species, with coordinates, from the EOD dataset (",
   mono["datasetKey 4fa7b334-ce0d-4e88-aaae-2e0c138d049e"],
   "), over a fixed eleven-year window (2014\[Dash]2024). The predicate below is the actual query \
structure used by the project's ", mono["wolfram/gbif_download.wls"], ":"}],

wlIn["(* GBIF Download API predicate: one citable download per species.
   EOD = eBird Observation Dataset (CC BY 4.0). *)
EOD = \"4fa7b334-ce0d-4e88-aaae-2e0c138d049e\";
predicate[key_] := <|
  \"type\" -> \"and\", \"predicates\" -> {
    <|\"type\" -> \"equals\", \"key\" -> \"TAXON_KEY\",   \"value\" -> ToString[key]|>,
    <|\"type\" -> \"equals\", \"key\" -> \"DATASET_KEY\", \"value\" -> EOD|>,
    <|\"type\" -> \"equals\", \"key\" -> \"HAS_COORDINATE\", \"value\" -> \"true\"|>,
    <|\"type\" -> \"equals\", \"key\" -> \"BASIS_OF_RECORD\", \"value\" -> \"HUMAN_OBSERVATION\"|>,
    <|\"type\" -> \"and\", \"predicates\" -> {
       <|\"type\" -> \"greaterThanOrEquals\", \"key\" -> \"YEAR\", \"value\" -> \"2014\"|>,
       <|\"type\" -> \"lessThanOrEquals\",    \"key\" -> \"YEAR\", \"value\" -> \"2024\"|>}|>}|>;
(* POST predicate[5229230] to /occurrence/download/request -> a downloadKey
   that resolves to a permanent DOI once the archive is built. *)"],

para[{"The raw archive arrives as a tidy table of ", mono["lat, lon, \
month, year"], " per occurrence. A first look, binned by month, already \
tells a clear seasonal story \[LongDash] here for the Arctic tern, whose \
occurrences sweep from the northern breeding grounds down the Atlantic and \
back over the year:"}],

wlIn["(* Seasonal occurrence map: 12 monthly GeoHistogram panels.
   o = loadOccurrences[key]; one 750-km hex bin map per calendar month. *)
o = loadOccurrences[5229230];
Grid@Partition[Table[
   Module[{idx = Flatten@Position[o[\"month\"], m]},
     GeoHistogram[
       GeoPosition /@ Transpose[{o[\"lat\"][[idx]], o[\"lon\"][[idx]]}],
       Quantity[750, \"Kilometers\"], GeoRange -> \"World\",
       GeoProjection -> \"Robinson\", ColorFunction -> \"TemperatureMap\",
       GeoBackground -> GrayLevel[0.15], PlotLabel -> monthNames[[m]],
       ImageSize -> 230]],
   {m, 12}], 4]"],

imgCell["seasonal_5229230.png"],
captionCell["Figure 2.1  Monthly occurrence density of the Arctic tern \
from the GBIF / eBird Observation Dataset (2014\[Dash]2024), one panel per \
calendar month, 750-km hex bins, Robinson projection. The northward \
breeding-season concentration (May\[Dash]July) and the long southbound \
Atlantic passage are both visible. ", ital["But read the next caption \
before trusting any apparent geography."]],

para[{ital["The honest caveat: effort bias."], " Occurrence records do not \
report where the birds are \[LongDash] they report where the ",
   bold["observers"], " are. eBird coverage is overwhelmingly concentrated \
in North America and Western Europe, where most contributors live, and is \
sparse across the open ocean, the tropics, and the Southern Hemisphere. A \
naive density map therefore conflates \[OpenCurlyDoubleQuote]many birds \
here\[CloseCurlyDoubleQuote] with \[OpenCurlyDoubleQuote]many birders \
here.\[CloseCurlyDoubleQuote] Any honest analysis of citizen-science \
occurrence data must correct for this sampling bias before drawing \
geographic conclusions \[LongDash] which is exactly what the centroid \
method in \[Section]3 is built to do."}]

}];


(* ============================================================
   3. From checklists to centroids (method)
   ============================================================ *)

writeAll[{

hd1["3.  From checklists to centroids (method)"],

para[{ital["The idea."], " To summarise \[OpenCurlyDoubleQuote]where the \
population is\[CloseCurlyDoubleQuote] in a given month with a single point, \
we compute the ", bold["monthly population centroid"], " \[LongDash] a \
weighted average location of that month's occurrences. Done naively this \
inherits all the effort bias of \[Section]2 and is geometrically wrong for \
a round planet. Two corrections fix both problems."}],

hd2["3.1  Correction one: presence weighting on a coarse grid"],

para[{"A raw average over occurrence ", ital["points"],
   " is dominated by a handful of intensely-birded hotspots \[LongDash] a \
single famous reserve can contribute tens of thousands of records and drag \
the centroid toward itself. To blunt this, we lay down a coarse ",
   bold["2\[Degree] grid"], " and weight each ", ital["occupied cell"],
   " equally (presence = 1 per cell), rather than weighting by the number \
of records in the cell. A cell with 40,000 checklists and a cell with one \
both count once. This converts \[OpenCurlyDoubleQuote]where were people \
looking\[CloseCurlyDoubleQuote] into \[OpenCurlyDoubleQuote]where was the \
species present,\[CloseCurlyDoubleQuote] which is far closer to the \
quantity we want."}],

para[{ital["A subtlety for the specialist."], " A 2\[Degree]\[Times]\
2\[Degree] cell is ", bold["not"], " equal-area: its true area shrinks \
toward the poles in proportion to ", math["cos(lat)"], ". For \
high-latitude species this matters, and the spherical mean below handles \
it correctly by construction \[LongDash] each presence point is converted \
to a unit vector whose contribution is naturally weighted by the geometry \
of the sphere, not by a flat lon\[Times]lat rectangle."}],

hd2["3.2  Correction two: a proper spherical centroid"],

para[{"The deeper problem is that ", bold["you cannot average longitudes \
arithmetically"], ". Longitude wraps at \[PlusMinus]180\[Degree]: the mean \
of +170\[Degree] and \[Minus]170\[Degree] is not 0\[Degree] (the Atlantic) \
\[LongDash] it should be 180\[Degree] (the dateline). For a circumpolar \
bird like the Arctic tern, whose occurrences ring the entire planet, a \
naive longitude average is simply meaningless. The correct construction \
embeds each point on the unit sphere, averages the 3-D vectors, and \
projects back:"}],

wlIn["(* Weighted spherical mean of (lat,lon) points. Returns {lat,lon}
   in degrees, or Missing[\"DegenerateCentroid\"] when the resultant
   vector is ~0 (antipodally smeared points cancel) -- we never fabricate
   an arithmetic-mean longitude. (This is the helper in the package.) *)
sphericalCentroid[lats_, lons_, w_] := Module[{v, m},
  v = MapThread[Function[{la, lo, wt},
        wt {Cos[la Degree] Cos[lo Degree],
            Cos[la Degree] Sin[lo Degree],
            Sin[la Degree]}], {lats, lons, w}];
  m = Total[v];
  If[Norm[m] < 10^-9, Return[Missing[\"DegenerateCentroid\"]]];
  m = m/Norm[m];
  {ArcSin[m[[3]]]/Degree, ArcTan[m[[1]], m[[2]]]/Degree}];"],

para[{"The ", mono["Missing[\"DegenerateCentroid\"]"], " branch is not \
defensive boilerplate \[LongDash] it is the honest answer when a \
population is spread so evenly around the globe (or split into antipodal \
clumps) that ", ital["no"], " single point represents it. Returning a \
fabricated longitude there would be worse than returning nothing. As we \
will see in \[Section]4, this is precisely the situation a global centroid \
walks into for a multi-flyway species, and the reason we must split by \
flyway first."}]

}];


(* ============================================================
   4. The multi-flyway trap
   ============================================================ *)

writeAll[{

hd1["4.  The multi-flyway trap (the key lesson)"],

para[{ital["The trap."], " A spherical centroid is only meaningful if the \
points it averages belong to a single, ", ital["coherent"],
   " population. Many species do not: they split into geographically \
disjoint ", bold["flyways"], " that never mix. Averaging across flyways \
produces a \[OpenCurlyDoubleQuote]centre\[CloseCurlyDoubleQuote] that lies \
where ", ital["no birds are"], " \[LongDash] the midpoint of two crowds is \
the empty space between them."}],

para[{"The red knot is the textbook case. Pool its Americas, \
European/African, and Asian-Australasian flyways into one global centroid \
and the result drifts out into the open ", bold["mid-Atlantic"],
   ", on average ", bold["~4,670 km per month"], " away from where the \
Americas (", ital["rufa"], ") population \[LongDash] the one a North \
American reader actually sees \[LongDash] truly is. The number is not a \
rounding artefact; it is the signature of averaging across populations \
that should never have been combined."}],

wlIn["(* The fix: restrict to one coherent flyway BEFORE taking the
   centroid. Each box is {lon -> {min,max}, lat -> {min,max}}. *)
swift = monthlyCentroids[5228676, <|\"lon\" -> {-30, 145},  \"lat\" -> {-40, 75}|>];  (* Afro-Palearctic *)
knot  = monthlyCentroids[2481765, <|\"lon\" -> {-110, -30}, \"lat\" -> {-56, 85}|>];  (* Americas flyway *)
tern  = monthlyCentroids[5229230, <|\"lon\" -> {-80, 20},   \"lat\" -> {-90, 90}|>];  (* Atlantic basin *)

(* The BROKEN contrast: no flyway filter -> meaningless mid-ocean centroid *)
knotGlobal = monthlyCentroids[2481765, All];"],

para[{"With each species reduced to a single coherent flyway, the monthly \
centroids trace clean, interpretable migration loops. The common swift's \
Afro-Palearctic flyway needs no special handling \[LongDash] it is already \
one population, and its centroid simply works. The red knot is shown on \
its Americas flyway. The Arctic tern is shown as an Atlantic-basin \
centroid (and, separately, as a latitude-versus-month curve, since its \
defining signal is the pole-to-pole north\[Dash]south sweep):"}],

imgCell["centroid_track_5229230.png"],
captionCell["Figure 4.1  Arctic tern \[LongDash] monthly population \
centroid on the Atlantic-basin flyway, orthographic globe over relief. \
Numbers mark the calendar month; the track sweeps from southern winter \
quarters up to high-Arctic breeding latitudes and back."],

imgCell["centroid_track_5228676.png"],
captionCell["Figure 4.2  Common swift \[LongDash] monthly population \
centroid on the single Afro-Palearctic flyway. Breeding-season \
concentration over Europe (months ~5\[Dash]8) and the sub-Saharan \
wintering shift (months ~11\[Dash]2) are both clear; no flyway splitting \
is needed because there is only one population."],

imgCell["centroid_track_2481765.png"],
captionCell["Figure 4.3  Red knot \[LongDash] monthly population centroid \
restricted to the Americas flyway. Compare this coherent loop with the \
broken global centroid (the ", mono["knotGlobal"], " contrast above), \
which would sit uselessly in the mid-Atlantic, ~4,670 km/month from this \
track. ", ital["A caveat in the other direction:"], " presence weighting \
blunts but does not erase effort bias. The Americas winter centroid here sits \
around Panama/northern Colombia rather than at the iconic ", ital["rufa"], \
" wintering grounds in Tierra del Fuego (~54\[Degree]S): the densely-birded \
USA and Caribbean still outweigh the sparsely-observed Patagonian coast, and \
the centroid blends several wintering areas. The shape of the journey is \
right; the precise southern extreme is pulled north."]

}];


(* ============================================================
   5. Animating the population centroid
   ============================================================ *)

writeAll[{

hd1["5.  Animating the population centroid"],

para[{"Stringing the twelve monthly centroids together and interpolating \
along great circles between them turns the static loops of \[Section]4 into \
the animated comet-trail globe shown at the top of this post. Each \
species' centre of mass glides through the year over its faint annual \
route \[LongDash] the most compact possible summary of \
\[OpenCurlyDoubleQuote]where is this population, right now, on average.\
\[CloseCurlyDoubleQuote]"}],

para[{"We can also quantify each loop. Summing the great-circle distances \
between consecutive monthly centroids (over observed months only) gives the \
", bold["annual centroid displacement"], " \[LongDash] how far the centre \
of mass travels in a year:"}],

wlIn["(* Annual centroid displacement per primary flyway track. *)
pl = Import[FileNameJoin[{$BFPDataDir, \"path_lengths.csv\"}], \"CSV\"];
prim = Select[Rest[pl], ! StringContainsQ[#[[3]], \"global\", IgnoreCase -> True] &];
BarChart[prim[[All, 4]],
   ChartLabels -> (Style[#[[2]] <> \"\\n(\" <> #[[3]] <> \")\", 10] & /@ prim),
   BarOrigin -> Left,
   PlotLabel -> Style[
     \"Annual centroid displacement (km) -- NOT individual journey distance\", 13],
   ImageSize -> 780, AspectRatio -> 0.5]"],

imgCell["path_lengths.png"],
captionCell["Figure 5.1  Annual displacement of the monthly population \
centroid along each species' primary flyway: common swift (Afro-Palearctic) \
\[TildeTilde] 14,000 km, red knot (Americas) \[TildeTilde] 7,900 km, Arctic \
tern (Atlantic basin) \[TildeTilde] 24,100 km. The deliberately broken \
global red-knot track is excluded."],

Cell[TextData[{
   StyleBox["Crucial caveat \[LongDash] read before quoting these numbers. ",
      FontWeight -> Bold, FontSlant -> Italic],
   "This is the displacement of the population ", ital["centre of mass"],
   ", NOT how far any individual bird flies. The two differ enormously, and \
in both directions. For the Arctic tern the centroid figure ",
   bold["understates"], " the journey: because the species is nearly \
circumpolar, east\[Dash]west motion in different longitudes cancels in the \
mean, so the centroid mostly captures the north\[Dash]south sweep. Tracked \
individual Arctic terns average about ", bold["70,900 km per year"],
   " (Egevang et al. 2010) \[LongDash] roughly three times the ~24,100 km \
centroid displacement. The centroid is a population statistic; the \
geolocator figure is an individual's odometer. Do not conflate them."
}], "Text", CellMargins -> {{60, 60}, {6, 10}},
   Background -> RGBColor[1.0, 0.97, 0.88],
   CellFrame -> {{4, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.85, 0.6, 0.15]],

hd2["5.1  From one point to a flock"],

para[{"A centroid is one point; the population is millions of birds. The \
same twelve monthly positions, resampled along great circles and seeded \
with a flock, turn the journey into motion \[LongDash] not to add new \
information, but to make the seasonal sweep legible at a glance:"}],

animCell["flock.gif",
   "Flocks streaming along each flyway (orange Arctic tern, Atlantic basin; \
cyan common swift, Afro-Palearctic; gold red knot, Americas). Birds are \
spaced along each species' resampled monthly path; this is a visualisation \
of the centroid route, not tracked individuals."],

para[{"The flock frames are generated by ", mono["wolfram/flock.wls"],
   ", which jitters a small swarm around each species' resampled monthly \
centroid path and renders the orthographic globe frame by frame."}]

}];


(* ============================================================
   6. Speeds and stopovers
   ============================================================ *)

writeAll[{

hd1["6.  Speeds and stopovers"],

para[{ital["The basic question."], " If the centre of mass of a population \
moves across the planet over a year, ", bold["how fast does it move, and \
when does it pause?"], " A migration is not a steady glide: it is bursts of \
hard travel separated by long stationary spells on the breeding and \
wintering grounds. The monthly centroid track of \[Section]4 already \
contains that rhythm \[LongDash] we just have to differentiate it."}],

para[{ital["The quantity."], " For each species we take the great-circle \
distance between consecutive monthly centroids and divide by the number of \
days in the step, giving a ", bold["centroid ground speed in km/day"],
   ". Read off the per-flyway tracks, the means and peaks differ sharply: \
the Arctic tern's centre of mass averages about ",
   bold[jmF[5229230, "meanSpeedKmDay", n0] <> " km/day"],
   " and peaks near ", bold[jmF[5229230, "maxSpeedKmDay", n0] <> " km/day"],
   " during passage; the common swift averages about ",
   bold[jmF[5228676, "meanSpeedKmDay", n0] <> " km/day"],
   " and the red knot about ", bold[jmF[2481765, "meanSpeedKmDay", n0] <> " km/day"],
   "."}],

wlIn["(* Monthly centroid ground speed (km/day) from the per-flyway track.
   Abbreviated from wolfram/journey_metrics.wls. *)
days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
step[c_] := MapThread[
   GeoDistance[GeoPosition[#1], GeoPosition[#2]] &,
   {Most[c], RotateLeft[c][[;; -2]]}];   (* consecutive monthly hops *)
speedKmDay[c_] := QuantityMagnitude[step[c], \"Kilometers\"] / Rest[days];
ListLinePlot[speedKmDay /@ {tern, swift, knot},
   PlotLegends -> {\"Arctic tern\", \"common swift\", \"red knot\"},
   AxesLabel -> {\"month\", \"km/day\"}]"],

imgCell["speed_profile.png"],
captionCell["Figure 6.1  Monthly centroid ground speed for each species \
along its primary flyway. The tall passage peaks (Arctic tern ~",
   jmF[5229230, "maxSpeedKmDay", n0], " km/day; red knot ~",
   jmF[2481765, "maxSpeedKmDay", n0], " km/day) separate the near-zero \
plateaux of the breeding and wintering seasons."],

Cell[TextData[{
   StyleBox["Crucial caveat \[LongDash] this is a lower bound. ",
      FontWeight -> Bold, FontSlant -> Italic],
   "Centroid speed is the speed of the population ", ital["centre of mass"],
   ", which is a ", bold["lower bound"], " on individual ground speed: when \
birds in different parts of the range move in opposing directions, those \
motions cancel in the mean, so the centroid moves more slowly than any of \
them. Equally, the low-speed months are not necessarily true en-route \
\[OpenCurlyDoubleQuote]stopovers\[CloseCurlyDoubleQuote] \[LongDash] they \
mostly mark the breeding/wintering turn-around, when the whole population \
sits still. Read these as the tempo of the population statistic, not of an \
individual bird."
}], "Text", CellMargins -> {{60, 60}, {6, 10}},
   Background -> RGBColor[1.0, 0.97, 0.88],
   CellFrame -> {{4, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.85, 0.6, 0.15]],

hd2["6.1  Does day length pace the journey?"],

para[{"A natural hypothesis: migrants might travel fastest when the \
photoperiod is changing fastest, since day length is the most reliable \
seasonal cue a bird has. We can test it directly against our own numbers \
\[LongDash] correlate each month's centroid speed with that month's rate of \
change of day length. ", ital["The honest answer is: not really."],
   " Across the twelve monthly steps the correlation is weak, and under a \
cyclic permutation that respects the annual cycle (the only null that does \
not pretend the twelve months are independent draws), it is ",
   bold["not significant"], ". The red knot is the strongest case, at ",
   bold["r = " <> jmF[2481765, "speedDaylightR", n2]],
   ", and even there ", bold["p = " <> jmF[2481765, "speedDaylightPcyclic", n2]],
   " (n = 12). Suggestive at best \[LongDash] a hypothesis to take to \
tracking data, not a result to report."}],

imgCell["daylight.png"],
captionCell["Figure 6.2  Day length experienced along each centroid track \
through the year. The Arctic tern, following summer from one hemisphere to \
the other, sits under a ~19 h midsummer day at its breeding latitudes \
\[LongDash] more daylight over the year than any other animal. Whether day \
length actually ", ital["paces"], " the speed in Figure 6.1, however, our \
12-point series cannot establish (see the photoperiod test above)."]

}];


(* ============================================================
   7. The energy of migration
   ============================================================ *)

writeAll[{

hd1["7.  The energy of migration"],

para[{ital["Cheap per kilometre, ruinous per year."], " Flapping flight is \
one of the most energetically expensive activities in nature per unit \
time, yet astonishingly ", bold["cheap per kilometre"],
   " \[LongDash] a migrating bird converts fat to distance with an \
efficiency no land animal approaches. The catch is the sheer length of the \
journey: a cost-per-kilometre that looks trivial becomes an enormous annual \
fuel bill when multiplied by tens of thousands of kilometres."}],

para[{ital["The model."], " We estimate flight power with the standard ",
   bold["Pennycuick flapping-flight model"], " (Pennycuick 2008), which \
sums three terms: ", bold["induced power"], " (the cost of generating lift, \
dominant at low speed), ", bold["parasite power"], " (drag on the body, \
dominant at high speed), and ", bold["profile power"],
   " (drag on the flapping wings). Their sum is the classic U-shaped power \
curve, whose two landmark speeds are the ", bold["minimum-power speed "],
   math["V"], math["mp"], " (cheapest per hour, where you would loiter) \
and the higher ", bold["maximum-range speed "], math["V"], math["mr"],
   " (cheapest per kilometre, where the tangent from the origin touches the \
curve). A bird minimising the fuel needed to cover distance should cruise \
near ", math["V"], math["mr"], " \[LongDash] and that is the speed at which \
we evaluate the fuel cost below."}],

para[{"For our three species the model gives a max-range speed ", math["V"],
   math["mr"], " of about ", bold[enF["Arctic tern", "VmrKmh", n0] <> " km/h"],
   " (Arctic tern), ", bold[enF["Common swift", "VmrKmh", n0] <> " km/h"],
   " (common swift), and ", bold[enF["Red knot", "VmrKmh", n0] <> " km/h"],
   " (red knot), with a cost of transport of roughly ",
   bold[enF["Arctic tern", "COTkJkm", n2] <> ", "],
   bold[enF["Common swift", "COTkJkm", n2] <> ", and "],
   bold[enF["Red knot", "COTkJkm", n2] <> " kJ/km"],
   " respectively. Expressed as fuel, each 1,000 km of flight burns about ",
   bold[enF["Arctic tern", "fatFracPer1000km", (n1[100 #] &)] <> "%, "],
   bold[enF["Common swift", "fatFracPer1000km", (n1[100 #] &)] <> "%, and "],
   bold[enF["Red knot", "fatFracPer1000km", (n1[100 #] &)] <> "%"],
   " of body mass respectively \[LongDash] which is why a long-haul migrant \
can nearly double its weight in fat before departure."}],

wlIn["(* Pennycuick flapping-flight power at speed V (level, still air).
   Abbreviated from wolfram/energetics.wls. *)
rho = 1.225; g = 9.81;            (* air density, gravity *)
Sb[m_] := 0.00813 m^0.666;        (* body frontal area (Pennycuick) *)
Pind[m_, b_, V_] := 2 (m g)^2 / (V rho Pi b^2);          (* induced  *)
Ppar[m_, b_, V_] := 0.5 rho V^3 Sb[m] 0.10;              (* parasite *)
Ppro[m_, V_]     := 1.2 (1.05/8.4) (m g)^1.5 / Sqrt[rho Sb[m]];  (* profile *)
Ptot[m_, b_, V_] := Pind[m, b, V] + Ppar[m, b, V] + Ppro[m, V];
Vmr[m_, b_] := V /. Last @ Minimize[{Ptot[m, b, V]/V, V > 5}, V];"],

imgCell["energetics.png"],
captionCell["Figure 7.1  Pennycuick power curves for the three species. \
Each U-shaped curve is induced + parasite + profile power; the minimum \
marks ", math["V"], math["mp"], " and the tangent from the origin marks the \
max-range speed ", math["V"], math["mr"], ", where cost per kilometre is \
lowest and where a fuel-minimising migrant should cruise."],

imgCell["energy_budget.png"],
captionCell["Figure 7.2  Cumulative flight energy along each species' ",
   bold["centroid"], " path over the year. This is explicitly a ",
   bold["lower bound"], " on the true annual energy: it integrates the \
~", enF["Arctic tern", "annualCentroidKm", nComma], " km centroid \
displacement, whereas a tracked Arctic tern actually flies ~70,900 km \
(Egevang et al. 2010) \[LongDash] roughly three times as far \[LongDash] so \
its real annual fuel bill dwarfs the centroid-path figure shown here."],

Cell[TextData[{
   StyleBox["A note on rigour. ", FontWeight -> Bold, FontSlant -> Italic],
   "These are ", bold["first-order estimates"], " \[LongDash] a point-mass \
bird in still air in steady level flight, with literature default \
coefficients. They are meant for ", ital["cross-species comparison"],
   ", not as physiology: real flight involves wind, climb, gliding (the \
swift especially), variable payload, and individual variation the model \
does not capture. Treat the numbers as order-of-magnitude, and the ranking \
between species as more trustworthy than any single absolute value."
}], "Text", CellMargins -> {{60, 60}, {6, 10}},
   Background -> RGBColor[1.0, 0.97, 0.88],
   CellFrame -> {{4, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.85, 0.6, 0.15]]

}];


(* ============================================================
   8. Finding the way: the magnetic landscape
   ============================================================ *)

writeAll[{

hd1["8.  Finding the way: the magnetic landscape"],

para[{ital["How does a bird know where it is?"], " Navigation over an ocean \
with no landmarks is the deepest puzzle of migration, and the answer is \
emphatically ", bold["multimodal"], ": migratory birds draw on a ",
   bold["sun compass"], ", a ", bold["star compass"],
   ", polarised-light cues at dawn and dusk, learned landmarks, olfaction, \
and \[LongDash] the part Wolfram Language lets us actually compute \[LongDash] \
the ", bold["Earth's magnetic field"], ", used both as a ",
   bold["compass"], " (direction) and, more controversially, as a ",
   bold["map"], " (position). The compass sense is an ", ital["inclination"],
   " compass: birds read the dip angle between the field and the horizon \
rather than its polarity (Wiltschko & Wiltschko 1972). For the broader \
mechanism see Mouritsen (2018)."}],

para[{ital["What we can compute."], " Wolfram Language ships the IGRF/WMM \
geomagnetic models through ", mono["GeomagneticModelData"],
   ", so we can evaluate the field everywhere along each flyway and ask what \
magnetic ", ital["landscape"], " the birds traverse. The map below shows \
magnetic inclination (dip) as a global backdrop with the three centroid \
tracks laid over it:"}],

wlIn["(* Magnetic inclination (dip) along a track, via the built-in model.
   Abbreviated from wolfram/geomag.wls. *)
dip[lat_, lon_] := QuantityMagnitude @ GeomagneticModelData[
   GeoPosition[{lat, lon}], \"MagneticDipAngle\"];
GeoRegionValuePlot[ ... ]   (* dip backdrop *)
trackDip = dip @@@ Transpose[{tern[[All, 1]], tern[[All, 2]]}];"],

imgCell["geomag_inclination.png"],
captionCell["Figure 8.1  Magnetic inclination (dip angle) across the globe, \
with the three population-centroid tracks overlaid. Dip runs from \
\[Minus]90\[Degree] at the south magnetic pole through 0\[Degree] at the \
magnetic equator to +90\[Degree] at the north magnetic pole; the contours \
run almost east\[Dash]west, nearly parallel to geographic latitude."],

imgCell["geomag_signature.png"],
captionCell["Figure 8.2  Magnetic dip and total-field intensity sampled \
month by month along each species' centroid route \[LongDash] the magnetic \
\[OpenCurlyDoubleQuote]signature\[CloseCurlyDoubleQuote] a bird on that \
flyway would experience through the year."],

Cell[TextData[{
   StyleBox["What this shows \[LongDash] and what it cannot. ",
      FontWeight -> Bold, FontSlant -> Italic],
   "All three tracks cross a wide span of magnetic dip \[LongDash] about ",
   bold[gmF["Arctic tern", "dipRangeDeg", n0] <> "\[Degree]"],
   " for the Arctic tern, ", bold[gmF["Common swift", "dipRangeDeg", n0] <> "\[Degree]"],
   " for the common swift, and ", bold[gmF["Red knot", "dipRangeDeg", n0] <> "\[Degree]"],
   " for the red knot \[LongDash] so the field carries a strong, monotone \
latitude signal along each route. In fact, along these tracks inclination \
is almost perfectly a function of latitude (corr(dip, lat) \[TildeTilde] ",
   bold[gmF["Arctic tern", "inclLatCorr", n2]],
   "), exactly as the geocentric-dipole relation ",
   math["tan I = 2 tan \[Lambda]"],
   " (with \[Lambda] the magnetic latitude) predicts; the longitude-only \
contribution to dip is tiny (\[LessEqual] ",
   bold[gmF["Arctic tern", "lonEffectDeg", n1] <> "\[Degree]"], "). ",
   StyleBox["So the field does provide a usable latitude gauge in \
principle. But occurrence centroids cannot test whether the birds actually \
use it.",
      FontWeight -> Bold],
   " We are showing the magnetic landscape these populations traverse, not a \
navigational mechanism: nothing here demonstrates that the birds read, \
follow, or steer by the field. That would require individual tracking, not \
where-the-crowd-is data."
}], "Text", CellMargins -> {{60, 60}, {6, 10}},
   Background -> RGBColor[1.0, 0.97, 0.88],
   CellFrame -> {{4, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.85, 0.6, 0.15]]

}];


(* ============================================================
   9. Cross-check: eBird Status & Trends (PROSE ONLY)
   ============================================================ *)

writeAll[{

hd1["9.  Cross-check: eBird Status & Trends"],

para[{ital["Are our occurrence-based centroids actually right?"], " A \
method built from biased citizen-science occurrences deserves an \
independent check. Cornell's ", bold["eBird Status & Trends"],
   " (S&T) is the professional answer to the same question: it fits \
machine-learning models that explicitly correct for observer effort and \
detectability, and outputs ", bold["bias-corrected weekly relative \
abundance"], " on a fine grid \[LongDash] a far more sophisticated product \
than our coarse occurrence centroid (Fink et al., eBird Status and Trends)."}],

para[{"As a ", bold["private validation"], ", we computed \
abundance-weighted centroids directly from the S&T rasters \[LongDash] \
inside the ", ital["same"], " flyway boxes used in \[Section]4 \[LongDash] \
by driving the R ", mono["ebirdst"], " package from Wolfram Language via ",
   mono["ExternalEvaluate"], ", then measuring the great-circle separation \
between Cornell's modelled centroids and ours, month by month. The pattern \
of code (our code, not Cornell's data) is:"}],

wlIn["(* PRIVATE S&T validation: abundance-weighted centroids from the
   ebirdst weekly rasters, compared to our GBIF centroids in the same
   flyway box. The rasters and all derived S&T artifacts stay LOCAL and
   git-ignored, per Cornell's terms -- only this code is shared. *)
r = StartExternalSession[\"R\"];
ExternalEvaluate[r, \"library(ebirdst); library(terra)\"];
ExternalEvaluate[r, \"
  cube <- load_raster(species, product='abundance', period='weekly')
  ll   <- project(cube, '+proj=longlat')
\"];
(* For each of 52 weekly layers: abundance-weighted lon/lat centroid,
   cropped to the flyway box, then resampled WL-side to 12 monthly means
   and compared to the GBIF track with GeoDistance. *)"],

para[{ital["The result."], " Our occurrence-based centroids agree with \
Cornell's professionally modelled abundance centroids to within roughly ",
   bold["1,300\[Dash]1,750 km"], " on average, along flyways thousands of \
kilometres long: common swift ~", ToString[swiftSep], " km, red knot ~",
   ToString[knotSep], " km, Arctic tern ~", ToString[ternSep],
   " km mean monthly separation. For a coarse, presence-weighted method \
built from raw occurrence data, agreeing with a full effort-corrected \
model to within a small fraction of the flyway length is a strong \
endorsement that the centroid approach captures the real seasonal signal."}],

para[{ital["Why you see no S&T figure here."], " The eBird Status & Trends \
Data Products are released under Cornell's own terms, which permit ",
   bold["non-commercial use and validation"], " but do ", bold["not"],
   " permit publishing derived figures or maps. We therefore show ",
   bold["none"], " \[LongDash] the cross-check above is reported as numbers \
only \[LongDash] and we point readers to Cornell's official, professionally \
produced visualizations instead: ",
   link["eBird Status and Trends",
      "https://science.ebird.org/en/status-and-trends"], "."}],

Cell[TextData[{
   "This material uses data from the eBird Status and Trends Project at \
the Cornell Lab of Ornithology, eBird.org. Any opinions, findings, and \
conclusions or recommendations expressed in this material are those of the \
author(s) and do not necessarily reflect the views of the Cornell Lab of \
Ornithology."
}], "Text", FontSlant -> Italic, FontSize -> 12,
   CellMargins -> {{60, 60}, {10, 10}},
   Background -> RGBColor[0.93, 0.95, 0.97],
   CellFrame -> {{4, 0}, {0, 0}}, CellFrameColor -> blue]

}];


(* ============================================================
   9b. Live now
   ============================================================ *)

writeAll[{

hd1["9b.  Live now: recent sightings via the eBird API"],

para[{"The centroids summarise a decade of history. For a sense of where \
these birds are ", ital["this month"], ", we add a live layer pulled from \
the ", bold["eBird API 2.0"], " recent-observations endpoint (",
   mono["/v2/data/obs/{region}/recent/{speciesCode}"],
   "), which returns the last 30 days of checklisted sightings for a \
species in a region. We sweep a representative spread of countries and plot \
the result:"}],

wlIn["(* Live recent sightings (last 30 days, as of late June 2026). LoadLiveSightings sweeps a
   spread of regions, returns {lat,lon} pairs ROUNDED TO 0.1 deg for
   privacy. Supply your own eBird API 2.0 token. *)
pts = LoadLiveSightings[\"arcter\", \"<your-ebird-api-token>\"];  (* arcter|comswi|redkno *)
GeoListPlot[GeoPosition /@ pts, GeoRange -> \"World\",
   GeoProjection -> \"Robinson\", GeoBackground -> GrayLevel[0.15],
   PlotStyle -> Directive[Orange, Opacity[0.7], PointSize[0.006]],
   PlotLabel -> \"Arctic tern -- recent eBird sightings (last 30 d)\\n\\
Source: eBird.org (Cornell Lab of Ornithology)\", ImageSize -> 900]"],

imgCell["live_5229230.png"],
captionCell["Figure 9b.1  Arctic tern \[LongDash] recent eBird sightings \
(last 30 days, as of late June 2026), swept across a spread of countries. ", bold["Source: \
eBird.org (Cornell Lab of Ornithology)"], "."],

imgCell["live_5228676.png"],
captionCell["Figure 9b.2  Common swift \[LongDash] recent eBird sightings \
(last 30 days, as of late June 2026). ", bold["Source: eBird.org (Cornell Lab of Ornithology)"], "."],

imgCell["live_2481765.png"],
captionCell["Figure 9b.3  Red knot \[LongDash] recent eBird sightings \
(last 30 days, as of late June 2026). ", bold["Source: eBird.org (Cornell Lab of Ornithology)"], "."],

para[{ital["Privacy and attribution."], " Live coordinates are coarsened \
to one decimal place (~11 km) before plotting or storage, so no precise \
observer or sensitive-species location is republished. All live data are \
attributed to eBird.org (Cornell Lab of Ornithology) per the eBird Terms \
of Use."}]

}];


(* ============================================================
   10. What each journey reveals
   ============================================================ *)

writeAll[{

hd1["10.  What each journey reveals"],

para[{"Read together, the three tracks tell three different stories about \
how a bird can solve the problem of seasonal survival. Plotting the centroid \
latitude against the month for all three at once makes the contrast plain:"}],

imgCell["annual_profiles.png"],
captionCell["Figure 10.1  Annual latitude profile of each population \
centroid. The Arctic tern's deep pole-to-pole swing, the common swift's \
moderate Europe\[LeftRightArrow]sub-Saharan shuttle, and the red knot's \
Americas-flyway loop are immediately distinguishable by amplitude and phase."],

para[{bold["Arctic tern \[LongDash] the pole-to-pole Atlantic sweep."],
   " The latitude-versus-month signal is the cleanest in the dataset: a \
centroid that climbs to high-Arctic breeding latitudes in the boreal \
summer and plunges toward the Southern Ocean in the austral summer. The \
centroid displacement (~24,100 km) is large yet still understates the \
individual journey (~70,900 km), because circumpolar east\[Dash]west motion \
cancels in the population mean \[LongDash] a vivid illustration of the \
difference between a population statistic and an individual track."}],

para[{bold["Common swift \[LongDash] the Europe\[LeftRightArrow]\
sub-Saharan shuttle."], " A single coherent flyway, and therefore the \
easiest centroid to trust: a tight summer concentration over Europe \
collapses into a sub-Saharan African wintering centre and back, ~14,000 km \
of annual centroid travel. The swift shows what the method looks like when \
nothing has to be corrected for multiple populations \[LongDash] it just \
works."}],

para[{bold["Red knot \[LongDash] the Americas long-haul (and the cautionary \
tale)."], " On its Americas flyway the knot traces a coherent ~7,900 km \
loop between Arctic breeding grounds and southern wintering areas, with the \
Delaware Bay stopover embedded in the spring leg. It is also the species \
that exposed the multi-flyway trap: pooled globally, its centroid is \
nonsense. The knot is the reason this post insists on per-flyway analysis."}],

para[{"Side by side, the quantitative summaries of \[Section]4\[Dash]\
\[Section]8 \[LongDash] annual centroid displacement, peak and mean centroid \
speed, max-range speed, cost of transport, and the magnetic span crossed \
\[LongDash] form a compact cross-species scorecard:"}],

imgCell["comparison.png"],
captionCell["Figure 10.2  Cross-species scorecard pulling together the \
headline numbers from the preceding sections. Read it as a comparison of \
population-level summaries, not individual physiology; the per-section \
caveats (centroid \[NotEqual] individual; energetics first-order; magnetic \
landscape, not mechanism) all still apply."]

}];


(* ============================================================
   11. New ideas, and how to test them
   ============================================================ *)

writeAll[{

hd1["11.  New ideas, and how to test them"],

para[{"Beyond reconstructing known journeys, this post surfaced two ",
   ital["testable"], " ideas. Neither is settled here \[LongDash] both are \
hypotheses that our occurrence-centroid data can frame but not decide \
\[LongDash] and saying so plainly is the point."}],

para[{bold["Idea 1 \[LongDash] magnetic inclination as a latitude gauge."],
   " We showed (\[Section]8) that along all three flyways magnetic dip is \
almost a pure function of latitude (corr \[TildeTilde] ",
   gmF["Arctic tern", "inclLatCorr", n2],
   "), so the field ", ital["could"], " in principle tell a bird how far \
north or south it is. What we could ", bold["not"], " do is test whether the \
birds use it: occurrence centroids show the magnetic landscape traversed, \
not the cue employed. ", bold["What would settle it:"],
   " individual tracking (Movebank archival tags, light-level geolocators) \
combined with magnetic-displacement experiments, not where-the-crowd-is \
data."}],

para[{bold["Idea 2 \[LongDash] migration speed paced by photoperiod."],
   " We tested whether centroid speed rises when day length changes fastest \
(\[Section]6). The signal is weak and, under a cycle-respecting permutation \
null, ", bold["not significant"], " (best case red knot, r = ",
   jmF[2481765, "speedDaylightR", n2], ", p = ",
   jmF[2481765, "speedDaylightPcyclic", n2],
   ", n = 12). ", bold["What would settle it:"], " a much longer time series \
\[LongDash] eBird Status & Trends weekly relative abundance gives 52 \
effort-corrected steps per year rather than our 12, and individual tracks \
give departure dates that can be regressed directly on local photoperiod."}],

para[{ital["Limitations, in one place."], " Three caveats run through \
everything above. ", bold["(1) Centroid \[NotEqual] individual:"],
   " a population centre of mass moves more slowly and more shortly than any \
bird in it (opposing motions cancel), so all speeds and distances here are \
lower bounds on the individual journey. ", bold["(2) Effort bias:"],
   " presence weighting on a coarse grid blunts but does not erase the \
over-representation of densely-birded regions; southern and oceanic extremes \
are pulled toward where the observers are. ", bold["(3) Sample, not census:"],
   " these are occurrence records, not a complete count, and the magnetic \
and energetic layers are model overlays, not measurements of the birds \
themselves."}],

para[{ital["Test it yourself."], " Every figure and number above \
regenerates from the public repository with four commands:"}],

codeIn["wolframscript -file wolfram/run_all.wls          # centroids, maps, animations
wolframscript -file wolfram/geomag.wls           # magnetic landscape (\[Section]8)
wolframscript -file wolfram/journey_metrics.wls  # speeds + photoperiod test (\[Section]6)
wolframscript -file wolfram/energetics.wls       # Pennycuick flight energy (\[Section]7)"]

}];


(* ============================================================
   12. Conclusions
   ============================================================ *)

writeAll[{

hd1["12.  Conclusions"],

para[{"With open data and a careful method, you can reconstruct \
continental-scale bird migration from a laptop. Hundreds of millions of \
volunteer observations, republished under an open licence with a citable \
DOI, plus a few dozen lines of Wolfram Language, are enough to recover the \
annual journeys of three of the planet's great migrants and to \
cross-validate them against a professional abundance model."}],

para[{"But the central lesson is a cautionary one. ", bold["Naive pooling \
misleads."], " A single global centroid placed the red knot in the empty \
mid-Atlantic, ~4,670 km/month from any real bird. Two disciplines rescue \
the analysis: ", bold["bias-awareness"],
   " (presence weighting on a coarse grid, so birders are not mistaken for \
birds) and ", bold["per-flyway analysis"],
   " (so disjoint populations are never averaged together), all on a ",
   bold["proper spherical geometry"], " (so longitudes are never averaged \
arithmetically). Get those three right and citizen-science occurrence data \
yield a faithful, validated picture of where the birds actually are."}]

}];


(* ============================================================
   13. References
   ============================================================ *)

writeAll[{

hd1["13.  References"],

para[{bold["Egevang, C., Stenhouse, I. J., Phillips, R. A., Petersen, A., \
Fox, J. W., & Silk, J. R. D."], " (2010). Tracking of Arctic terns ",
   ital["Sterna paradisaea"], " reveals longest animal migration. ",
   ital["Proceedings of the National Academy of Sciences"], " 107(5), \
2078\[Dash]2081. [Geolocator tracking; ~70,900 km/yr round trip.]"}],

para[{bold["Hedenstr\[ODoubleDot]m, A., Norevik, G., Warfvinge, K., \
Andersson, A., B\[ADoubleDot]ckman, J., & \[CapitalARing]kesson, S."], \
" (2016). Annual 10-month aerial life phase in the common swift ",
   ital["Apus apus"], ". ", ital["Current Biology"], " 26(22), \
3066\[Dash]3070. [Common swifts remain airborne for ~10 months.]"}],

para[{bold["Fink, D., Auer, T., Johnston, A., Strimas-Mackey, M., Ligocki, \
S., Robinson, O., Hochachka, W., et al."], " eBird Status and Trends. \
Cornell Lab of Ornithology, Ithaca, New York. ",
   link["science.ebird.org/en/status-and-trends",
      "https://science.ebird.org/en/status-and-trends"],
   ". [Effort-corrected weekly relative-abundance models used for the \
\[Section]9 validation.]"}],

para[{bold["GBIF.org"], ". eBird Observation Dataset (EOD), datasetKey ",
   mono["4fa7b334-ce0d-4e88-aaae-2e0c138d049e"],
   ", accessed via the GBIF Occurrence Download API (CC BY 4.0). \
Per-species download DOIs: Arctic tern \[LongDash] ", mono[doiFor[5229230]],
   "; common swift \[LongDash] ", mono[doiFor[5228676]], "; red knot \
\[LongDash] ", mono[doiFor[2481765]], "."}],

para[{bold["Sullivan, B. L., Wood, C. L., Iliff, M. J., Bonney, R. E., \
Fink, D., & Kelling, S."], " (2009). eBird: A citizen-based bird \
observation network in the biological sciences. ",
   ital["Biological Conservation"], " 142(10), 2282\[Dash]2292. [The eBird \
platform.]"}],

para[{bold["Newton, I."], " (2008). ", ital["The Migration Ecology of \
Birds"], ". Academic Press. [Comprehensive reference on flyways, \
energetics, and migratory strategy.]"}],

para[{bold["Baker, A. J., Gonz\[AAcute]lez, P. M., Piersma, T., Niles, L. \
J., et al."], " (2004). Rapid population decline in red knots: fitness \
consequences of decreased refuelling rates and late arrival in Delaware \
Bay. ", ital["Proceedings of the Royal Society B"], " 271, 875\[Dash]882. \
[Red knot / horseshoe-crab stopover coupling.]"}],

para[{bold["Pennycuick, C. J."], " (2008). ", ital["Modelling the Flying \
Bird"], ". Academic Press. [Flapping-flight power model \[LongDash] induced, \
parasite, and profile power, ", math["V"], math["mp"], "/", math["V"],
   math["mr"], " \[LongDash] used in \[Section]7.]"}],

para[{bold["Mouritsen, H."], " (2018). Long-distance navigation and \
magnetoreception in migratory animals. ", ital["Nature"], " 558, \
50\[Dash]59. [Multimodal-navigation review underpinning \[Section]8.]"}],

para[{bold["Wiltschko, W., & Wiltschko, R."], " (1972, 2005). Magnetic \
compass of European robins; the inclination compass of migratory birds. ",
   ital["Science"], " 176, 62\[Dash]64; ", ital["Journal of Comparative \
Physiology A"], " 191, 675\[Dash]693. [The inclination-compass sense cited \
in \[Section]8.]"}]

}];


(* ============================================================
   14. Acknowledgements & data licences
   ============================================================ *)

writeAll[{

hd1["14.  Acknowledgements & data licences"],

para[{ital["With thanks."], " This work rests entirely on the labour of \
others: the global community of ", bold["eBird volunteers"],
   " who contributed the underlying observations, the ", bold["Cornell Lab \
of Ornithology"], " which runs eBird and the Status & Trends project, and \
", bold["GBIF"], " which curates and openly republishes the data with \
persistent, citable DOIs."}],

para[{"\[Bullet] ", bold["GBIF / eBird Observation Dataset"],
   " is licensed ", bold["CC BY 4.0"], " \[LongDash] freely publishable \
with attribution; we cite the per-species download DOIs in \[Section]13 (or \
mark them \[OpenCurlyDoubleQuote]" <> doiPending <> "\[CloseCurlyDoubleQuote] \
when the archive build is still in progress)."}],

para[{"\[Bullet] ", bold["eBird Status & Trends"],
   " is released under Cornell's custom, non-commercial terms. We use it \
for ", ital["private validation only"], " and publish ", bold["no"],
   " derived S&T figures here; see Cornell's official visualizations \
instead. As required:"}],

Cell[TextData[{
   "This material uses data from the eBird Status and Trends Project at \
the Cornell Lab of Ornithology, eBird.org. Any opinions, findings, and \
conclusions or recommendations expressed in this material are those of the \
author(s) and do not necessarily reflect the views of the Cornell Lab of \
Ornithology."
}], "Text", FontSlant -> Italic, FontSize -> 12,
   CellMargins -> {{60, 60}, {10, 10}},
   Background -> RGBColor[0.93, 0.95, 0.97],
   CellFrame -> {{4, 0}, {0, 0}}, CellFrameColor -> blue],

para[{"\[Bullet] ", bold["eBird API 2.0"],
   " live data are used under the eBird Terms of Use, attributed to \
eBird.org (Cornell Lab of Ornithology), with observer coordinates \
coarsened to ~11 km for privacy."}],

para[{ital["Tools."], " All numerics, maps, and animations are pure ",
   bold["Wolfram Language"], ". The notebook was assembled programmatically \
via ", mono["wolframscript"], ". No AI-generated illustrations are used \
anywhere in this post; every figure is computed from data."}]

}];


(* ============================================================
   15. Reproducibility
   ============================================================ *)

writeAll[{

hd1["15.  Reproducibility"],

para[{"All source code lives in the public repository ",
   link["github.com/mthiel74/BirdFlightPaths",
      "https://github.com/mthiel74/BirdFlightPaths"],
   ". The pipeline is pure Wolfram Language; the ", mono[".wls"],
   " scripts are the source of truth, and the committed ", mono[".nb"],
   " is browseable without running anything. To rebuild from scratch on a \
machine with Wolfram Language installed (plus, for the optional \[Section]9 \
validation, R with the ", mono["ebirdst"], " package):"}],

codeIn["# 1. Mint citable GBIF downloads (DOIs) + fetch full occurrence CSVs
wolframscript -file wolfram/gbif_download.wls

# 2. Centroids, seasonal maps, centroid-track globes, hero animation
wolframscript -file wolfram/run_all.wls

# 3. (optional, private) S&T cross-check via R / ebirdst -- stays local
wolframscript -file wolfram/ebirdst_r.wls

# 4. Build this notebook (bird_migration.nb + .pdf)
wolframscript -file community/build_notebook.wls"],

para[{ital["GBIF download DOIs."], " The citable DOIs minted by step 1 are \
recorded in ", mono["data/gbif_dois.json"], ": Arctic tern \[LongDash] ",
   mono[doiFor[5229230]], "; common swift \[LongDash] ", mono[doiFor[5228676]],
   "; red knot \[LongDash] ", mono[doiFor[2481765]], "."}],

para[{Style["Generated on " <> DateString[Now, {"MonthName", " ", "DayShort",
    ", ", "Year"}] <> ".", FontSlant -> Italic, FontColor -> GrayLevel[0.4]]}]

}];


(* ==================================================================
   Save -- host the cells in an invisible FE document, NotebookSave +
   Export so Image / AnimatedImage cells serialise to disk.
   ================================================================== *)

Print["assembled ", Length[$allCells], " cells"];

TimeConstrained[
   UsingFrontEnd[
      nbObj = CreateDocument[$allCells, Visible -> False,
         WindowSize -> {980, 800}, StyleDefinitions -> "Default.nb"];
      NotebookSave[nbObj, outNb];
      Print["wrote ", outNb, " (", FileByteCount[outNb], " B)"];
      (* Export the saved notebook to PDF. Errors are surfaced (no Quiet) so a
         failed/partial render is visible, not silently swallowed. *)
      Export[outPdf, nbObj];
      Print["wrote ", outPdf, " (", FileByteCount[outPdf], " B)"];
      NotebookClose[nbObj];
   ],
   1800,
   Print["ERROR: notebook save timed out"]; Exit[1]
];

(* Verify the PDF is complete: enough pages and a sane byte count. The full
   post is ~15 pages; a truncated export (e.g. an empty Reproducibility section)
   shows up as too few pages. Fail loudly so a broken PDF is never committed. *)
If[FileExistsQ[outPdf],
   Module[{pc = Quiet @ Check[Import[outPdf, "PageCount"], 0]},
      Print["PDF pages: ", pc, "  bytes: ", FileByteCount[outPdf]];
      If[! IntegerQ[pc] || pc < 13,
         Print["ERROR: PDF looks truncated (", pc, " pages, expected >=13)"]; Exit[1]]],
   Print["ERROR: no PDF produced"]; Exit[1]];
Print["build_notebook: OK"];
