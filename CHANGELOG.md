# Release Notes

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

## [v0.3.0](https://github.com/nhz2/install-julia-linux/tree/v0.3.0) - 2026-06-22

### Added

- macOS and FreeBSD are now supported alongside Linux. The target triplet is autodetected and can be set explicitly with the new `INSTALL_JULIA_TRIPLET` environment variable.

### Fixed

- Stable/prerelease download URLs are no longer built by hand. `<INSTALL_JULIA_STABLE_URL>/bin/versions.json` (default `https://julialang-s3.julialang.org/bin/versions.json`) is searched for the entry matching the version and build `triplet`, and its `url` field gives the download path. Installs no longer break when the layout under `/bin` changes.
- A `+` in a version specifier is now rejected with `bad version specifier`. This also applies to the `switch` command's version argument (but not when it is a path containing a `/`).

## [v0.2.0](https://github.com/nhz2/install-julia-linux/tree/v0.2.0) - 2026-06-15

- Added the command `install-julia.sh manifest <path>`: Install the stable Julia version a project's `Manifest.toml` was written with, and make it the default (path is a manifest file or a project dir) [#2](https://github.com/nhz2/install-julia-linux/pull/2)

## [v0.1.0](https://github.com/nhz2/install-julia-linux/tree/v0.1.0) - 2026-06-12

### Added

- Initial release