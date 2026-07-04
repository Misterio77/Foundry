# DynamicScheme + MaterialDynamicColors role layer (brick 4), ported from
# material-colors 0.4.2 for the rainbow scheme at standard contrast (the
# config's settings). Rainbow is neither monochrome nor fidelity, so those
# branches collapse to the default case.
{lib}: let
  h = import ./hct.nix {inherit lib;};
  m = import ./math.nix {inherit lib;};
  p = import ./palettes.nix {inherit lib;};
  inherit (h) yFromLstar lstarFromY;
  inherit (builtins) floor;
  abs = m.abs;

  clamp = lo: hi: x:
    if x < lo
    then lo
    else if x > hi
    then hi
    else x;
  round = x: floor (x + 0.5);
  lerp = a: b: t: (1.0 - t) * a + t * b;
  maxf = a: b:
    if a > b
    then a
    else b;
  minf = a: b:
    if a < b
    then a
    else b;
  between = lo: hi: x: x >= lo && x < hi;

  # --- contrast ---
  ratioOfYs = y1: y2: let
    li = maxf y1 y2;
    dk = minf y1 y2;
  in (li + 5.0) / (dk + 5.0);
  ratioOfTones = a: b: ratioOfYs (yFromLstar (clamp 0.0 100.0 a)) (yFromLstar (clamp 0.0 100.0 b));
  lighter = tone: ratio:
    if !(between 0.0 100.01 tone)
    then -1.0
    else let
      darkY = yFromLstar tone;
      lightY = ratio * (darkY + 5.0) - 5.0;
      rc = ratioOfYs lightY darkY;
      d = abs (rc - ratio);
    in
      if rc < ratio && d > 0.04
      then -1.0
      else let rv = lstarFromY lightY + 0.4; in
        if rv < 0.0 || rv > 100.0
        then -1.0
        else rv;
  darker = tone: ratio:
    if !(between 0.0 100.01 tone)
    then -1.0
    else let
      lightY = yFromLstar tone;
      darkY = (lightY + 5.0) / ratio - 5.0;
      rc = ratioOfYs lightY darkY;
      d = abs (rc - ratio);
    in
      if rc < ratio && d > 0.04
      then -1.0
      else let rv = lstarFromY darkY - 0.4; in
        if rv < 0.0 || rv > 100.0
        then -1.0
        else rv;
  lighterUnsafe = tone: ratio: let x = lighter tone ratio; in
    if x < 0.0
    then 100.0
    else x;
  darkerUnsafe = tone: ratio: let x = darker tone ratio; in
    if x < 0.0
    then 0.0
    else x;
  tonePrefersLight = tone: (round tone) < 60.0;
  toneAllowsLight = tone: (round tone) <= 49.0;
  foregroundTone = bgTone: ratio: let
    lt = lighterUnsafe bgTone ratio;
    dt = darkerUnsafe bgTone ratio;
    lr = ratioOfTones lt bgTone;
    dr = ratioOfTones dt bgTone;
  in
    if tonePrefersLight bgTone
    then
      if lr >= ratio || lr >= dr || (abs (lr - dr) < 0.1 && lr < ratio && dr < ratio)
      then lt
      else dt
    else if dr >= ratio || dr >= lr
    then dt
    else lt;

  ccGet = cc: cl:
    if cl <= -1.0
    then cc.low
    else if cl < 0.0
    then lerp cc.low cc.normal (cl + 1.0)
    else if cl < 0.5
    then lerp cc.normal cc.medium (cl / 0.5)
    else if cl < 1.0
    then lerp cc.medium cc.high ((cl - 0.5) / 0.5)
    else cc.high;
  cc = low: normal: medium: high: {inherit low normal medium high;};

  # --- role table (rec: roles reference each other) ---
  highestSurface = s:
    if s.isDark
    then roles.surface_bright
    else roles.surface_dim;
  # defaults keep every role total: null background/curve/pair unless set
  R = attrs:
    {
      isBackground = false;
      background = null;
      secondBackground = null;
      contrastCurve = null;
      toneDeltaPair = null;
    }
    // attrs;
  tdp = subject: basis: delta: polarity: stayTogether: _: {inherit subject basis delta polarity stayTogether;};

  roles = rec {
    background = R {name = "background"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then 6.0 else 98.0;};
    on_background = R {name = "on_background"; palette = "neutral"; tone = s: if s.isDark then 90.0 else 10.0; background = _: background; contrastCurve = cc 3.0 3.0 4.5 7.0;};
    surface = R {name = "surface"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then 6.0 else 98.0;};
    surface_dim = R {name = "surface_dim"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then 6.0 else ccGet (cc 87.0 87.0 80.0 75.0) s.contrastLevel;};
    surface_bright = R {name = "surface_bright"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then ccGet (cc 24.0 24.0 29.0 34.0) s.contrastLevel else 98.0;};
    surface_container_lowest = R {name = "surface_container_lowest"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then ccGet (cc 4.0 4.0 2.0 0.0) s.contrastLevel else 100.0;};
    surface_container_low = R {name = "surface_container_low"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then ccGet (cc 10.0 10.0 11.0 12.0) s.contrastLevel else ccGet (cc 96.0 96.0 96.0 95.0) s.contrastLevel;};
    surface_container = R {name = "surface_container"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then ccGet (cc 12.0 12.0 16.0 20.0) s.contrastLevel else ccGet (cc 94.0 94.0 92.0 90.0) s.contrastLevel;};
    surface_container_high = R {name = "surface_container_high"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then ccGet (cc 17.0 17.0 21.0 25.0) s.contrastLevel else ccGet (cc 92.0 92.0 88.0 85.0) s.contrastLevel;};
    surface_container_highest = R {name = "surface_container_highest"; palette = "neutral"; isBackground = true; tone = s: if s.isDark then ccGet (cc 22.0 22.0 26.0 30.0) s.contrastLevel else ccGet (cc 90.0 90.0 84.0 80.0) s.contrastLevel;};
    on_surface = R {name = "on_surface"; palette = "neutral"; tone = s: if s.isDark then 90.0 else 10.0; background = highestSurface; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    surface_variant = R {name = "surface_variant"; palette = "neutral_variant"; isBackground = true; tone = s: if s.isDark then 30.0 else 90.0;};
    on_surface_variant = R {name = "on_surface_variant"; palette = "neutral_variant"; tone = s: if s.isDark then 80.0 else 30.0; background = highestSurface; contrastCurve = cc 3.0 4.5 7.0 11.0;};
    inverse_surface = R {name = "inverse_surface"; palette = "neutral"; tone = s: if s.isDark then 90.0 else 20.0;};
    inverse_on_surface = R {name = "inverse_on_surface"; palette = "neutral"; tone = s: if s.isDark then 20.0 else 95.0; background = _: inverse_surface; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    outline = R {name = "outline"; palette = "neutral_variant"; tone = s: if s.isDark then 60.0 else 50.0; background = highestSurface; contrastCurve = cc 1.5 3.0 4.5 7.0;};
    outline_variant = R {name = "outline_variant"; palette = "neutral_variant"; tone = s: if s.isDark then 30.0 else 80.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5;};
    shadow = R {name = "shadow"; palette = "neutral"; tone = _: 0.0;};
    scrim = R {name = "scrim"; palette = "neutral"; tone = _: 0.0;};
    surface_tint = R {name = "surface_tint"; palette = "primary"; isBackground = true; tone = s: if s.isDark then 80.0 else 40.0;};

    primary = R {name = "primary"; palette = "primary"; isBackground = true; tone = s: if s.isDark then 80.0 else 40.0; background = highestSurface; contrastCurve = cc 3.0 4.5 7.0 7.0; toneDeltaPair = tdp primary_container primary 10.0 "Nearer" false;};
    on_primary = R {name = "on_primary"; palette = "primary"; tone = s: if s.isDark then 20.0 else 100.0; background = _: primary; contrastCurve = cc 3.0 7.0 11.0 21.0;};
    primary_container = R {name = "primary_container"; palette = "primary"; isBackground = true; tone = s: if s.isDark then 30.0 else 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp primary_container primary 10.0 "Nearer" false;};
    on_primary_container = R {name = "on_primary_container"; palette = "primary"; tone = s: if s.isDark then 90.0 else 10.0; background = _: primary_container; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    inverse_primary = R {name = "inverse_primary"; palette = "primary"; tone = s: if s.isDark then 40.0 else 80.0; background = _: inverse_surface; contrastCurve = cc 3.0 4.5 7.0 7.0;};

    secondary = R {name = "secondary"; palette = "secondary"; isBackground = true; tone = s: if s.isDark then 80.0 else 40.0; background = highestSurface; contrastCurve = cc 3.0 4.5 7.0 7.0; toneDeltaPair = tdp secondary_container secondary 10.0 "Nearer" false;};
    on_secondary = R {name = "on_secondary"; palette = "secondary"; tone = s: if s.isDark then 20.0 else 100.0; background = _: secondary; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    secondary_container = R {name = "secondary_container"; palette = "secondary"; isBackground = true; tone = s: if s.isDark then 30.0 else 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp secondary_container secondary 10.0 "Nearer" false;};
    on_secondary_container = R {name = "on_secondary_container"; palette = "secondary"; tone = s: if s.isDark then 90.0 else 10.0; background = _: secondary_container; contrastCurve = cc 4.5 7.0 11.0 21.0;};

    tertiary = R {name = "tertiary"; palette = "tertiary"; isBackground = true; tone = s: if s.isDark then 80.0 else 40.0; background = highestSurface; contrastCurve = cc 3.0 4.5 7.0 7.0; toneDeltaPair = tdp tertiary_container tertiary 10.0 "Nearer" false;};
    on_tertiary = R {name = "on_tertiary"; palette = "tertiary"; tone = s: if s.isDark then 20.0 else 100.0; background = _: tertiary; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    tertiary_container = R {name = "tertiary_container"; palette = "tertiary"; isBackground = true; tone = s: if s.isDark then 30.0 else 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp tertiary_container tertiary 10.0 "Nearer" false;};
    on_tertiary_container = R {name = "on_tertiary_container"; palette = "tertiary"; tone = s: if s.isDark then 90.0 else 10.0; background = _: tertiary_container; contrastCurve = cc 4.5 7.0 11.0 21.0;};

    error = R {name = "error"; palette = "error"; isBackground = true; tone = s: if s.isDark then 80.0 else 40.0; background = highestSurface; contrastCurve = cc 3.0 4.5 7.0 7.0; toneDeltaPair = tdp error_container error 10.0 "Nearer" false;};
    on_error = R {name = "on_error"; palette = "error"; tone = s: if s.isDark then 20.0 else 100.0; background = _: error; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    error_container = R {name = "error_container"; palette = "error"; isBackground = true; tone = s: if s.isDark then 30.0 else 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp error_container error 10.0 "Nearer" false;};
    on_error_container = R {name = "on_error_container"; palette = "error"; tone = s: if s.isDark then 90.0 else 10.0; background = _: error_container; contrastCurve = cc 4.5 7.0 11.0 21.0;};

    primary_fixed = R {name = "primary_fixed"; palette = "primary"; isBackground = true; tone = _: 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp primary_fixed primary_fixed_dim 10.0 "Lighter" true;};
    primary_fixed_dim = R {name = "primary_fixed_dim"; palette = "primary"; isBackground = true; tone = _: 80.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp primary_fixed primary_fixed_dim 10.0 "Lighter" true;};
    on_primary_fixed = R {name = "on_primary_fixed"; palette = "primary"; tone = _: 10.0; background = _: primary_fixed_dim; secondBackground = _: primary_fixed; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    on_primary_fixed_variant = R {name = "on_primary_fixed_variant"; palette = "primary"; tone = _: 30.0; background = _: primary_fixed_dim; secondBackground = _: primary_fixed; contrastCurve = cc 3.0 4.5 7.0 11.0;};

    secondary_fixed = R {name = "secondary_fixed"; palette = "secondary"; isBackground = true; tone = _: 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp secondary_fixed secondary_fixed_dim 10.0 "Lighter" true;};
    secondary_fixed_dim = R {name = "secondary_fixed_dim"; palette = "secondary"; isBackground = true; tone = _: 80.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp secondary_fixed secondary_fixed_dim 10.0 "Lighter" true;};
    on_secondary_fixed = R {name = "on_secondary_fixed"; palette = "secondary"; tone = _: 10.0; background = _: secondary_fixed_dim; secondBackground = _: secondary_fixed; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    on_secondary_fixed_variant = R {name = "on_secondary_fixed_variant"; palette = "secondary"; tone = _: 30.0; background = _: secondary_fixed_dim; secondBackground = _: secondary_fixed; contrastCurve = cc 3.0 4.5 7.0 11.0;};

    tertiary_fixed = R {name = "tertiary_fixed"; palette = "tertiary"; isBackground = true; tone = _: 90.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp tertiary_fixed tertiary_fixed_dim 10.0 "Lighter" true;};
    tertiary_fixed_dim = R {name = "tertiary_fixed_dim"; palette = "tertiary"; isBackground = true; tone = _: 80.0; background = highestSurface; contrastCurve = cc 1.0 1.0 3.0 4.5; toneDeltaPair = tdp tertiary_fixed tertiary_fixed_dim 10.0 "Lighter" true;};
    on_tertiary_fixed = R {name = "on_tertiary_fixed"; palette = "tertiary"; tone = _: 10.0; background = _: tertiary_fixed_dim; secondBackground = _: tertiary_fixed; contrastCurve = cc 4.5 7.0 11.0 21.0;};
    on_tertiary_fixed_variant = R {name = "on_tertiary_fixed_variant"; palette = "tertiary"; tone = _: 30.0; background = _: tertiary_fixed_dim; secondBackground = _: tertiary_fixed; contrastCurve = cc 3.0 4.5 7.0 11.0;};
  };

  # --- getTone: the DynamicColor contrast/tone resolution ---
  getTone = role: s: let
    cl = s.contrastLevel;
    decreasing = cl < 0.0;
  in
    if role.toneDeltaPair != null
    then let
      pair = role.toneDeltaPair s;
      roleA = pair.subject;
      roleB = pair.basis;
      delta = pair.delta;
      polarity = pair.polarity;
      stayTogether = pair.stayTogether;
      bgTone = getTone (role.background s) s;
      aIsNearer = polarity == "Nearer" || (polarity == "Lighter" && !s.isDark) || (polarity == "Darker" && s.isDark);
      nearer =
        if aIsNearer
        then roleA
        else roleB;
      farther =
        if aIsNearer
        then roleB
        else roleA;
      amNearer = role.name == nearer.name;
      dir =
        if s.isDark
        then 1.0
        else -1.0;
      nContrast = ccGet nearer.contrastCurve cl;
      fContrast = ccGet farther.contrastCurve cl;
      nInitial = nearer.tone s;
      nTone0 =
        if decreasing
        then foregroundTone bgTone nContrast
        else if ratioOfTones bgTone nInitial >= nContrast
        then nInitial
        else foregroundTone bgTone nContrast;
      fInitial = farther.tone s;
      fTone0 =
        if decreasing
        then foregroundTone bgTone fContrast
        else if ratioOfTones bgTone fInitial >= fContrast
        then fInitial
        else foregroundTone bgTone fContrast;
      # expand to satisfy delta
      exp =
        if (fTone0 - nTone0) * dir >= delta
        then {n = nTone0; f = fTone0;}
        else let f1 = clamp 0.0 100.0 (delta * dir + nTone0); in
          if (f1 - nTone0) * dir >= delta
          then {n = nTone0; f = f1;}
          else {n = clamp 0.0 100.0 (0.0 - delta * dir + f1); f = f1;};
      # avoid the [50,60) awkward zone
      adj =
        if between 50.0 60.0 exp.n
        then
          if dir > 0.0
          then {n = 60.0; f = maxf exp.f (delta * dir + 60.0);}
          else {n = 49.0; f = minf exp.f (delta * dir + 49.0);}
        else if between 50.0 60.0 exp.f
        then
          if stayTogether
          then (
            if dir > 0.0
            then {n = 60.0; f = maxf exp.f (delta * dir + 60.0);}
            else {n = 49.0; f = minf exp.f (delta * dir + 49.0);}
          )
          else {n = exp.n; f = if dir > 0.0 then 60.0 else 49.0;}
        else exp;
    in
      if amNearer
      then adj.n
      else adj.f
    else let
      answer0 = role.tone s;
    in
      if role.background == null
      then answer0
      else let
        bgTone = getTone (role.background s) s;
        desired = ccGet role.contrastCurve cl;
        answer1 =
          if ratioOfTones bgTone answer0 >= desired && !decreasing
          then answer0
          else foregroundTone bgTone desired;
        answer2 =
          if role.isBackground && between 50.0 60.0 answer1
          then
            if ratioOfTones 49.0 bgTone >= desired
            then 49.0
            else 60.0
          else answer1;
      in
        if role.secondBackground == null
        then answer2
        else let
          bgt1 = getTone (role.background s) s;
          bgt2 = getTone (role.secondBackground s) s;
          upper = maxf bgt1 bgt2;
          lower = minf bgt1 bgt2;
          lightOption = lighter upper desired;
          darkOption = darker lower desired;
          prefersLight = tonePrefersLight bgt1 || tonePrefersLight bgt2;
          availables = builtins.filter (x: abs (x - (-1.0)) > 1.0e-12) [lightOption darkOption];
        in
          if ratioOfTones upper answer2 >= desired && ratioOfTones lower answer2 >= desired
          then answer2
          else if prefersLight
          then (if lightOption < 0.0 then 100.0 else lightOption)
          else if builtins.length availables == 1
          then builtins.head availables
          else (if darkOption < 0.0 then 0.0 else darkOption);

  mkScheme = isDark: sourceHex: let
    src = h.hctFromHex sourceHex;
  in {
    inherit isDark;
    contrastLevel = 0.0;
    sourceColorHct = src;
    palettes = p.rainbowPalettes {inherit (src) hue chroma;};
  };

  colorOf = roleName: s: let
    role = roles.${roleName};
    tone = getTone role s;
  in
    s.palettes.${role.palette}.tone tone;
in {
  inherit roles mkScheme getTone colorOf;

  # all role colors for a source hex + mode
  colorsFor = isDark: sourceHex: let
    s = mkScheme isDark sourceHex;
  in
    lib.mapAttrs (n: _: colorOf n s) roles;
}
