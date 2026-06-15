# install-julia-linux

A POSIX shell script that installs and manages
[Julia](https://julialang.org) on Linux. It is an alternative to [`jill.py`](https://github.com/johnnychen94/jill.py)
or [`juliaup`](https://github.com/JuliaLang/juliaup): it downloads official Julia
binaries, verifies them with a bundled GPG key, unpacks them,
and keeps a tidy set of `julia`, `julia-X`, `julia-X.Y`, `julia-X.Y.Z`
symlinks on your `PATH`.

Runtime dependencies: `curl`, `tar`, `mktemp`, `gpgv`, `base64`, and `readlink`

## One line install of the latest version of Julia

```sh
curl -fsSL https://github.com/nhz2/install-julia-linux/releases/download/v0.2.0/install-julia.sh | sh
```

## Install the script for ongoing version management

```sh
curl -fsSLO https://github.com/nhz2/install-julia-linux/releases/download/v0.2.0/install-julia.sh   # or just copy the file
chmod +x install-julia.sh
mv install-julia.sh ~/.local/bin/                  # somewhere on your PATH
```

Make sure your symlink directory (default `~/.local/bin`) is on your `PATH`.

## Quick start

```sh
install-julia.sh                # install the latest stable Julia, make it default
julia                           # ...now on your PATH
```

## Other examples

```sh
install-julia.sh 1.12                  # latest 1.12.x, set as default
install-julia.sh manifest .            # install the stable version the Manifest.toml was written with, set as default
install-julia.sh add 1.10              # install 1.10.x without changing the default
install-julia.sh add nightly           # add the master nightly
install-julia.sh add pre               # add the latest prerelease or stable
install-julia.sh switch 1.10           # make 1.10.x the default julia
install-julia.sh switch ~/build/julia/usr/bin/julia   # point julia at a custom build
install-julia.sh remove 1.10           # delete all 1.10.*
install-julia.sh list                  # show what's installed
```

## Usage

```
install-julia.sh [options] [command] [version]
```

| Command                              | What it does                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------------- |
| `install-julia.sh`                   | Install the latest stable release and point the default `julia` at it.       |
| `install-julia.sh <version>`         | Install `<version>` and make it the default `julia`.                         |
| `install-julia.sh add <version>`     | Install `<version>` but leave the default `julia` untouched.                 |
| `install-julia.sh switch <ver\|path>` | Repoint the default `julia` at an already-installed version, or at a path to a `julia` binary. A numeric prefix (`1`, `1.12`) picks the greatest installed stable patch under it. Installs nothing. |
| `install-julia.sh remove <version>`  | Delete a version and its symlinks. A bare numeric prefix removes every matching build (releases, prereleases, the branch nightly, and per-arch copies). A fully-qualified id (`1.12.6~aarch64`, `nightly`, `pr1234`) matches just itself. Alias: `rm`. |
| `install-julia.sh list`              | List installed versions. Alias: `ls`.                                        |
| `install-julia.sh manifest <path>`   | Install the stable Julia version a project's `Manifest.toml` was written with, and make it the default (path is a manifest file or a project dir) |

### Options

| Option                          | Meaning                                  |
| ------------------------------- | ---------------------------------------- |
| `-h`, `--help`                  | Show help.                               |
| `-v`, `--version`               | Show the script's own version.           |
| `-y`, `--yes`                   | Don't prompt for confirmation.           |
| `--reinstall`                   | If a stable version is already installed, re-download and replace it. |

## Version specifiers

| Specifier        | Meaning                                                            |
| ---------------- | ----------------------------------------------------------------- |
| `1`              | Latest stable `1.x`.                                               |
| `1.12`           | Latest stable `1.12.x`.                                            |
| `1.12.6`         | Exactly `1.12.6`.                                                  |
| `1.13.0-rc1`     | A specific prerelease (release candidate, beta, …).               |
| `pre`            | Latest release, including release candidates and betas.           |
| `nightly`        | Latest `master` nightly build.                                    |
| `1.11-nightly`   | Latest nightly of the `1.11` branch.                              |
| `pr1234`         | The latest CI build of pull request 1234.                         |

### Architecture override

Any specifier may carry a `~arch` suffix to override autodetection:

```sh
install-julia.sh 1.10~x86_64     # force 64-bit x86
install-julia.sh 1.10~x86        # force 32-bit (i686)
install-julia.sh 1.10~aarch64    # force ARM64
```

## Environment variables

| Variable                     | Default                                       | Purpose                                            |
| ---------------------------- | --------------------------------------------- | -------------------------------------------------- |
| `INSTALL_JULIA_INSTALL_DIR`  | `~/packages/julias`                           | Where versions are unpacked.                       |
| `INSTALL_JULIA_SYMLINK_DIR`  | `~/.local/bin`                                | Where symlinks are created.                        |
| `INSTALL_JULIA_NO_VERIFY`    | `0`                                           | Set to `1` to skip GPG verification.               |
| `INSTALL_JULIA_STABLE_URL`   | `https://julialang-s3.julialang.org`          | Base for stable/prerelease binaries.               |
| `INSTALL_JULIA_NIGHTLY_URL`  | `https://julialangnightlies-s3.julialang.org` | Base for nightly and PR builds.                    |

Stable/prerelease resolution reads `<INSTALL_JULIA_STABLE_URL>/bin/versions.json`
to discover available versions.

## How it lays things out

Versions are unpacked into `INSTALL_JULIA_INSTALL_DIR` (default
`~/packages/julias`), one directory per version. Stable releases are named by
their exact version; rolling builds (nightly, PR) are named after their
label:

```
~/packages/julias/
  julia-1.12.6/
  julia-1.12.6~x86/   # a non-native build, namespaced by arch (see below)
  julia-nightly/
```

Symlinks are created in `INSTALL_JULIA_SYMLINK_DIR` (default `~/.local/bin`):

```
julia            -> .../julia-1.12.6/bin/julia      # the default; set by install / switch
julia-1          -> .../julia-1.12.6/bin/julia      # greatest installed 1.x.y
julia-1.12       -> .../julia-1.12.6/bin/julia      # greatest installed 1.12.x
julia-1.12.6     -> .../julia-1.12.6/bin/julia
julia-1.12.6~x86 -> .../julia-1.12.6~x86/bin/julia
julia-nightly    -> .../julia-nightly/bin/julia
```

The `julia-1` and `julia-1.12` "rollup" links track the greatest installed
stable patch/minor on the default architecture.
Prereleases, nightlies, PR builds, and versions with specified architectures get only their own direct link
(e.g. `julia-1.13.0-rc1`, `julia-nightly`, `julia-pr1234`, `julia-1.12.6~x86`).

### Reinstalling

Installing a stable or prerelease version that's already present does not
re-download it. It just refreshes the symlinks (and, for the default-setting form,
switches the default), after a confirmation prompt that says so. Pass `--reinstall`
to force a fresh download and replace the build (e.g. to repair a corrupt tree).
Rolling builds (`nightly`, `pr<num>`) always refresh to the newest build behind their
label.

## Verification

Every download is verified with GPG (via `gpgv`) against Julia's official
signing key, which is bundled in the script. If a
signature is missing or doesn't verify, the install is aborted.

PR builds are the exception: Julia publishes no signature for them, so the check
is skipped with a warning. Set `INSTALL_JULIA_NO_VERIFY=1` to skip verification
entirely (then `gpgv` isn't required).

## AI usage

This project was developed with the help of AI tools (Claude Code). All code
has been manually reviewed.

## License

MIT.
