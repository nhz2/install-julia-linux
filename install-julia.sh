#!/bin/sh

# A POSIX shell script that installs and manages
# [Julia](https://julialang.org) on Linux. It is an alternative to [`jill.py`](https://github.com/johnnychen94/jill.py)
# or [`juliaup`](https://github.com/JuliaLang/juliaup): it downloads official Julia
# binaries, verifies them with a bundled GPG key, unpacks them 
# and keeps a tidy set of `julia`, `julia-1`, `julia-1.12`, `julia-1.12.6`
# symlinks on your `PATH`.

# MIT License

# Copyright (c) 2026 Nathan Zimmerberg

set -eu

SELF_VERSION="0.1.0"

# --------------------------------------------------------------------------- #
# Configuration                                                               #
# --------------------------------------------------------------------------- #

INSTALL_DIR=${INSTALL_JULIA_INSTALL_DIR:-"$HOME/packages/julias"}
SYMLINK_DIR=${INSTALL_JULIA_SYMLINK_DIR:-"$HOME/.local/bin"}
# Pinned for display only; the trusted key itself is embedded (see julia_keyring).
GPG_FPR="3673DF529D9049477F76B37566E3C7DC03D6E495"
NO_VERIFY=${INSTALL_JULIA_NO_VERIFY:-0}

# The official Julia binary signing key, dearmored to a binary keyring for gpgv.
# Source : https://julialang.org/assets/juliareleases.asc
# Date   : 2026-06-08
# Key    : Julia (Binary signing key) <buildbot@julialang.org>
# Pinning the key in the script (rather than fetching it from a keyserver) makes
# verification self-contained: no network step to block and no trust in a third
# party beyond the key bytes shipped here, which you can audit against the URL
# above. Regenerate with:
#   curl -fsSL https://julialang.org/assets/juliareleases.asc | gpg --dearmor | base64
# Audit with (must print the fingerprint above):
#   julia_keyring | gpg --show-keys
julia_keyring() {
	base64 -d <<'EOF'
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
cgYU
EOF
}

# Service endpoints. All overridable via the environment so the script can be
# pointed at a mirror or a private cache. Trailing slashes are stripped.
STABLE_BASE=${INSTALL_JULIA_STABLE_URL:-"https://julialang-s3.julialang.org"}
NIGHTLY_BASE=${INSTALL_JULIA_NIGHTLY_URL:-"https://julialangnightlies-s3.julialang.org"}
STABLE_BASE=${STABLE_BASE%/}; NIGHTLY_BASE=${NIGHTLY_BASE%/}

NO_CONFIRM=0

# Resolver output (populated by resolve_spec):
R_KIND=""      # release | nightly | pr
R_LABEL=""     # short symlink id, e.g. 1.12.6 / nightly / 1.11-nightly / pr1234
R_URL=""       # tarball download URL
R_ASC_URL=""   # detached signature URL ("" if none)
R_ROLLUP=0     # 1 if this is a plain stable release eligible for X.Y / X rollups

# Detected/overridden architecture (see arch_setup):
ARCH_STABLE=""   # stable bucket dir: x64 | x86 | aarch64 (raw token if unrecognized)
ARCH_FILE=""     # filename arch:     x86_64 | i686 | aarch64 (raw token if unrecognized)
ARCH_SUFFIX=""   # "~<arch>" tag appended to the label when ~arch was given ("" if autodetected)

# Install staging paths (set by cmd_install; all live inside INSTALL_DIR so every
# move is a same-filesystem rename). The download, signature and unpacked tree go
# under .incoming.*; the version being replaced is parked at .old.* during the swap.
# cleanup() and the next install's reap tear these down.
DEST_DIR=""      # final version dir, e.g. .../julia-1.12.6
INCOMING_DIR=""  # unpacked new build, e.g. .../.incoming.julia-1.12.6
OLD_DIR=""       # previous version parked here during the swap
STAGE_TAR=""     # downloaded tarball; .asc and .keyring sit beside it

# --------------------------------------------------------------------------- #
# Output helpers                                                              #
# --------------------------------------------------------------------------- #

info() { printf '==> %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

# EXIT/INT/TERM trap; returns 0 so it never overrides the script's exit status.
# Runs on Ctrl-C, so it must be fast: rename the (possibly huge) incoming tree into
# the inert .old.* namespace - an instant rename() vs a slow rm -rf - and let the
# next install's reap (install_resolved) delete it. Only the single staged tarball
# is unlinked here; the lockfile is left for the kernel to release on exit.
cleanup() {
	[ -n "$INCOMING_DIR" ] && [ -e "$INCOMING_DIR" ] &&
		mv "$INCOMING_DIR" "$INSTALL_DIR/.old.incoming.$$" 2>/dev/null
	[ -n "$STAGE_TAR" ] && rm -f "$STAGE_TAR" "$STAGE_TAR.asc" "$STAGE_TAR.keyring" 2>/dev/null
	return 0
}
trap cleanup EXIT INT TERM

confirm() {
	# confirm "question" -> 0 if yes. Read the answer strictly from the controlling
	# terminal (/dev/tty), never from stdin: under `curl ... | sh` stdin is the script
	# source, and a stdin fallback would consume the next script line as the answer.
	# No tty means we can't ask, so decline (the prompt default is N anyway) and point
	# at -y for non-interactive use.
	[ "$NO_CONFIRM" -eq 1 ] && return 0
	printf '%s [y/N] ' "$1" >&2
	# 2>/dev/null is placed before </dev/tty on purpose: redirections apply left to
	# right, so the stderr redirect must be in effect before the (possibly failing)
	# /dev/tty open, or the shell's "cannot open /dev/tty" leaks to the terminal.
	if ! read -r _ans 2>/dev/null </dev/tty; then
		printf '\n' >&2
		warn "no terminal available to confirm; assuming No (pass -y to proceed non-interactively)"
		return 1
	fi
	case "$_ans" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# --------------------------------------------------------------------------- #
# Low-level utilities                                                         #
# --------------------------------------------------------------------------- #

have() { command -v "$1" >/dev/null 2>&1; }

need() { have "$1" || die "required command not found: $1"; }

# Take a non-blocking, per-version lock so two operations on the SAME version can't
# race (install vs install, or install vs remove). Different versions use different
# lock files and proceed concurrently. flock holds the lock on FD 9 for the life of
# the process; the kernel releases it automatically on exit - even on SIGKILL - so a
# crash never leaves a stale lock, and we never delete the lockfile (deleting it
# would break mutual exclusion for a process that already opened it). First starter
# wins; a second caller fails fast rather than waiting.
lock_version() {        # lock_version DESTNAME   e.g. julia-1.12.6
	_lock="$INSTALL_DIR/.lock.$1"
	exec 9>"$_lock"
	flock -n 9 || die "another install or remove of ${1#julia-} is already in progress"
	# Revalidate that the file we locked is still the one at this path. `remove`
	# deletes the lockfile as its last act; if it unlinked ours between our open and
	# our flock, our FD now holds a nameless inode while a fresh opener would create
	# a new one - two "holders" on two inodes. Compare our FD's inode (via /proc) to
	# the path's: a mismatch means we raced that remove, so fail fast (re-run). Once
	# they match we're canonical - nobody can delete it without first taking our lock.
	# Best-effort: if the FD inode can't be read (no /proc), skip rather than break.
	_fdino=$(stat -L -c %i /proc/self/fd/9 2>/dev/null)
	[ -z "$_fdino" ] || [ "$_fdino" = "$(stat -c %i "$_lock" 2>/dev/null)" ] ||
		die "lock for ${1#julia-} was removed concurrently; please retry"
}

# http_get URL -> body on stdout; nonzero on HTTP/transport error.
# Capture this into a variable on its own line - _x=$(http_get ...) || die ... --
# never straight into a pipeline: a failing command substitution in a plain
# assignment trips `set -e`, but inside a pipeline it's swallowed, so piping would
# let a network error masquerade as an empty ("not found") result.
# --max-filesize caps a hostile endless response; 100M dwarfs the versions.json
# manifest (~2M) and any real bucket listing.
http_get() { curl -fsSL --retry 3 --max-filesize 100M "$1"; }

# http_download URL DEST. --max-filesize caps it (declared-size refusal + mid-stream abort on curl 8.20.0+); 3G >> any build.
http_download() { curl -fL --retry 3 --progress-bar --max-filesize 3G -o "$2" "$1"; }

# http_ok URL -> 0 if a HEAD request returns success
http_ok() {
	curl -fsIL -o /dev/null "$1" 2>/dev/null
}

# Read versions on stdin, print the greatest. The sed mapping makes prereleases
# sort *below* their final release: plain `sort -V` ranks 1.13.0-rc1 above 1.13.0,
# but `~` sorts before everything in version order (the Debian convention), so
# 1.13.0~rc1 < 1.13.0. We map -> ~ for the sort and back again on the way out.
version_max() { sed 's/-/~/g' | sort -V | tail -1 | sed 's/~/-/g'; }

# --------------------------------------------------------------------------- #
# Architecture                                                                #
# --------------------------------------------------------------------------- #

# arch_setup [override]; resolve an arch alias straight to its bucket names. The
# stable bucket dir (x64/x86) differs from ARCH_FILE - the filename arch, which is
# also the nightlies-bucket dir (x86_64/i686) - so each known arch sets both. An
# UNRECOGNIZED arch is passed through verbatim for both: we can't predict the aliases
# a future Julia arch will use, so we assume one uniform name and let the download
# 404 if that guess is wrong, rather than rejecting a newly-shipped arch outright
# (it then works automatically, or via ~arch, with no script update).
arch_setup() {
	_a=${1:-}
	[ -z "$_a" ] && _a=$(uname -m)
	case "$_a" in
		x86_64 | x64) ARCH_STABLE=x64;     ARCH_FILE=x86_64 ;;
		i686 | x86)   ARCH_STABLE=x86;     ARCH_FILE=i686 ;;
		aarch64)      ARCH_STABLE=aarch64; ARCH_FILE=aarch64 ;;
		*)            ARCH_STABLE=$_a;     ARCH_FILE=$_a ;;   # unrecognized: pass through
	esac
}

# --------------------------------------------------------------------------- #
# Stable release discovery (versions.json manifest)                           #
# --------------------------------------------------------------------------- #

# Escape regex metacharacters (dots) in a version prefix.
reesc() { printf '%s' "$1" | sed 's/\./\\./g'; }

# stable_versions -> every full version with a Linux build for this arch, one per
# line (e.g. 1.12.6 / 1.13.0-rc1). Read from the published release manifest at
# <STABLE_BASE>/bin/versions.json rather than an S3 bucket listing: the manifest is
# an ordinary file, so a dumb HTTP mirror (one with no S3 ListObjects API) serves it
# too. We don't parse the JSON - we just pull the tarball filenames out of it; each
# embeds its exact version, which inherently keeps only builds that exist for
# ARCH_FILE and skips the rolling "<minor>-latest" pointers (the manifest lists
# concrete releases only). Captured before parsing (see http_get) so a network error
# aborts instead of masquerading as "no such version".
stable_versions() {
	_json=$(http_get "$STABLE_BASE/bin/versions.json") ||
		die "could not fetch $STABLE_BASE/bin/versions.json (network/HTTP error)"
	printf '%s\n' "$_json" |
		grep -oE "julia-[0-9][^\"/]*-linux-$ARCH_FILE\.tar\.gz" |
		sed -e 's/^julia-//' -e "s/-linux-$ARCH_FILE\\.tar\\.gz\$//" |
		sort -u
}

# pick_stable PREFIX STABLE_ONLY -> greatest matching full version ("" if none).
#   PREFIX: "" (any) | major (1) | major.minor (1.12)
#   STABLE_ONLY=1 excludes prereleases (rc/beta/alpha).
pick_stable() {
	_prefix=$1 _stable_only=$2
	# Assigned on its own line (see http_get) so stable_versions' die isn't swallowed.
	_cands=$(stable_versions)
	[ -n "$_prefix" ] &&
		_cands=$(printf '%s\n' "$_cands" | grep -E "^$(reesc "$_prefix")(\.|$)" || true)
	[ "$_stable_only" = 1 ] &&
		_cands=$(printf '%s\n' "$_cands" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)
	# version_max ends in sed (exit 0), so the no-match case returns success with
	# empty output rather than a nonzero status that, under set -e, would abort the
	# `_full=$(pick_stable ...)` assignment before the caller's own `[ -n "$_full" ]`
	# guard could emit a helpful message.
	printf '%s\n' "$_cands" | grep -v '^$' | version_max
}

# --------------------------------------------------------------------------- #
# Spec parsing & resolution                                                   #
# --------------------------------------------------------------------------- #

# Build the stable download URL for a known full version (e.g. 1.12.6).
resolve_stable_full() {
	_full=$1
	[ -n "$_full" ] || die "no matching stable release for $ARCH_FILE"
	_minor=$(printf '%s' "$_full" | sed -n 's/^\([0-9]*\.[0-9]*\).*/\1/p')
	R_KIND=release
	R_URL="$STABLE_BASE/bin/linux/$ARCH_STABLE/$_minor/julia-$_full-linux-$ARCH_FILE.tar.gz"
	R_ASC_URL="$R_URL.asc"
	# Plain X.Y.Z (no prerelease tag) participates in rollup symlinks.
	case "$_full" in *-*) R_ROLLUP=0 ;; *) R_ROLLUP=1 ;; esac
	R_LABEL="$_full"
}

resolve_nightly() {
	# resolve_nightly [minor]   ("" => master)
	_minor=${1:-}
	R_KIND=nightly
	if [ -n "$_minor" ]; then
		R_URL="$NIGHTLY_BASE/bin/linux/$ARCH_FILE/$_minor/julia-latest-linux-$ARCH_FILE.tar.gz"
		R_LABEL="$_minor-nightly"
	else
		R_URL="$NIGHTLY_BASE/bin/linux/$ARCH_FILE/julia-latest-linux-$ARCH_FILE.tar.gz"
		R_LABEL="nightly"
	fi
	R_ASC_URL="$R_URL.asc"
	R_ROLLUP=0
}

resolve_pr() {
	# Julia's CI uploads each open PR's latest build to a fixed, PR-numbered key
	# in the nightlies bucket (same scheme juliaup uses). No GitHub/Buildkite API
	# and no token required; the file is replaced in place as the PR gets commits,
	# so there is no published sha256 and no GPG signature for it.
	_num=$1
	R_KIND='pr'
	R_URL="$NIGHTLY_BASE/bin/linux/$ARCH_FILE/julia-pr$_num-linux-$ARCH_FILE.tar.gz"
	http_ok "$R_URL" || die \
		"no build published for PR #$_num on $ARCH_FILE (the PR may be closed, or CI hasn't uploaded a build yet)"
	R_ASC_URL="$R_URL.asc"   # checked with http_ok before use; absent for PR builds
	R_ROLLUP=0
	R_LABEL="pr$_num"
}

# resolve_spec SPEC: parse a version specifier and populate R_* globals.
resolve_spec() {
	_spec=$1
	R_KIND=""; R_LABEL=""; R_URL=""; R_ASC_URL=""; R_ROLLUP=0

	# Split off an architecture override: "1.10~aarch64". An explicit ~arch tags the
	# label with what the user typed (~x86, not the canonical ~i686) and opts the
	# build out of the X.Y / X rollups (below); a bare spec autodetects via uname and
	# keeps the bare, rollup-eligible name. So the tag is exactly "was ~arch given".
	#
	# We download by the resolved bucket arch (arch_setup) but label by the literal
	# spelling, so aliases of one arch (~x86/~i686, ~x64/~x86_64) name distinct install
	# dirs - redundant copies of the same binary, which is fine. The rollup opt-out
	# itself happens once R_LABEL is set, below.
	case "$_spec" in
		*"~"*)
			_arch=${_spec##*~}
			# Require a non-empty bare token: it's interpolated into the sed
			# expressions and download URL (a metacharacter could break out of
			# them) and becomes part of the install-dir name. Unknown-but-well-
			# formed arches still pass through.
			case "$_arch" in "" | *[!A-Za-z0-9_]*)
				die "bad arch override in '$_spec' (arch must be one or more of A-Za-z0-9_)" ;;
			esac
			ARCH_SUFFIX="~$_arch"; arch_setup "$_arch"; _spec=${_spec%%~*} ;;
		*)     ARCH_SUFFIX=""; arch_setup ;;
	esac

	case "$_spec" in
		nightly | latest-nightly)
			resolve_nightly "" ;;
		*-nightly)
			_m=${_spec%-nightly}
			case "$_m" in [0-9]*.[0-9]*) resolve_nightly "$_m" ;; *) die "bad nightly spec: $_spec" ;; esac ;;
		pr[0-9]*)
			# Require the whole tail to be digits (the glob only pins the first), so
			# a malformed "pr12ab" is rejected up front rather than 404ing mid-resolve.
			_n=${_spec#pr}
			case "$_n" in *[!0-9]*) die "bad pr spec: $_spec (expected pr<number>)" ;; esac
			resolve_pr "$_n" ;;
		"")
			# No specifier: latest stable release across all majors. Assigned before
			# the call, not inlined as an arg (see http_get), so a network error in
			# pick_stable aborts instead of becoming a misleading "no matching release".
			_full=$(pick_stable "" 1); resolve_stable_full "$_full" ;;
		pre | preview | rc)
			# Greatest version overall, prereleases included.
			_full=$(pick_stable "" 0); resolve_stable_full "$_full" ;;
		[0-9]*.[0-9]*.[0-9]*-*)
			# Fully-qualified prerelease, e.g. 1.13.0-rc1.
			resolve_stable_full "$_spec" ;;
		[0-9]*.[0-9]*.[0-9]*)
			resolve_stable_full "$_spec" ;;
		[0-9]* | [0-9]*.[0-9]*)
			_full=$(pick_stable "$_spec" 1)
			[ -n "$_full" ] || die "no stable release matching '$_spec' for $ARCH_FILE"
			resolve_stable_full "$_full" ;;
		*)
			die "unrecognized version specifier: $_spec" ;;
	esac

	# Apply the ~arch tag and keep the build out of the X.Y / X rollups: those links
	# track the builds you install for this machine (no ~arch), so an arch-pinned one
	# must never hijack them. Its own direct link (julia-<label>~<arch>) is enough.
	if [ -n "$ARCH_SUFFIX" ]; then
		R_LABEL="$R_LABEL$ARCH_SUFFIX"
		R_ROLLUP=0
	fi
	[ -n "$R_URL" ] || die "could not resolve a download URL for '$1'"
}

# --------------------------------------------------------------------------- #
# Download / verify / unpack                                                   #
# --------------------------------------------------------------------------- #

# verify_sig FILE: verify FILE's detached signature against the pinned Julia key.
# Fails closed for builds that are supposed to be signed (release / nightly);
# PR builds publish no signature and are skipped with a warning.
verify_sig() {
	_file=$1
	if [ "$NO_VERIFY" = 1 ]; then
		warn "signature verification disabled (INSTALL_JULIA_NO_VERIFY=1)"
		return 0
	fi
	if [ "$R_KIND" = pr ]; then
		warn "PR builds are not signed; skipping signature verification"
		return 0
	fi
	[ -n "$R_ASC_URL" ] || die "no signature URL for $R_LABEL (refusing to install unverified)"

	_asc="$_file.asc"
	http_get "$R_ASC_URL" >"$_asc" ||
		die "could not download signature from $R_ASC_URL (refusing to install unverified)"

	_keyring="$_file.keyring"
	julia_keyring >"$_keyring" || die "could not materialize signing keyring"

	# The keyring holds only the official Julia key and gpgv trusts every key it
	# is given, so a zero exit status means "validly signed by Julia's key" - the
	# key identity is bound by the keyring contents, no separate fpr check needed.
	if gpgv --keyring "$_keyring" "$_asc" "$_file" >/dev/null 2>&1; then
		info "GPG signature OK ($GPG_FPR)"
	else
		die "signature verification FAILED for $(basename "$_file") - refusing to install"
	fi
}

# install_resolved: download R_URL, verify, and unpack into DEST_DIR. Uses the
# .incoming.* / .old.* staging paths set by cmd_install (all inside INSTALL_DIR,
# so every move is a same-filesystem rename).
install_resolved() {
	_destname=$(basename "$DEST_DIR")

	# Reap leftover scratch before reusing these paths. This is where the slow
	# rm -rf lives - at the start of an install you're already committed to, not on
	# the Ctrl-C path. We reap: this version's .incoming from a hard kill that
	# skipped cleanup (the lock makes it exclusively ours), plus all .old.* garbage
	# (parked old versions and trees that cleanup renamed aside, from any version --
	# always inert, so reaping them all is safe). Also frees disk before download.
	rm -rf "$INCOMING_DIR" "$INSTALL_DIR"/.old.* 2>/dev/null || :

	info "Downloading $R_URL"
	http_download "$R_URL" "$STAGE_TAR" || die "download failed"
	verify_sig "$STAGE_TAR"

	info "Unpacking"
	# --strip-components=1 drops the tarball's leading julia-X.Y.Z/ dir so the tree
	# lands directly in .incoming.julia-<label>, which we then rename into place.
	mkdir -p "$INCOMING_DIR"
	tar -xzf "$STAGE_TAR" --strip-components=1 -C "$INCOMING_DIR" || die "failed to extract tarball"
	[ -x "$INCOMING_DIR/bin/julia" ] || die "unexpected tarball layout (no bin/julia)"

	# Version read from the tarball's own top-level dir name (Julia names it after the
	# version) - never by running the binary. Used for display, and below to bind a
	# release tarball to the version we asked for.
	_realver=$(tar -tzf "$STAGE_TAR" 2>/dev/null | sed -n '1s#^julia-\([^/]*\)/.*#\1#p')

	# Version-binding: GPG proves the tarball is a genuine Julia build but not *which*
	# one, so a hostile endpoint could serve a different (older, still-signed) release
	# than requested. For stable/prerelease builds the tarball dir IS the version, so
	# require it to equal the resolved label (sans any ~arch tag); fail closed on a
	# mismatch or a missing version. Rolling builds (nightly/pr) carry a fluid
	# dev version with no such invariant, so the binding doesn't apply to them.
	if [ "$R_KIND" = release ]; then
		_want=${R_LABEL%"$ARCH_SUFFIX"}
		[ "$_realver" = "$_want" ] ||
			die "version mismatch: requested $_want but tarball reports '${_realver:-unknown}' - refusing to install"
	fi
	[ -n "$_realver" ] || _realver=$R_LABEL

	# Swap: rename(2) can't overwrite a non-empty dir, so on a refresh park the old
	# version at .old.* first, then rename the new one in. Both are same-fs renames,
	# so the only window where DEST_DIR is absent is a single syscall. If the second
	# rename fails the version is left missing (the parked .old is reaped at the next
	# install) - re-running heals it; we never reconstruct state from .old.
	if [ -d "$DEST_DIR" ]; then
		info "$_destname already installed; refreshing"
		mv "$DEST_DIR" "$OLD_DIR" || die "could not move aside existing $_destname"
	fi
	mv "$INCOMING_DIR" "$DEST_DIR" || die "could not install into $DEST_DIR"
	info "Installed $_realver -> $DEST_DIR"
}

# --------------------------------------------------------------------------- #
# Symlink management                                                          #
# --------------------------------------------------------------------------- #

link() {
	# link NAME TARGET - atomically create/replace SYMLINK_DIR/NAME -> TARGET.
	# `ln -sfn` is unlink()+symlink(), leaving a brief window with no link at all;
	# create a temp link and rename() it over NAME instead, so a concurrent reader
	# (or `julia` invocation) never sees the link missing. This is what keeps a
	# normal install gapless: a new stable version only flips the julia / julia-1 /
	# julia-X.Y links, and each flip is atomic. (A same-name *refresh* - i.e. a
	# nightly/pr update - still has a tiny gap while its directory is swapped, which
	# is fine: those are testing builds, not production.)
	mkdir -p "$SYMLINK_DIR"
	_tmp="$SYMLINK_DIR/.$1.tmp.$$"
	# -f so a stale temp left by a crashed run (or a reused PID) is overwritten
	# rather than aborting the install.
	ln -sf "$2" "$_tmp" || die "could not create symlink $1"
	mv "$_tmp" "$SYMLINK_DIR/$1" || { rm -f "$_tmp"; die "could not place symlink $1"; }
	info "symlink $1 -> $2"
}

# Ensure the NAME rollup points at VER or newer. Each install only concerns its
# own version (no scan of all installed versions), so concurrent installs don't
# fight over a shared max. readlink+link isn't atomic, so a concurrent same-line
# install can clobber between our read and write - loop until the link RESOLVES to
# an existing target at VER-or-newer (a peer installing something newer counts as
# done; a dangling or missing link falls through and is recreated, which is how a
# re-run self-heals). Removal never repoints rollups (it just deletes referring
# links), so this only ever raises - never the wrong direction.
raise_rollup() {
	_i=0
	while [ "$_i" -lt 100 ]; do
		_cur=$(readlink "$SYMLINK_DIR/$1" 2>/dev/null | sed -n 's#.*/julia-\(.*\)/bin/julia$#\1#p')
		[ -e "$SYMLINK_DIR/$1" ] && [ -n "$_cur" ] &&
			[ "$(printf '%s\n%s\n' "$_cur" "$2" | version_max)" = "$_cur" ] && break
		link "$1" "$INSTALL_DIR/julia-$2/bin/julia"
		_i=$((_i + 1))
	done
}

# Create the direct + rollup symlinks for an installed build.
make_symlinks() {
	_destname=$1            # install dir name, e.g. julia-1.12.6 / julia-nightly
	_label=$2              # short id for the direct symlink (1.12.6 / nightly / pr1234)
	link "julia-$_label" "$INSTALL_DIR/$_destname/bin/julia"
	if [ "$R_ROLLUP" = 1 ]; then
		_xy=$(printf '%s' "$_label" | sed 's/\.[0-9]*$//')   # 1.12.6 -> 1.12
		_x=$(printf '%s' "$_label" | sed 's/\..*//')          # 1.12.6 -> 1
		raise_rollup "julia-$_xy" "$_label"
		raise_rollup "julia-$_x" "$_label"
	fi
	return 0
}

set_default() { link "julia" "$1"; }

# --------------------------------------------------------------------------- #
# Commands                                                                    #
# --------------------------------------------------------------------------- #

# Resolve an installed version from a partial id; echo its install dir name.
# Used by `switch`, which targets a single build: an exact id wins, else the
# *greatest* installed stable patch matching a numeric prefix.
find_installed() {
	_q=$1
	# exact match first
	[ -d "$INSTALL_DIR/julia-$_q" ] && { printf 'julia-%s\n' "$_q"; return 0; }
	# else greatest installed stable matching the prefix
	_v=$(ls "$INSTALL_DIR" 2>/dev/null |
		sed -n 's/^julia-\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' |
		grep -E "^$(printf '%s' "$_q" | sed 's/\./\\./g')(\.|$)" | version_max)
	[ -n "$_v" ] && { printf 'julia-%s\n' "$_v"; return 0; }
	return 1
}

# List *every* installed build matching a removal query, one "julia-<id>" per line,
# ascending. A pure-numeric prefix (1, 1.12, 1.12.6) sweeps every build under it --
# releases, prereleases, the branch nightly, and ALL arches - so `remove 1.12`
# clears the whole 1.12 line (1.12.x, 1.12.x-rcN, 1.12-nightly, and any ~arch copy).
# Matching is on component boundaries, so `1.1` never catches `1.10.0`. The master
# nightly and pr builds carry no numeric prefix, so they (and any fully-
# qualified id) are matched only by exact name. Nonzero if nothing matches.
match_installed() {
	_q=$1
	case "$_q" in
		*[!0-9.]*) ;;   # not pure-numeric -> exact match only (handled below)
		*)
			# Pure-numeric prefix: sweep every build whose version starts with it
			# at a component boundary ('.' or '-'), with any ~arch tag stripped first.
			_hits=$(ls "$INSTALL_DIR" 2>/dev/null | sed -n 's/^julia-//p' |
				while IFS= read -r _id; do
					case "${_id%%~*}" in
						"$_q" | "$_q".* | "$_q"-*) printf 'julia-%s\n' "$_id" ;;
					esac
				done | sort -V)
			[ -n "$_hits" ] && { printf '%s\n' "$_hits"; return 0; } ;;
	esac
	# Exact id: a fully-qualified prerelease/~arch name, a rolling build, or a
	# numeric token with no swept match above.
	[ -d "$INSTALL_DIR/julia-$_q" ] && { printf 'julia-%s\n' "$_q"; return 0; }
	return 1
}

cmd_install() {
	# cmd_install SPEC SETDEFAULT
	_spec=$1 _setdefault=$2
	resolve_spec "$_spec"
	info "Resolved '$_spec' -> $R_LABEL ($R_KIND)"

	# Take the per-version lock before prompting, so a concurrent op on the same
	# version fails fast instead of bothering the user with a prompt it can't honor.
	mkdir -p "$INSTALL_DIR"
	_destname="julia-$R_LABEL"
	lock_version "$_destname"

	if ! confirm "Install $R_LABEL into $INSTALL_DIR and link in $SYMLINK_DIR?"; then
		info "Aborted."; exit 0
	fi

	# The .incoming.* / .old.* names are hidden and not julia-* prefixed, so the
	# list/remove/rollup scans ignore them. Set here in the parent shell (not a
	# subshell) so the EXIT trap can see and clean them.
	DEST_DIR="$INSTALL_DIR/$_destname"
	INCOMING_DIR="$INSTALL_DIR/.incoming.$_destname"
	OLD_DIR="$INSTALL_DIR/.old.$_destname"
	STAGE_TAR="$INCOMING_DIR.tar.gz"

	install_resolved
	make_symlinks "$_destname" "$R_LABEL"
	if [ "$_setdefault" = 1 ]; then
		set_default "$INSTALL_DIR/$_destname/bin/julia"
		info "Default 'julia' now points to $R_LABEL"
	fi
	_check_path
}

cmd_switch() {
	_target=$1
	# Anything containing a '/' is a path to a julia binary; everything else is
	# an installed-version id. (Use ./julia to point at a binary in the cwd.)
	case "$_target" in
		*/*)
			[ -e "$_target" ] || die "$_target: no such file"
			[ -x "$_target" ] || die "$_target is not executable"
			case "$_target" in /*) _abs=$_target ;; *) _abs="$PWD/$_target" ;; esac
			set_default "$_abs"
			info "Default 'julia' now points to $_abs"
			return 0 ;;
	esac
	_destname=$(find_installed "$_target") ||
		die "no installed version matching '$_target' (switch never installs; try: install-julia.sh add $_target)"
	set_default "$INSTALL_DIR/$_destname/bin/julia"
	info "Default 'julia' now points to ${_destname#julia-}"
}

# Remove one already-resolved build (dir name like julia-1.12.6 / julia-nightly).
remove_one() {
	_destname=$1
	# Take the same per-version lock install uses, so remove can't race a concurrent
	# install/remove of this version. (Each version locks independently; in a batch
	# remove the versions are taken one at a time.)
	lock_version "$_destname"
	_dest="$INSTALL_DIR/$_destname"

	# Reverse of install: drop the referring symlinks *before* the directory, so
	# nothing ever resolves through a link into a half-deleted tree. We do not
	# repoint rollups to an older remaining patch - removing a version simply drops
	# its links (a missing link is trivially repaired by the next install; a
	# dangling one is not). Direct, rollup, and default links are all handled here.
	if [ -d "$SYMLINK_DIR" ]; then
		for _l in "$SYMLINK_DIR"/julia "$SYMLINK_DIR"/julia-*; do
			[ -L "$_l" ] || continue
			case "$(readlink "$_l")" in "$_dest"/*) rm -f "$_l"; info "removed symlink $(basename "$_l")" ;; esac
		done
	fi
	rm -rf "$_dest"
	# Mop up this version's .incoming (ours; we hold its lock) and all inert .old.* (as install does).
	rm -rf "$INSTALL_DIR/.incoming.$_destname" "$INSTALL_DIR/.incoming.$_destname.tar.gz"* \
	       "$INSTALL_DIR"/.old.* 2>/dev/null || :
	info "Removed $_destname"
	# Delete our own lockfile last. Safe: we still hold the flock (so a concurrent
	# acquirer fails) and acquirers revalidate the inode (see lock_version), so this
	# never lets two operations run at once. The rm only drops the name; the lock is
	# held until FD 9 is reassigned or the process exits.
	rm -f "$INSTALL_DIR/.lock.$_destname"
}

cmd_remove() {
	_target=$1
	# A bare numeric prefix expands to every build under it (releases, prereleases,
	# the branch nightly, all arches); a non-numeric id (master nightly / pr... /
	# fully-qualified prerelease or ~arch) matches just itself. See match_installed.
	_matches=$(match_installed "$_target") || die "no installed version matching '$_target'"
	_n=$(printf '%s\n' "$_matches" | grep -c .)

	# One confirmation for the whole batch; -y (NO_CONFIRM) skips it. List the set so
	# a prefix that swept up several patches is never a surprise.
	if [ "$_n" -gt 1 ]; then
		info "$_n installed versions match '$_target':"
		printf '%s\n' "$_matches" | sed 's/^julia-/    /' >&2
		confirm "Remove all $_n and their symlinks?" || { info "Aborted."; exit 0; }
	else
		confirm "Remove $INSTALL_DIR/$_matches and its symlinks?" || { info "Aborted."; exit 0; }
	fi

	# Version ids carry no spaces or glob metacharacters, so word-splitting the list
	# is safe; staying out of a subshell keeps `die` (e.g. a lock conflict) fatal to
	# the whole batch rather than just one iteration.
	for _destname in $_matches; do
		remove_one "$_destname"
	done
}

cmd_list() {
	if [ ! -d "$INSTALL_DIR" ]; then echo "No versions installed."; return 0; fi
	_default=""
	[ -L "$SYMLINK_DIR/julia" ] && _default=$(readlink "$SYMLINK_DIR/julia")
	ls "$INSTALL_DIR" 2>/dev/null | sed -n 's/^julia-//p' | sort -V | while read -r _v; do
		_mark=" "
		[ "$_default" = "$INSTALL_DIR/julia-$_v/bin/julia" ] && _mark="*"
		printf ' %s %s\n' "$_mark" "$_v"
	done
}

# Warn if SYMLINK_DIR is not on PATH.
_check_path() {
	case ":$PATH:" in
		*":$SYMLINK_DIR:"*) : ;;
		*) warn "$SYMLINK_DIR is not on your PATH; add it, e.g.:"
		   printf '       export PATH="%s:$PATH"\n' "$SYMLINK_DIR" >&2 ;;
	esac
}

# --------------------------------------------------------------------------- #
# Argument parsing                                                            #
# --------------------------------------------------------------------------- #

usage() {
	cat <<'EOF'
Usage: install-julia.sh [options] [command] [version]

Install and manage Julia versions on Linux.

Commands:
  install-julia.sh <version>          install <version>, make it the default
  install-julia.sh add <version>      install <version>, keep current default
  install-julia.sh switch <ver|path>  point default julia at an installed
                                      version or a path to a julia binary
  install-julia.sh remove <version>   delete a version and its symlinks
  install-julia.sh list               list installed versions
  install-julia.sh                    install the latest stable release

Options:
  -h, --help     show this help and exit
  -v, --version  show version and exit
  -y, --yes      do not prompt for confirmation

Versions:
  1  1.12  1.12.6  1.13.0-rc1  pre  nightly  1.11-nightly  pr<num>
  (append ~x86_64, ~x86, or ~aarch64 to override the architecture)

See README.md for full documentation.
EOF
}

main() {
	# Pull out global flags anywhere on the line; keep positionals in order.
	_positional=""
	while [ $# -gt 0 ]; do
		case "$1" in
			-h | --help) usage; exit 0 ;;
			-v | --version) printf 'install-julia.sh %s\n' "$SELF_VERSION"; exit 0 ;;
			-y | --yes) NO_CONFIRM=1 ;;
			--) shift; while [ $# -gt 0 ]; do _positional="$_positional $1"; shift; done; break ;;
			-*) die "unknown option: $1 (try --help)" ;;
			*) _positional="$_positional $1" ;;
		esac
		shift
	done
	# Disable globbing for the re-split so a spec containing a glob metacharacter
	# isn't expanded against the cwd; restore it afterwards (cmd_remove globs).
	set -f
	# shellcheck disable=SC2086
	set -- $_positional
	set +f

	# Check every hard dependency up front, before any command runs, so a missing
	# tool surfaces immediately instead of partway through an operation. gpgv/base64
	# are needed only when signature verification is on (the default).
	need curl
	need tar
	need flock
	[ "$NO_VERIFY" = 1 ] || { need gpgv; need base64; }

	case "${1:-}" in
		add)
			[ $# -ge 2 ] || die "usage: install-julia.sh add <version>"
			cmd_install "$2" 0 ;;
		switch)
			[ $# -ge 2 ] || die "usage: install-julia.sh switch <version|path>"
			cmd_switch "$2" ;;
		remove | rm | uninstall)
			[ $# -ge 2 ] || die "usage: install-julia.sh remove <version>"
			cmd_remove "$2" ;;
		list | ls)
			cmd_list ;;
		"")
			cmd_install "" 1 ;;             # default: latest stable, set default
		*)
			cmd_install "$1" 1 ;;           # install-julia.sh <version>
	esac
}

main "$@"
