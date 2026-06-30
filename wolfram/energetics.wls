#!/usr/bin/env wolframscript
(* energetics.wls — the cost of migration (Pennycuick flight mechanics).

   For each species we estimate, from body mass m and wingspan b:
     - minimum-power airspeed Vmp                                        [item 10]
     - mechanical + chemical flight power, cost of transport (J/km)      [item 10]
     - fuel: fat mass per 1000 km and as a fraction of body mass         [item 11]
     - an energy budget along the year (COT x monthly centroid distance) [item 12]

   Aerodynamic power for level flapping flight (Pennycuick 2008,
   "Modelling the Flying Bird"):
     induced   P_ind(V) = 2 k (m g)^2 / (rho V pi b^2)
     parasite  P_par(V) = 1/2 rho V^3 S_b C_Db ,  S_b = 0.00813 m^0.666
     profile   P_pro    ~ X1 * P_am   (X1 = 1.2, P_am = min of P_ind+P_par)
   Minimum-power speed (analytic): Vmp = (A/(3B))^(1/4),
     A = 2 k (m g)^2/(rho pi b^2),  B = 1/2 rho S_b C_Db.
   Chemical power P_chem = P_mech/eta + BMR, eta = 0.23 (muscle efficiency),
     BMR = 3.79 m^0.723 W.  Fat energy density e_fat = 3.93e7 J/kg.

   These are first-order estimates (point masses, level flight, no wind), meant
   for cross-species comparison, not precise physiology. Outputs:
   docs/images/energetics.png, docs/images/energy_budget.png,
   data/energetics.json. Pure Wolfram Language. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
img = FileNameJoin[{$repoRoot, "docs", "images"}];

g = 9.81; rho = 1.23; kInd = 1.2; cDb = 0.10; x1 = 1.2; eta = 0.23; eFat = 3.93*^7;

(* per-species morphology (kg, m) from the literature; knot uses a lean body mass *)
morph = <|
  5229230 -> <|"name" -> "Arctic tern",  "m" -> 0.110, "b" -> 0.79|>,
  5228676 -> <|"name" -> "Common swift", "m" -> 0.040, "b" -> 0.42|>,
  2481765 -> <|"name" -> "Red knot",     "m" -> 0.135, "b" -> 0.57|>|>;
cols = <|5229230 -> RGBColor[1, 0.4, 0.25], 5228676 -> RGBColor[0.35, 0.9, 1.0],
         2481765 -> RGBColor[0.9, 0.7, 0.1]|>;
keys = {5229230, 5228676, 2481765};

(* Cost of transport is minimised at the MAXIMUM-RANGE speed Vmr, NOT at the
   minimum-power speed Vmp. Migrants fly near Vmr to minimise fuel per distance
   (Pennycuick / flight-range theory), so all fuel/COT metrics are evaluated at
   Vmr; Vmp is reported only as the airspeed of minimum power. *)
flight[m_, b_] := Module[{Sb, A, B, Vmp, Pam, Ppro, bmr, Pchem, cot, Vmr, cotMr, V},
  Sb = 0.00813 m^0.666;
  A = 2 kInd (m g)^2/(rho Pi b^2);          (* P_ind = A / V        *)
  B = 0.5 rho Sb cDb;                        (* P_par = B V^3        *)
  Vmp = (A/(3 B))^(1/4);
  Pam = A/Vmp + B Vmp^3;                      (* absolute minimum aerodynamic power *)
  Ppro = x1 Pam;                             (* profile power ~ constant in V        *)
  bmr = 3.79 m^0.723;
  Pchem[v_] := (A/v + B v^3 + Ppro)/eta + bmr;
  cot[v_] := Pchem[v]/v;                      (* J per metre at airspeed v           *)
  Vmr = v /. Last@FindMinimum[{cot[v], 5 < v < 100}, {v, 1.6 Vmp}];
  cotMr = cot[Vmr];
  <|"Vmp" -> Vmp, "Vmr" -> Vmr, "PchemMr" -> Pchem[Vmr], "COTJkm" -> cotMr*1000,
    "fatPer1000km" -> cotMr*1.0*^6/eFat,     (* kg fat per 1000 km at Vmr            *)
    "fatFracPer1000km" -> cotMr*1.0*^6/eFat/m|>];

(* path length per species (km) from path_lengths.csv, primary track *)
pl = Rest@Import[FileNameJoin[{$repoRoot, "data", "path_lengths.csv"}], "CSV"];
primKm[key_] := SelectFirst[pl, #[[1]] == key && ! StringContainsQ[ToString[#[[3]]], "global"] &][[4]];

enr = Association @ Table[
   With[{f = flight[morph[k]["m"], morph[k]["b"]], dkm = primKm[k]},
     k -> Join[<|"name" -> morph[k]["name"], "m_kg" -> morph[k]["m"], "b_m" -> morph[k]["b"],
        "VmpKmh" -> Round[f["Vmp"]*3.6, 0.1], "VmrKmh" -> Round[f["Vmr"]*3.6, 0.1],
        "PchemW" -> Round[f["PchemMr"], 0.01],
        "COTkJkm" -> Round[f["COTJkm"]/1000, 0.01],
        "fatFracPer1000km" -> Round[f["fatFracPer1000km"], 0.001],
        "annualCentroidKm" -> Round[dkm],
        "annualFlightMJ" -> Round[f["COTJkm"]*dkm/1.0*^6, 0.1]|>]], {k, keys}];

(* ---------- item 10/11: comparison dashboard ---------- *)
metricBar[prop_, lab_] := BarChart[enr[#][prop] & /@ keys,
   ChartLabels -> (morph[#]["name"] & /@ keys), ChartStyle -> (cols /@ keys),
   PlotLabel -> Style[lab, 12], ImageSize -> 300, LabelingFunction -> Above];
dash = Grid[{{metricBar["VmrKmh", "max-range cruising airspeed (km/h)"],
              metricBar["COTkJkm", "cost of transport at Vmr (kJ/km)"]},
             {metricBar["fatFracPer1000km", "fat fraction burned / 1000 km"],
              metricBar["annualFlightMJ", "annual flight energy (MJ, centroid path)"]}},
   Spacings -> {1, 1}];
Export[FileNameJoin[{img, "energetics.png"}], dash, "PNG", ImageResolution -> 130];
Print["wrote energetics.png"];

(* ---------- item 12: cumulative energy budget along the route ---------- *)
loadTrack[key_] := Select[Rest@Import[FileNameJoin[{$repoRoot, "data",
   "centroids_" <> ToString[key] <> ".csv"}], "CSV"], NumberQ[#[[2]]] && NumberQ[#[[3]]] &];
budget[key_] := Module[{tr = loadTrack[key], steps, cot, cum},
  steps = Table[QuantityMagnitude@UnitConvert[GeoDistance[{tr[[i,2]],tr[[i,3]]},
     {tr[[Mod[i,12]+1,2]],tr[[Mod[i,12]+1,3]]}], "Kilometers"], {i, 12}];
  cot = enr[key]["COTkJkm"];                       (* kJ/km *)
  cum = Accumulate[steps cot]/1000.;             (* MJ cumulative *)
  Transpose[{Range[12], cum}]];
budFig = ListLinePlot[budget /@ keys, PlotStyle -> (cols /@ keys), Mesh -> All,
   PlotLegends -> (morph[#]["name"] & /@ keys), Frame -> True,
   FrameLabel -> {"month", "cumulative flight energy (MJ)"},
   PlotLabel -> Style["Energy budget along the centroid path (lower bound on the real journey)", 13],
   GridLines -> {Range[12], Automatic}, ImageSize -> 900];
Export[FileNameJoin[{img, "energy_budget.png"}], budFig, "PNG", ImageResolution -> 130];
Print["wrote energy_budget.png"];

Export[FileNameJoin[{$repoRoot, "data", "energetics.json"}], Values[enr], "RawJSON"];
Do[Print["  ", enr[k]["name"], ": Vmp ", enr[k]["VmpKmh"], " / Vmr ", enr[k]["VmrKmh"],
   " km/h, COT@Vmr ", enr[k]["COTkJkm"], " kJ/km, fat ",
   Round[100 enr[k]["fatFracPer1000km"]], "%/1000km, annual ",
   enr[k]["annualFlightMJ"], " MJ"], {k, keys}];
Print["energetics: OK"];
