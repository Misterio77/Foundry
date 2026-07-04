# Pure-Nix floating-point math, enough to port material-color-utilities.
# Nix has floats + (+,-,*,/) + floor/ceil but no transcendentals, so these are
# hand-rolled via range reduction + series/Newton. Aiming for ~1e-9 accuracy.
{lib}: let
  inherit (builtins) floor;
in rec {
  pi = 3.141592653589793;
  e = 2.718281828459045;
  ln2 = 0.6931471805599453;

  abs = x:
    if x < 0.0
    then 0.0 - x
    else x;

  # Float modulo
  fmod = x: m: x - m * (1.0 * floor (x / m));

  # sqrt via Newton-Raphson
  sqrt = x:
    if x <= 0.0
    then 0.0
    else let
      step = g: (g + x / g) / 2.0;
      iter = g: n:
        if n <= 0
        then g
        else iter (step g) (n - 1);
    in
      iter (if x > 1.0 then x else 1.0) 40;

  # cbrt via Newton, sign-aware
  cbrt = x:
    if x == 0.0
    then 0.0
    else let
      s =
        if x < 0.0
        then -1.0
        else 1.0;
      a = abs x;
      step = g: (2.0 * g + a / (g * g)) / 3.0;
      iter = g: n:
        if n <= 0
        then g
        else iter (step g) (n - 1);
    in
      s * iter (if a > 1.0 then a else 1.0) 60;

  # exp via argument halving + Taylor, then repeated squaring
  exp = x: let
    # reduce until |r| < 1/1024 (halve 10 times max region)
    k = 12;
    scale = 4096.0; # 2^12
    r = x / scale;
    # Taylor around 0 for small r
    term = i: acc: prod:
      if i > 12
      then acc
      else let
        p = prod * r / (1.0 * i);
      in
        term (i + 1) (acc + p) p;
    small = term 1 1.0 1.0;
    square = v: n:
      if n <= 0
      then v
      else square (v * v) (n - 1);
  in
    square small k;

  # ln via factoring powers of 2 into [2/3, 4/3], then artanh series
  ln = x:
    if x <= 0.0
    then 0.0 # undefined; caller guards
    else let
      reduce = v: k:
        if v > 1.3333333333
        then reduce (v / 2.0) (k + 1)
        else if v < 0.6666666667
        then reduce (v * 2.0) (k - 1)
        else {
          inherit v k;
        };
      red = reduce x 0;
      y = (red.v - 1.0) / (red.v + 1.0);
      y2 = y * y;
      term = i: acc: ypow:
        if i > 25
        then acc
        else let
          p = ypow / (1.0 * i);
        in
          term (i + 2) (acc + p) (ypow * y2);
    in
      2.0 * (term 1 0.0 y) + (1.0 * red.k) * ln2;

  # pow for real exponents (base > 0); integer-exponent fast path for exactness
  pow = b: p:
    if b == 0.0
    then 0.0
    else if p == (1.0 * floor p)
    then let
      n = floor (abs p);
      go = acc: i:
        if i <= 0
        then acc
        else go (acc * b) (i - 1);
      v = go 1.0 n;
    in
      if p < 0.0
      then 1.0 / v
      else v
    else exp (p * ln b);

  # sin/cos via range reduction to [-pi,pi] + Taylor
  sin = x: let
    r = fmod (x + pi) (2.0 * pi) - pi;
    r2 = r * r;
    term = i: acc: prod:
      if i > 12
      then acc
      else let
        p = prod * (0.0 - r2) / (1.0 * (2 * i) * (2 * i + 1));
      in
        term (i + 1) (acc + p) p;
  in
    term 1 r r;

  cos = x: sin (pi / 2.0 - x);

  # atan: half-angle reduce (atan z = 2*atan(z/(1+sqrt(1+z^2)))) until |z| small,
  # so the alternating series converges fast, then scale back by 2^k.
  atan = x: let
    reduce = z: k:
      if (abs z) < 0.2
      then {inherit z k;}
      else reduce (z / (1.0 + sqrt (1.0 + z * z))) (k + 1);
    red = reduce x 0;
    z = red.z;
    z2 = z * z;
    term = i: acc: zpow:
      if i > 25
      then acc
      else let
        s =
          if (fmod (1.0 * i) 4.0) == 1.0
          then 1.0
          else -1.0;
      in
        term (i + 2) (acc + s * zpow / (1.0 * i)) (zpow * z2);
  in
    (pow 2.0 (1.0 * red.k)) * (term 1 0.0 z);

  atan2 = y: x:
    if x > 0.0
    then atan (y / x)
    else if x < 0.0 && y >= 0.0
    then atan (y / x) + pi
    else if x < 0.0 && y < 0.0
    then atan (y / x) - pi
    else if x == 0.0 && y > 0.0
    then pi / 2.0
    else if x == 0.0 && y < 0.0
    then (0.0 - pi) / 2.0
    else 0.0;

  toDeg = r: r * 180.0 / pi;
  toRad = d: d * pi / 180.0;
}
