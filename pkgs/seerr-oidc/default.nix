{
  seerr,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_10,
  nodejs-slim_22,
}: let
  pnpm = pnpm_10.override {nodejs-slim = nodejs-slim_22;};
in
  seerr.overrideAttrs (finalAttrs: oldAttrs: {
    version = "0.1.0-oidc-2e52312";
    # https://github.com/seerr-team/seerr/pull/2715
    src = fetchFromGitHub {
      owner = "michaelhthomas";
      repo = "seerr";
      rev = "2e523125e8e7262af44309c70db20fe2d7ca28a3";
      hash = "sha256-k8qWhsSBnQXfGk/xEmb2+4tlw6xY8viwWzEQUBxtrNs=";
    };
    patches = (oldAttrs.patches or []) ++ [./permission-claims.patch];
    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-bfdmNLBypcoJ79/lMRSgRKSIddQJJohcn3/dL21edog=";
    };
  })
