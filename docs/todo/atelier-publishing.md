# Atelier publication artifacts — proposal

Goal: publish finished papers from private Atelier without copying its sources
or history into public Foundry. Foundry currently vendors publication Markdown,
figures and PDFs in `projects/website/_src/`; no artifact input or publisher is
wired up. CI is Nixbot, not Hydra.

## Boundary

Atelier should build an allowlisted `publicationBundle` directory containing:

```text
_publications/*.md
assets/papers/             # PDFs and figures
manifest.json              # schema version and source revision
```

Keep source trees, notes, intermediate files and private build logs out. Validate
locally before publishing; a successful build must not itself perform deployment.

A Nixbot effect/post-build step would publish normalized, immutable
revision-addressed tarballs to a public HTTP webroot. Publish the archive before
atomically advancing `latest.tar.gz` and its metadata; never overwrite releases
or delete ones referenced by historical Foundry lockfiles.

Foundry would consume a non-flake `atelier-publications` input pinned by
`flake.lock`, updated manually. A moving latest URL must implement Nix's
Lockable HTTP Tarball Protocol with an immutable URL/NAR-hash `Link` header;
a mutable symlink alone breaks old locks. Choose the registry host and serving
mechanism before implementing this.

## Work remaining

1. Define the exact public allowlist and build/validate the bundle in Atelier.
2. Implement the Nixbot publisher and registry; test retry safety and old-lock
   builds after publishing a newer release.
3. Feed the locked directory into the Jekyll derivation, rejecting collisions,
   then remove the duplicated generated files from Foundry.
4. For local development, support a `PUBLICATIONS_ROOT` override pointing at a
   stable Atelier build-result symlink. Any managed links must be ignored,
   collision-checked and removable without touching ordinary site files.
   Test Jekyll watching; restarting the server is an acceptable first fallback.

Defer catalog flakes and per-paper inputs. If slides or other artifact
families gain independent consumers, publish separate bundles then.
