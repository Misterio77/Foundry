# Pure-Nix port of Google's material-color-utilities HCT: sRGB <-> CAM16 <-> HCT,
# including the HctSolver (findResultByJ + bisectToLimit). Ported from the
# canonical TypeScript reference so output matches matugen bit-for-bit (modulo
# our math lib's ~1e-9 series precision). See lib/math.nix for the transcendentals.
{lib}: let
  m = import ./math.nix {inherit lib;};
  inherit (builtins) floor elemAt;
  inherit (m) pi exp ln pow sqrt cbrt sin cos atan2 abs fmod;

  round = x: floor (x + 0.5);
  signum = x:
    if x < 0.0
    then -1.0
    else if x == 0.0
    then 0.0
    else 1.0;
  clampInt = lo: hi: x:
    if x < lo
    then lo
    else if x > hi
    then hi
    else x;
  max0 = x:
    if x > 0.0
    then x
    else 0.0;
  # matrixMultiply(row, matrix) -> [row·m0, row·m1, row·m2]
  matmul = row: mat: let
    r0 = elemAt row 0;
    r1 = elemAt row 1;
    r2 = elemAt row 2;
    dot = v: r0 * (elemAt v 0) + r1 * (elemAt v 1) + r2 * (elemAt v 2);
  in [(dot (elemAt mat 0)) (dot (elemAt mat 1)) (dot (elemAt mat 2))];

  sanitizeDegrees = d: let r = fmod d 360.0; in
    if r < 0.0
    then r + 360.0
    else r;

  # --- color_utils ---
  labE = 216.0 / 24389.0;
  labKappa = 24389.0 / 27.0;
  labF = t:
    if t > labE
    then cbrt t
    else (labKappa * t + 16.0) / 116.0;
  labInvf = ft: let ft3 = ft * ft * ft; in
    if ft3 > labE
    then ft3
    else (116.0 * ft - 16.0) / labKappa;
  yFromLstar = l: 100.0 * labInvf ((l + 16.0) / 116.0);
  lstarFromY = y: labF (y / 100.0) * 116.0 - 16.0;

  linearized = c: let n = c / 255.0; in
    if n <= 0.040449936
    then n / 12.92 * 100.0
    else pow ((n + 0.055) / 1.055) 2.4 * 100.0;
  delinearizedRaw = v: let n = v / 100.0; in
    if n <= 0.0031308
    then n * 12.92
    else 1.055 * pow n (1.0 / 2.4) - 0.055;
  delinearized = v: clampInt 0.0 255.0 (round (delinearizedRaw v * 255.0));
  trueDelinearized = v: delinearizedRaw v * 255.0;

  argbFromLinrgb = linrgb: {
    r = delinearized (elemAt linrgb 0);
    g = delinearized (elemAt linrgb 1);
    b = delinearized (elemAt linrgb 2);
  };
  argbFromLstar = l: let c = delinearized (yFromLstar l); in {
    r = c;
    g = c;
    b = c;
  };
  lstarFromRgb = {r, g, b}: let
    y = 0.2126 * linearized r + 0.7152 * linearized g + 0.0722 * linearized b;
  in
    116.0 * labF (y / 100.0) - 16.0;

  # --- viewing conditions (DEFAULT) ---
  d65 = [95.047 100.0 108.883];
  makeVc = whitePoint: adaptingLuminance: backgroundLstar: surround: let
    rW = (elemAt whitePoint 0) * 0.401288 + (elemAt whitePoint 1) * 0.650173 + (elemAt whitePoint 2) * (-0.051461);
    gW = (elemAt whitePoint 0) * (-0.250268) + (elemAt whitePoint 1) * 1.204414 + (elemAt whitePoint 2) * 0.045854;
    bW = (elemAt whitePoint 0) * (-0.002079) + (elemAt whitePoint 1) * 0.048952 + (elemAt whitePoint 2) * 0.953127;
    f = 0.8 + surround / 10.0;
    lerp = a: b: t: (1.0 - t) * a + t * b;
    c =
      if f >= 0.9
      then lerp 0.59 0.69 ((f - 0.9) * 10.0)
      else lerp 0.525 0.59 ((f - 0.8) * 10.0);
    dRaw = f * (1.0 - (1.0 / 3.6) * exp ((0.0 - adaptingLuminance - 42.0) / 92.0));
    d =
      if dRaw > 1.0
      then 1.0
      else if dRaw < 0.0
      then 0.0
      else dRaw;
    nc = f;
    rgbD = [
      (d * (100.0 / rW) + 1.0 - d)
      (d * (100.0 / gW) + 1.0 - d)
      (d * (100.0 / bW) + 1.0 - d)
    ];
    k = 1.0 / (5.0 * adaptingLuminance + 1.0);
    k4 = k * k * k * k;
    k4F = 1.0 - k4;
    fl = k4 * adaptingLuminance + 0.1 * k4F * k4F * cbrt (5.0 * adaptingLuminance);
    n = yFromLstar backgroundLstar / (elemAt whitePoint 1);
    z = 1.48 + sqrt n;
    nbb = 0.725 / pow n 0.2;
    fac = i: rw: pow (fl * (elemAt rgbD i) * rw / 100.0) 0.42;
    rgbAF = [(fac 0 rW) (fac 1 gW) (fac 2 bW)];
    rgbA = map (x: 400.0 * x / (x + 27.13)) rgbAF;
    aw = (2.0 * (elemAt rgbA 0) + (elemAt rgbA 1) + 0.05 * (elemAt rgbA 2)) * nbb;
  in {
    inherit n aw nbb c nc rgbD fl z;
    ncb = nbb;
    fLRoot = pow fl 0.25;
  };
  vc = makeVc d65 ((200.0 / pi) * yFromLstar 50.0 / 100.0) 50.0 2.0;

  # --- CAM16 forward: rgb -> { hue (deg), chroma } ---
  cam16 = {r, g, b}: let
    rL = linearized r;
    gL = linearized g;
    bL = linearized b;
    x = 0.41233895 * rL + 0.35762064 * gL + 0.18051042 * bL;
    y = 0.2126 * rL + 0.7152 * gL + 0.0722 * bL;
    z = 0.01932141 * rL + 0.11916382 * gL + 0.95034478 * bL;
    rC = 0.401288 * x + 0.650173 * y - 0.051461 * z;
    gC = (-0.250268) * x + 1.204414 * y + 0.045854 * z;
    bC = (-0.002079) * x + 0.048952 * y + 0.953127 * z;
    rD = (elemAt vc.rgbD 0) * rC;
    gD = (elemAt vc.rgbD 1) * gC;
    bD = (elemAt vc.rgbD 2) * bC;
    adapt = comp: let af = pow (vc.fl * abs comp / 100.0) 0.42; in
      signum comp * 400.0 * af / (af + 27.13);
    rA = adapt rD;
    gA = adapt gD;
    bA = adapt bD;
    a = (11.0 * rA - 12.0 * gA + bA) / 11.0;
    bb = (rA + gA - 2.0 * bA) / 9.0;
    u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0;
    p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0;
    hue = sanitizeDegrees (atan2 bb a * 180.0 / pi);
    ac = p2 * vc.nbb;
    j = 100.0 * pow (ac / vc.aw) (vc.c * vc.z);
    huePrime =
      if hue < 20.14
      then hue + 360.0
      else hue;
    eHue = 0.25 * (cos (huePrime * pi / 180.0 + 2.0) + 3.8);
    p1 = (50000.0 / 13.0) * eHue * vc.nc * vc.ncb;
    t = p1 * sqrt (a * a + bb * bb) / (u + 0.305);
    alpha = pow t 0.9 * pow (1.64 - pow 0.29 vc.n) 0.73;
    chroma = alpha * sqrt (j / 100.0);
  in {inherit hue chroma;};

  # --- HctSolver ---
  scaledDiscountFromLinrgb = [
    [0.001200833568784504 0.002389694492170889 0.0002795742885861124]
    [0.0005891086651375999 0.0029785502573438758 0.0003270666104008398]
    [0.00010146692491640572 0.0005364214359186694 0.0032979401770712076]
  ];
  linrgbFromScaledDiscount = [
    [1373.2198709594231 (-1100.4251190754821) (-7.278681089101213)]
    [(-271.815969077903) 559.6580465940733 (-32.46047482791194)]
    [1.9622899599665666 (-57.173814538844006) 308.7233197812385]
  ];
  yFromLinrgb = [0.2126 0.7152 0.0722];
  criticalPlanes = import ./hct-critical-planes.nix;

  sanitizeRadians = a: fmod (a + pi * 8.0) (pi * 2.0);
  chromaticAdaptation = comp: let af = pow (abs comp) 0.42; in
    signum comp * 400.0 * af / (af + 27.13);
  hueOf = linrgb: let
    sd = matmul linrgb scaledDiscountFromLinrgb;
    rA = chromaticAdaptation (elemAt sd 0);
    gA = chromaticAdaptation (elemAt sd 1);
    bA = chromaticAdaptation (elemAt sd 2);
    a = (11.0 * rA - 12.0 * gA + bA) / 11.0;
    b = (rA + gA - 2.0 * bA) / 9.0;
  in
    atan2 b a;
  areInCyclicOrder = a: b: c: (sanitizeRadians (b - a)) < (sanitizeRadians (c - a));
  intercept = source: mid: target: (mid - source) / (target - source);
  lerpPoint = source: t: target:
    map (i: (elemAt source i) + ((elemAt target i) - (elemAt source i)) * t) [0 1 2];
  setCoordinate = source: coord: target: axis:
    lerpPoint source (intercept (elemAt source axis) coord (elemAt target axis)) target;
  isBounded = x: 0.0 <= x && x <= 100.0;
  nthVertex = y: n: let
    kR = elemAt yFromLinrgb 0;
    kG = elemAt yFromLinrgb 1;
    kB = elemAt yFromLinrgb 2;
    coordA =
      if (fmod (1.0 * n) 4.0) <= 1.0
      then 0.0
      else 100.0;
    coordB =
      if (fmod (1.0 * n) 2.0) == 0.0
      then 0.0
      else 100.0;
    bad = [(-1.0) (-1.0) (-1.0)];
  in
    if n < 4
    then let g = coordA; b = coordB; r = (y - g * kG - b * kB) / kR; in
      if isBounded r then [r g b] else bad
    else if n < 8
    then let b = coordA; r = coordB; g = (y - r * kR - b * kB) / kG; in
      if isBounded g then [r g b] else bad
    else let r = coordA; g = coordB; b = (y - r * kR - g * kG) / kB; in
      if isBounded b then [r g b] else bad;

  bisectToSegment = y: targetHue: let
    step = st: n:
      if n >= 12
      then st
      else let
        mid = nthVertex y n;
      in
        if (elemAt mid 0) < 0.0
        then step st (n + 1)
        else let
          midHue = hueOf mid;
        in
          if !st.initialized
          then step {left = mid; right = mid; leftHue = midHue; rightHue = midHue; initialized = true; uncut = true;} (n + 1)
          else if st.uncut || areInCyclicOrder st.leftHue midHue st.rightHue
          then
            if areInCyclicOrder st.leftHue targetHue midHue
            then step (st // {uncut = false; right = mid; rightHue = midHue;}) (n + 1)
            else step (st // {uncut = false; left = mid; leftHue = midHue;}) (n + 1)
          else step st (n + 1);
    r = step {left = [(-1.0) (-1.0) (-1.0)]; right = [(-1.0) (-1.0) (-1.0)]; leftHue = 0.0; rightHue = 0.0; initialized = false; uncut = true;} 0;
  in [r.left r.right];

  midpoint = a: b: map (i: ((elemAt a i) + (elemAt b i)) / 2.0) [0 1 2];
  criticalPlaneBelow = x: floor (x - 0.5);
  criticalPlaneAbove = x: builtins.ceil (x - 0.5);

  bisectToLimit = y: targetHue: let
    seg = bisectToSegment y targetHue;
    perAxis = state: axis:
      if axis >= 3
      then state
      else let
        l = state.left;
        r = state.right;
      in
        if (elemAt l axis) == (elemAt r axis)
        then perAxis state (axis + 1)
        else let
          leftBelow = (elemAt l axis) < (elemAt r axis);
          lPlane0 =
            if leftBelow
            then criticalPlaneBelow (trueDelinearized (elemAt l axis))
            else criticalPlaneAbove (trueDelinearized (elemAt l axis));
          rPlane0 =
            if leftBelow
            then criticalPlaneAbove (trueDelinearized (elemAt r axis))
            else criticalPlaneBelow (trueDelinearized (elemAt r axis));
          planeLoop = s: i:
            if i >= 8 || (abs (s.rPlane - s.lPlane)) <= 1.0
            then s
            else let
              mPlane = floor ((s.lPlane + s.rPlane) / 2.0);
              coord = elemAt criticalPlanes mPlane;
              mid = setCoordinate s.left coord s.right axis;
              midHue = hueOf mid;
            in
              if areInCyclicOrder s.leftHue targetHue midHue
              then planeLoop (s // {right = mid; rPlane = mPlane;}) (i + 1)
              else planeLoop (s // {left = mid; leftHue = midHue; lPlane = mPlane;}) (i + 1);
          res = planeLoop {left = l; right = r; leftHue = hueOf l; lPlane = lPlane0; rPlane = rPlane0;} 0;
        in
          perAxis {left = res.left; right = res.right;} (axis + 1);
    final = perAxis {left = elemAt seg 0; right = elemAt seg 1;} 0;
  in
    midpoint final.left final.right;

  inverseChromaticAdaptation = adapted: let
    aAbs = abs adapted;
    base = max0 (27.13 * aAbs / (400.0 - aAbs));
  in
    signum adapted * pow base (1.0 / 0.42);

  findResultByJ = hueRadians: chroma: y: let
    tInnerCoeff = 1.0 / pow (1.64 - pow 0.29 vc.n) 0.73;
    eHue = 0.25 * (cos (hueRadians + 2.0) + 3.8);
    p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb;
    hSin = sin hueRadians;
    hCos = cos hueRadians;
    iter = j: round':
      if round' >= 5
      then null
      else let
        jNorm = j / 100.0;
        alpha =
          if chroma == 0.0 || j == 0.0
          then 0.0
          else chroma / sqrt jNorm;
        t = pow (alpha * tInnerCoeff) (1.0 / 0.9);
        ac = vc.aw * pow jNorm (1.0 / vc.c / vc.z);
        p2 = ac / vc.nbb;
        gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin);
        a = gamma * hCos;
        b = gamma * hSin;
        rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
        gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
        bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;
        linrgb = matmul [(inverseChromaticAdaptation rA) (inverseChromaticAdaptation gA) (inverseChromaticAdaptation bA)] linrgbFromScaledDiscount;
        l0 = elemAt linrgb 0;
        l1 = elemAt linrgb 1;
        l2 = elemAt linrgb 2;
      in
        if l0 < 0.0 || l1 < 0.0 || l2 < 0.0
        then null
        else let
          fnj = 0.2126 * l0 + 0.7152 * l1 + 0.0722 * l2;
        in
          if fnj <= 0.0
          then null
          else if round' == 4 || (abs (fnj - y)) < 0.002
          then
            if l0 > 100.01 || l1 > 100.01 || l2 > 100.01
            then null
            else argbFromLinrgb linrgb
          else iter (j - (fnj - y) * j / (2.0 * fnj)) (round' + 1);
  in
    iter (sqrt y * 11.0) 0;

  # hue in degrees, chroma, tone (L*) -> {r,g,b}
  solveToRgb = hueDegrees: chroma: lstar:
    if chroma < 0.0001 || lstar < 0.0001 || lstar > 99.9999
    then argbFromLstar lstar
    else let
      hue = sanitizeDegrees hueDegrees;
      hueRadians = hue / 180.0 * pi;
      y = yFromLstar lstar;
      exact = findResultByJ hueRadians chroma y;
    in
      if exact != null
      then exact
      else argbFromLinrgb (bisectToLimit y hueRadians);

  # --- hex <-> rgb ---
  hexDigit = c:
    {"0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;}.${lib.toLower c};
  hexPair = s: i: (hexDigit (builtins.substring i 1 s)) * 16 + hexDigit (builtins.substring (i + 1) 1 s);
  hexToRgb = hex: let h = lib.removePrefix "#" hex; in {
    r = 1.0 * hexPair h 0;
    g = 1.0 * hexPair h 2;
    b = 1.0 * hexPair h 4;
  };
  hexChars = "0123456789abcdef";
  byteToHex = v: let i = floor (v + 0.5); in
    (builtins.substring (i / 16) 1 hexChars) + (builtins.substring (lib.mod i 16) 1 hexChars);
  rgbToHex = {r, g, b}: "#" + byteToHex r + byteToHex g + byteToHex b;
in rec {
  inherit cam16 solveToRgb hexToRgb rgbToHex lstarFromRgb yFromLstar lstarFromY vc;

  # { hue, chroma, tone } from a hex string
  hctFromHex = hex: let
    rgb = hexToRgb hex;
    c = cam16 rgb;
  in {
    hue = c.hue;
    chroma = c.chroma;
    tone = lstarFromRgb rgb;
  };

  # { hue, chroma, tone } -> hex string
  hexFromHct = {hue, chroma, tone}: rgbToHex (solveToRgb hue chroma tone);
}
