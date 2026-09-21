# Atelier publishing

Atelier is the canonical home for paper sources, figures and research notes. It
is private-ish by design: the individual files are not necessarily secret, but
the aggregate work-in-progress history should not become part of a public online
footprint. Foundry is public and owns the website that presents finished work.

Generated publication pages, figures and PDFs are currently duplicated into
Foundry. Replace that duplication with a narrow, versioned publication boundary:
Atelier builds public artifacts, Hydra publishes them, and Foundry consumes a
locked release.

## Goals

- Keep Atelier's source and history private while explicitly publishing finished
  outputs.
- Make Atelier the sole owner of paper builds and generated publication content.
- Keep Foundry builds reproducible through `flake.lock`.
- Support both hermetic website builds and convenient local development across
  the two repositories.
- Leave room for Atelier to publish other independently consumed artifact
  families later.

## Non-goals

- Merge Atelier and Foundry into one repository.
- Publish Atelier source, meeting notes or agent notes.
- Build a general-purpose package registry or browsing interface.
- Automatically update Foundry whenever Atelier publishes. Updating the flake
  input manually is sufficient.

## Architecture

```text
Atelier sources
      |
      v
Nix publication bundle (directory)
      |
      v
Hydra CI build
      |
      v
Hydra RunCommand hook
      |  package, validate and publish
      v
Public HTTP webroot
      |  immutable tarballs + latest endpoint
      v
Foundry non-flake input, pinned by flake.lock
      |
      v
Managed Jekyll links / website derivation
      |
      v
Published website
```

The repository boundary is also the publication boundary:

| Concern | Owner |
|---------|-------|
| Research sources, notes and paper build logic | Atelier |
| Selection and construction of public artifacts | Atelier |
| Bundle filesystem schema | Shared contract |
| CI and artifact publication | Atelier/Hydra |
| Selected artifact revision | Foundry's `flake.lock` |
| Site layout and presentation | Foundry/Jekyll |
| Local integration links | Foundry development tooling |

## Publication bundle

Atelier exposes one canonical Nix derivation whose output is a directory. The
initial bundle is deliberately shaped for Jekyll:

```text
publication-bundle/
├── _publications/
│   ├── fontes-design-2026.md
│   └── fontes-sesos-2026.md
├── assets/papers/
│   ├── design/
│   ├── sesos/
│   └── *.pdf
└── manifest.json
```

The derivation:

1. builds PDFs from the Typst or LaTeX sources;
2. generates the publication Markdown;
3. gathers figures and other public assets;
4. validates the exported layout and an allowlist of file types;
5. writes the source Atelier revision and schema version to `manifest.json`.

Only this directory is public. Building it must not copy source trees, notes,
intermediate files or build logs into the output. Validation should also catch
unexpected hidden files and absolute build paths where practical.

The output remains a directory rather than a tarball because that is the useful
Nix-native interface and the convenient form for local development:

```console
nix build ~/Atelier#publicationBundle
```

Packing is transport work and belongs to the publishing hook.

## Hydra CI

Hydra builds `publicationBundle` for Atelier revisions. A PDF, conversion or
validation failure prevents publication. The expanded directory can remain
available as an ordinary Hydra build output for inspection.

The build derivation stays pure and performs no deployment.

## Hydra publication

Hydra's RunCommand plugin runs a hook under `hydra-notify` after a successful
publication build. This is distinct from a Nix `runCommand` derivation: the hook
executes outside the sandbox and may write to the registry webroot.

The hook should:

1. obtain the successful bundle output and Atelier revision from the build;
2. verify the bundle schema and manifest;
3. create a normalized tarball in a temporary location;
4. calculate `nix hash path` for the unpacked directory;
5. install the archive at an immutable revision-addressed path;
6. refuse to replace an existing revision with different contents;
7. atomically update the latest release and its locking metadata.

Normalize archive metadata so retrying publication produces identical bytes:
sort entries, use fixed ownership and timestamps, and suppress gzip's timestamp
and original filename. The NAR hash of the unpacked tree is the identity that
matters to Nix, but deterministic archive bytes make operation and verification
less surprising.

A dynamic `runCommandHook` keeps the publishing program versioned with Atelier.
It also allows trusted jobset code to execute on the Hydra host, so enable it
only for the trusted Atelier project/jobset. A static hook matching the Atelier
publication job remains an alternative if keeping deployment code in Hydra's
configuration is preferable.

## HTTP registry

The registry is a boring public webroot, not a dedicated package service:

```text
https://<registry>/v1/publications/
├── latest.tar.gz
└── bundles/
    ├── <atelier-revision-a>.tar.gz
    └── <atelier-revision-b>.tar.gz
```

Revision-addressed archives are immutable and retained so historical Foundry
lockfiles continue to build.

`latest.tar.gz` must implement Nix's Lockable HTTP Tarball Protocol. Its response
includes the immutable archive URL and NAR hash:

```http
Link: <https://<registry>/v1/publications/bundles/<revision>.tar.gz?narHash=sha256-...>; rel="immutable"
```

This lets `flake.nix` name the moving `latest` endpoint while `flake.lock`
records a fetchable immutable release. A plain symlink or mutable file without
the `Link` header is insufficient: after the next publication, an old lockfile
would request the changed URL with its old hash and fail.

The concrete mechanism for serving the changing header is still open. Options
include an atomically replaced web-server configuration fragment, a small
dynamic endpoint in front of the static webroot, or a server with native support
for the protocol.

## Foundry input

Foundry consumes the archive as a non-flake data input:

```nix
inputs.atelier-publications = {
  url = "https://<registry>/v1/publications/latest.tar.gz";
  flake = false;
};
```

Nix downloads and unpacks the archive, so consumers see the same directory
shape as Atelier's local derivation. Updating is explicit:

```console
nix flake update atelier-publications
```

The website derivation receives `inputs.atelier-publications` as a path. In its
private build tree it links or copies `_publications` and `assets/papers` into
the Jekyll source, rejects collisions, and performs the normal Jekyll build.
After this is wired up, remove the duplicated generated publications and paper
assets from Foundry.

## Local website development

Use managed symlinks first; reconsider a Jekyll plugin only if this proves
awkward.

The website development shell exports the locked input as its default:

```sh
PUBLICATIONS_ROOT=/nix/store/...-source
```

A helper invoked by the shell or explicitly by the developer creates ignored,
collision-checked links under the existing Jekyll paths:

```text
projects/website/_src/_publications/*.md
projects/website/_src/assets/papers/
```

The helper must touch only paths it owns, fail rather than overwrite normal site
files, and provide a cleanup operation. The generated links belong in
`.gitignore`.

To develop against current Atelier work instead of the locked public release:

```console
nix build ~/Atelier#publicationBundle \
  --out-link ~/Atelier/result-publications

PUBLICATIONS_ROOT=~/Atelier/result-publications nix develop .#website
```

Keep the symlink pointed through the stable `result-publications` path rather
than resolving it to one store path, so rebuilding Atelier updates the target.
Test whether Jekyll's watcher notices changes through these links. Restarting
`jekyll serve` is an acceptable initial fallback.

## Future artifacts and laziness

A tarball is one fetch boundary: Nix cannot lazily fetch selected files from a
monolithic Atelier archive. Future public artifact families should therefore be
built and published independently:

```text
/v1/publications/...
/v1/slides/...
/v1/bibliography/...
```

Foundry can add a separate non-flake input for each family it actually consumes.
Derivations that reference only publications do not acquire a dependency on
slides or bibliography, and each input can be updated separately.

Keep granularity at the artifact-family level rather than creating one archive
per paper unless a concrete need appears. If the number of inputs eventually
becomes unwieldy, publish a small catalog flake containing lazy, hash-pinned
references to the independent archives. Do not introduce that indirection for
the first bundle.

## Retention and failure behavior

- Never mutate a revision-addressed archive.
- Publish the immutable archive before changing `latest`.
- Update `latest` and its `Link` metadata as one logical operation.
- Leave the previous latest release usable if publication fails partway through.
- Retain every archive referenced by Foundry history; initially, retaining all
  publication bundles is simpler and safer than garbage collection.
- Give `hydra-notify` write access only to the publication webroot and no Atelier
  secrets beyond what the hook strictly requires.

## Order of work

1. Define and document the publication bundle schema in Atelier.
2. Implement `publicationBundle` for the currently duplicated papers.
3. Validate the output locally, including PDFs, web pages and asset links.
4. Add the Atelier Hydra job.
5. Choose the registry host and configure the static webroot.
6. Implement the RunCommand publisher and immutable archive layout.
7. Implement and test the lockable `latest.tar.gz` response.
8. Add `atelier-publications` to Foundry and update `flake.lock`.
9. Pass the input into the website derivation.
10. Add the managed-symlink development helper and test Jekyll watching.
11. Remove the duplicated publication pages and assets from Foundry.
12. Verify that an old Foundry lockfile still builds after publishing a newer
    Atelier bundle.

## Open questions

- Which host and domain should serve the registry?
- Should publishing use a static or dynamic Hydra RunCommand hook?
- How should the web server generate the lockable `Link` header atomically?
- Which exact files and extensions belong in the public allowlist?
- Does Jekyll reliably watch changes through the managed symlinks?
- Should `manifest.json` list every exported file and its hash, or only schema
  and source revision metadata?
