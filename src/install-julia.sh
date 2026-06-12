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
NO_VERIFY=${INSTALL_JULIA_NO_VERIFY:-0}

# Service endpoints. All overridable via the environment so the script can be
# pointed at a mirror or a private cache. Trailing slashes are stripped.
STABLE_BASE=${INSTALL_JULIA_STABLE_URL:-"https://julialang-s3.julialang.org"}
NIGHTLY_BASE=${INSTALL_JULIA_NIGHTLY_URL:-"https://julialangnightlies-s3.julialang.org"}
STABLE_BASE=${STABLE_BASE%/}; NIGHTLY_BASE=${NIGHTLY_BASE%/}

# The official Julia binary signing key, dearmored to a binary keyring for gpgv.
# Fingerprint: 3673DF529D9049477F76B37566E3C7DC03D6E495
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

NO_CONFIRM=0
REINSTALL=0

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

# --------------------------------------------------------------------------- #
# Output helpers                                                              #
# --------------------------------------------------------------------------- #

info() { printf '==> %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

confirm() {
	# confirm "question" -> 0 if yes. Read the answer strictly from the controlling
	# terminal (/dev/tty), never from stdin: under `curl ... | sh` stdin is the script
	# source, and a stdin fallback would consume the next script line as the answer.
	# No tty means we can't ask, so exit 1 and point at -y for non-interactive use.
	[ "$NO_CONFIRM" -eq 1 ] && return 0
	if ! ( : </dev/tty ) 2>/dev/null; then
		warn "no terminal available to confirm; exiting (pass -y to proceed non-interactively)"
		exit 1
	fi
	printf '%s [y/N] ' "$1" >&2
	if ! read -r _confirm_ans </dev/tty; then
		printf '\n' >&2
		return 1
	fi
	case "$_confirm_ans" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# --------------------------------------------------------------------------- #
# Low-level utilities                                                         #
# --------------------------------------------------------------------------- #

have() { command -v "$1" >/dev/null 2>&1; }

need() { have "$1" || die "required command not found: $1"; }

# http_get URL -> body on stdout; nonzero on HTTP/transport error.
# --max-filesize caps a hostile endless response; 100M >> the versions.json
http_get() { curl -fsSL --retry 3 --max-filesize 100M "$1"; }

# http_download URL DEST. --max-filesize caps it; 3G >> any build.
http_download() { curl -fL --retry 3 --progress-bar --max-filesize 3G -o "$2" "$1"; }

# http_ok URL -> 0 if a HEAD request returns success
http_ok() {
	curl -fsIL -o /dev/null "$1" 2>/dev/null
}

# Compare versions in semver precedence order, in-shell, so picking the greatest
# needs no `sort -V` (a GNU extension) - no sort at all.

# _lex_lt A B: true iff A sorts strictly before B in ASCII order. Walk both
# strings; at the first differing character compare the two bytes (printf '%d'
# "'c" is the POSIX way to read a char's value), and a string that runs out
# first is the smaller (it is a prefix of the other).
_lex_lt() {
	_lex_lt_a=$1; _lex_lt_b=$2
	while : ; do
		[ -z "$_lex_lt_b" ] && return 1
		[ -z "$_lex_lt_a" ] && return 0
		_lex_lt_ca=${_lex_lt_a%"${_lex_lt_a#?}"}; _lex_lt_cb=${_lex_lt_b%"${_lex_lt_b#?}"}
		if [ "$_lex_lt_ca" != "$_lex_lt_cb" ]; then
			[ "$(printf '%d' "'$_lex_lt_ca")" -lt "$(printf '%d' "'$_lex_lt_cb")" ]
			return
		fi
		_lex_lt_a=${_lex_lt_a#?}; _lex_lt_b=${_lex_lt_b#?}
	done
}

is_alphanumdashdot() {
	case "$1" in
		*[!0-9A-Za-z.-]*) return 1 ;;     # any char outside the set
		*) return 0 ;;
	esac
}

is_numsegment() {
	case "$1" in
		'') return 1 ;; # reject empty
		*[!0-9]*) return 1 ;; # any char outside the set
		0) return 0 ;;
		0*) return 1 ;; # no leading zeros
		*) return 0 ;;
	esac
}

is_prereleasesegment() {
	case "$1" in
		'') return 1 ;; # reject empty
		*[!0-9A-Za-z-]*) return 1 ;; # any char outside the set
		*[!0-9]*) return 0 ;; # non numeric
		0) return 0 ;;
		0*) return 1 ;; # no leading zeros
		*) return 0 ;; # valid numeric
	esac
}

# check if valid semver build metadata suffix is currently not supported
is_version() {
	is_alphanumdashdot "$1" || return 1
	case "$1" in
		*.*.*) : ;;
		*) return 1 ;;
	esac
	check_version_rest="$1"
	is_numsegment "${check_version_rest%%.*}" || return 1
	check_version_rest=${check_version_rest#*.}
	is_numsegment "${check_version_rest%%.*}" || return 1
	check_version_rest=${check_version_rest#*.}
	# Y-pre
	is_numsegment "${check_version_rest%%-*}" || return 1
	check_version_rest=${check_version_rest#"${check_version_rest%%-*}"}
	# -pre or empty
	[ -z "$check_version_rest" ] && return 0
	# -pre
	check_version_rest=${check_version_rest#-}
	# pre
	case "$check_version_rest" in
		*. | .* | *..* | '') return 1 ;;
		*) : ;;
	esac
	# check prerelease
	while : ; do
		is_prereleasesegment "${check_version_rest%%.*}" || return 1
		case "$check_version_rest" in
			*.*) check_version_rest=${check_version_rest#*.} ;;  # more segments: drop this one + its dot
			*)   break ;;                                        # last segment: done
		esac
	done
	return 0
}


# version_gt A B: return 0 iff version A is strictly greater than B.
# Die if A or B are not valid semver versions or contain a build metadata suffix.
# One pass over both versions a field at a time.
version_gt() {
	# validation to get started
	is_version "$1" || die "could not parse version $1"
	is_version "$2" || die "could not parse version $2"
	[ "$1" = "$2" ] && return 1
	version_gt_a=$1; version_gt_b=$2
	version_gt_state=core
	while : ; do
		# Leading field and the separator after it. In the core a field ends at a
		# '.', the '-' that opens the prerelease; in
		# the prerelease only at a '.', because a '-' there is a legal
		# identifier character (e.g. the tag x-y-z.--), not a separator.
		if [ "$version_gt_state" = core ]; then
			version_gt_fa=${version_gt_a%%[.-]*}; version_gt_fb=${version_gt_b%%[.-]*}
		else
			version_gt_fa=${version_gt_a%%.*};  version_gt_fb=${version_gt_b%%.*}
		fi
		version_gt_ra=${version_gt_a#"$version_gt_fa"}; version_gt_sa=${version_gt_ra%"${version_gt_ra#?}"}
		version_gt_rb=${version_gt_b#"$version_gt_fb"}; version_gt_sb=${version_gt_rb%"${version_gt_rb#?}"}
		if [ "$version_gt_fa" != "$version_gt_fb" ]; then
			if [ "$version_gt_state" = core ]; then
				[ "$version_gt_fa" -gt "$version_gt_fb" ]; return       # numeric core field
			fi
			version_gt_na=0; case $version_gt_fa in *[!0-9]*) version_gt_na=1 ;; esac  # 1 = has a non-digit
			version_gt_nb=0; case $version_gt_fb in *[!0-9]*) version_gt_nb=1 ;; esac
			if [ "$version_gt_na" != "$version_gt_nb" ]; then [ "$version_gt_na" -gt "$version_gt_nb" ]; return; fi  # numeric < alnum
			if [ "$version_gt_na" = 0 ]; then [ "$version_gt_fa" -gt "$version_gt_fb" ]; return; fi  # both numeric
			if _lex_lt "$version_gt_fa" "$version_gt_fb"; then return 1; else return 0; fi  # both alnum, ASCII
		fi
		# Fields equal: the following separators decide.
		if [ "$version_gt_sa" = "$version_gt_sb" ]; then
			[ -z "$version_gt_sa" ] && return 1               # both versions end: equal
			[ "$version_gt_sa" = - ] && version_gt_state=pre  # both enter the prerelease
			version_gt_a=${version_gt_ra#?}; version_gt_b=${version_gt_rb#?}   # drop the shared separator
			continue
		fi
		[ "$version_gt_sa" = - ] && return 1   # A enters a prerelease, B does not: A is lower
		[ "$version_gt_sb" = - ] && return 0   # B enters a prerelease, A does not: A is higher
		# length mismatch longer wins
		if [ -n "$version_gt_sa" ]; then
			return 0
		else
			return 1
		fi
	done
}

# Read versions on stdin, print the greatest. Empty input prints an empty line
# and returns 0 - callers guard with [ -n "$result" ] - so a no-match never
# aborts under set -e. A plain fold, no sort.
version_max() {
	version_max_best=''
	while IFS= read -r version_max_v; do
		[ -n "$version_max_v" ] || continue
		if [ -z "$version_max_best" ] || version_gt "$version_max_v" "$version_max_best"; then
			version_max_best=$version_max_v
		fi
	done
	printf '%s\n' "$version_max_best"
}

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
	# Break the JSON on quotes and slashes so every string token and path component
	# lands on its own line, then strip the bare tarball filenames to their version.
	# (POSIX sed can't emit multiple matches per line the way GNU `grep -o` can, so
	# tr - which is POSIX - does the splitting first.) The leading [0-9] keeps this
	# to concrete releases and skips any rolling "julia-latest-..." pointer.
	# Keep only versions is_version can parse: version_max dies on anything it
	# can't compare, so one weird manifest entry (e.g. a future +build suffix)
	# would otherwise break every discovery spec. Skip-and-warn instead.
	printf '%s\n' "$_json" |
		tr '"/' '\n\n' |
		sed -n "s/^julia-\\([0-9].*\\)-linux-$ARCH_FILE\\.tar\\.gz\$/\\1/p" |
		sort -u |
		while IFS= read -r _sv; do
			if is_version "$_sv"; then
				printf '%s\n' "$_sv"
			else
				warn "ignoring unparseable version '$_sv' in versions.json"
			fi
		done
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
	# version_max returns success with empty output for empty input, so the
	# no-match case doesn't return a nonzero status that, under set -e, would abort
	# the `_full=$(pick_stable ...)` assignment before the caller's own
	# `[ -n "$_full" ]` guard could emit a helpful message.
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
	# Julia's CI uploads some PR's latest build to a fixed, PR-numbered key
	# in the nightlies bucket.
	_num=$1
	R_KIND='pr'
	R_URL="$NIGHTLY_BASE/bin/linux/$ARCH_FILE/julia-pr$_num-linux-$ARCH_FILE.tar.gz"
	http_ok "$R_URL" || die \
		"no build published for PR #$_num on $ARCH_FILE (the PR may be closed, or CI hasn't uploaded a build yet)"
	R_ASC_URL="$R_URL.asc"
	R_ROLLUP=0
	R_LABEL="pr$_num"
}

# resolve_spec SPEC: parse a version specifier and populate R_* globals.
resolve_spec() {
	_spec=$1
	R_KIND=""; R_LABEL=""; R_URL=""; R_ASC_URL=""; R_ROLLUP=0

	# Reject any path-shaped spec outright: case globs match '/', so a spec like
	# "1.2.3/../evil" would otherwise fall into the version patterns below and
	# end up in install-dir names, where the slash escapes INSTALL_DIR.
	case "$_spec" in */*) die "bad version specifier: $_spec" ;; esac

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
			# Everything after the LEFTMOST ~ is the arch token (a version never
			# contains ~), so a stray second ~ ("1.0.0~x86~x64") lands inside the
			# token and is rejected below instead of being silently dropped.
			_arch=${_spec#*~}
			# Require a non-empty bare token: it's interpolated into the sed
			# expressions and download URL (a metacharacter could break out of
			# them) and becomes part of the install-dir name. Unknown-but-well-
			# formed arches still pass through.
			case "$_arch" in "" | *[!A-Za-z0-9_-]*)
				die "bad arch override in '$_spec' (arch must be one or more of A-Za-z0-9_-)" ;;
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
	gpgv --keyring "$_keyring" "$_asc" "$_file" >/dev/null ||
		die "signature verification FAILED for $(basename "$_file") - refusing to install"
}

# install_resolved DESTNAME: download R_URL, verify it, and claim
# INSTALL_DIR/DESTNAME. All scratch lives inside INSTALL_DIR (so every move is a
# same-filesystem rename), under hidden, non-julia-* names that the
# list/remove/rollup scans ignore. Staging is two-level: .incoming.<destname>/
# is the version's staging namespace - an exact, unambiguous name, so no
# pattern matching is ever needed to find a version's staging - and each
# attempt gets its own mktemp-unique subdir inside it holding the tarball,
# signature, keyring and unpacked tree, so no two processes ever share staging
# paths. The unpacked tree itself is named <destname>, and the final `mv` into
# INSTALL_DIR either lands it at its final path or fails if the version
# appeared concurrently - rename(2) never nests or merges. A successful install
# deletes its own scratch; anything left behind (crash, Ctrl-C) is reaped by
# the next install or remove of the same version. No locks: same-version
# operations race by clobber and the loser dies, while different versions never
# share paths and proceed in parallel.
install_resolved() {
	_destname=$1
	_dest="$INSTALL_DIR/$_destname"
	_ns="$INSTALL_DIR/.incoming.$_destname"

	# Reap leftovers before staging. First sweep the inert .old.* garbage (any
	# version - always safe) to free disk, then yank this version's whole staging
	# namespace aside with a single rename - so a leftover tree is either whole at
	# an installable path or whole in the inert .old.* namespace, never
	# half-deleted somewhere a concurrent claim could pick it up - and a second
	# sweep deletes what was just yanked. Yanking a live same-version peer's
	# staging is deliberate: same-version operations race by clobber, and the
	# loser dies at its next step instead of corrupting anything.
	rm -rf "$INSTALL_DIR"/.old.* 2>/dev/null || :
	_scratch=$(mktemp -d "$INSTALL_DIR/.old.XXXXXXXXXX") ||
		die "could not create scratch dir in $INSTALL_DIR"
	mv "$_ns" "$_scratch/" 2>/dev/null || :
	rm -rf "$INSTALL_DIR"/.old.* 2>/dev/null || :

	mkdir -p "$_ns" || die "could not create staging namespace $_ns"
	_parent=$(mktemp -d "$_ns/XXXXXXXXXX") || die "could not create staging dir in $_ns"
	_tree="$_parent/$_destname"
	_tar="$_parent/stage.tar.gz"
	mkdir "$_tree" || die "could not create staging directory $_tree"
	info "Downloading $R_URL"
	http_download "$R_URL" "$_tar" || die "download failed"
	verify_sig "$_tar"

	info "Unpacking"
	# --strip-components=1 drops the tarball's leading julia-X.Y.Z/ dir so the tree
	# lands directly in the staging tree, which is named <destname> for the claim below.
	tar -xzf "$_tar" --strip-components=1 -C "$_tree" || die "failed to extract tarball"
	[ -x "$_tree/bin/julia" ] || die "unexpected tarball layout (no bin/julia)"

	# Version read from the tarball's own top-level dir name (Julia names it after the
	# version) - never by running the binary. Used for display, and below to bind a
	# release tarball to the version we asked for. Some tar writers list the dir
	# entry without a trailing slash, so the slash is not part of the match.
	_realver=$(tar -tzf "$_tar" 2>/dev/null | sed -n '1s#^julia-\([^/]*\).*#\1#p')

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

	# Swap the unpacked tree into place. The tree is named <destname> and moved to
	# INSTALL_DIR itself, so mv computes the final path as the target and rename(2)
	# either lands it there atomically or fails outright (ENOTEMPTY) if the version
	# appeared concurrently - the POSIX-portable equivalent of mv -T, with no way
	# to nest or merge. Two cases:
	#
	#   * First install (no DEST yet): a single rename(2). No window.
	#
	#   * Refresh (DEST exists): rename(2) can't overwrite a non-empty dir, so park the
	#     old version in a fresh .old.* scratch dir first, then rename the new one in.
	#     DEST is absent for the single syscall between the two renames, so a
	#     concurrent `julia` can momentarily get ENOENT. We don't bother closing that
	#     window with an atomic `mv --exchange`: a refresh only happens on --reinstall
	#     or a rolling nightly/pr update (an already-present stable version skips the
	#     download entirely), so casual users never reach this path and anyone who
	#     does can just re-run. If power is lost between the two renames the version
	#     is left missing, and the parked .old is reaped on the next install.
	# -f on the claims so a stray unwritable file at the destination fails
	# outright instead of making mv prompt; collisions still fail (rename(2)
	# never overwrites a non-empty directory).
	if [ ! -d "$_dest" ]; then
		mv -f "$_tree" "$INSTALL_DIR/" || die "could not install into $_dest"
	else
		info "$_destname already installed; refreshing"
		_old=$(mktemp -d "$INSTALL_DIR/.old.XXXXXXXXXX") ||
			die "could not create scratch dir in $INSTALL_DIR"
		mv "$_dest" "$_old/" || die "could not move aside existing $_destname"
		mv -f "$_tree" "$INSTALL_DIR/" || die "could not install into $_dest"
		rm -rf "$_old" 2>/dev/null || :
	fi
	# Success: our staging subdir now holds only the tarball, signature and keyring;
	# delete it so a completed install leaves no litter, and drop the namespace dir
	# if we were the last one staging in it (rmdir only removes it when empty, so a
	# live peer's staging is never touched). A crash before this line leaves the
	# scratch for the next same-version install's or remove's reap.
	rm -rf "$_parent" 2>/dev/null || :
	rmdir "$_ns" 2>/dev/null || :
	info "Installed $_realver -> $_dest"
}

# --------------------------------------------------------------------------- #
# Symlink management                                                          #
# --------------------------------------------------------------------------- #

link() {
	# link NAME TARGET - create/replace SYMLINK_DIR/NAME -> TARGET, atomically.
	# Not `ln -sfn` (unlink+symlink: NAME briefly missing, racing links can
	# die on EEXIST). Build the link in scratch and rename(2) it into place:
	# the scratch link is itself named NAME and mv's stated target is
	# SYMLINK_DIR (install_resolved's trick, in lieu of the non-POSIX -T), so
	# rename replaces an existing NAME without dereferencing it. A hard kill
	# can leak a .link.* scratch dir; never reaped (it may be a live peer's),
	# but tiny, hidden, and off every scan.
	mkdir -p "$SYMLINK_DIR"
	_lnk=$(mktemp -d "$SYMLINK_DIR/.link.XXXXXXXXXX") ||
		die "could not create scratch dir in $SYMLINK_DIR"
	if ! ln -s "$2" "$_lnk/$1" || ! mv -f "$_lnk/$1" "$SYMLINK_DIR/"; then
		rm -rf "$_lnk" 2>/dev/null || :
		die "could not create symlink $1"
	fi
	rmdir "$_lnk" 2>/dev/null || :
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
			# Sort the bare ids (POSIX numeric sort, by dotted field; the julia-
			# prefix would defeat -k1,1n) and re-add the prefix afterward.
			_hits=$(ls "$INSTALL_DIR" 2>/dev/null | sed -n 's/^julia-//p' |
				while IFS= read -r _id; do
					case "${_id%%~*}" in
						"$_q" | "$_q".* | "$_q"-*) printf '%s\n' "$_id" ;;
					esac
				done | sort -t. -k1,1n -k2,2n -k3,3n | sed 's/^/julia-/')
			[ -n "$_hits" ] && { printf '%s\n' "$_hits"; return 0; } ;;
	esac
	# Exact id: a fully-qualified prerelease/~arch name, a rolling build, or a
	# numeric token with no swept match above.
	[ -d "$INSTALL_DIR/julia-$_q" ] && { printf 'julia-%s\n' "$_q"; return 0; }
	return 1
}

cmd_install() {
	# cmd_install SPEC SETDEFAULT. The spec is read from $1 both times, never
	# copied into a named variable: shell variables are global, and resolve_spec
	# strips ~arch from its own _spec - which would alias a copy here and make
	# the message below misquote what the user typed.
	_setdefault=$2
	resolve_spec "$1"
	info "Resolved '$1' -> $R_LABEL ($R_KIND)"
	mkdir -p "$INSTALL_DIR"
	_destname="julia-$R_LABEL"
	# A stable release is immutable, so once its dir exists the resolved label is that
	# same build and there is nothing to download. Default to skipping the reinstall:
	# no pointless re-download, and no non-atomic refresh of a live version on systems
	# without an atomic directory swap. We still re-link it (and switch the default),
	# so the prompt spells that out and points at --reinstall to force a fresh build.
	# --reinstall, and rolling nightly/pr builds (which refresh to the newest build
	# behind their label - the whole point of re-running them), take the full
	# download-verify-swap path below.
	if [ -d "$INSTALL_DIR/$_destname" ] && [ "$R_KIND" = release ] && [ "$REINSTALL" != 1 ]; then
		if [ "$_setdefault" = 1 ]; then
			_prompt="$R_LABEL is already installed; make it the default and refresh its symlinks in $SYMLINK_DIR? (pass --reinstall to re-download and replace the build)"
		else
			_prompt="$R_LABEL is already installed; refresh its symlinks in $SYMLINK_DIR? (pass --reinstall to re-download and replace the build)"
		fi
		if ! confirm "$_prompt"; then
			info "Aborted."; exit 0
		fi
	else
		_prompt="Install $R_LABEL into $INSTALL_DIR and link in $SYMLINK_DIR?"
		if [ -d "$INSTALL_DIR/$_destname" ]; then
			if [ "$R_KIND" = release ]; then
				_prompt="$R_LABEL is already installed; re-download and replace it?"
			else
				_prompt="Refresh $R_LABEL to the latest build in $INSTALL_DIR and re-link in $SYMLINK_DIR?"
			fi
		fi
		# Make the trust downgrade part of what the user consents to: PR builds
		# skip GPG verification (see verify_sig), not just a warning that scrolls by.
		[ "$R_KIND" = pr ] && _prompt="$_prompt (unsigned: PR builds have no GPG signature)"
		if ! confirm "$_prompt"; then
			info "Aborted."; exit 0
		fi

		install_resolved "$_destname"
	fi
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
	# Mop up this version's staging namespace the same way install reaps it: yank
	# .incoming.<destname> aside with one rename (so nothing is ever half-deleted
	# at an installable path), then sweep all inert .old.* garbage.
	_scratch=$(mktemp -d "$INSTALL_DIR/.old.XXXXXXXXXX") ||
		die "could not create scratch dir in $INSTALL_DIR"
	mv "$INSTALL_DIR/.incoming.$_destname" "$_scratch/" 2>/dev/null || :
	rm -rf "$INSTALL_DIR"/.old.* 2>/dev/null || :
	info "Removed $_destname"
}

cmd_remove() {
	_target=$1
	# Reject any path-shaped target outright (as resolve_spec does for installs):
	# match_installed resolves an exact id with a bare [ -d "$INSTALL_DIR/julia-$_q" ]
	# test, so a "../.." target would escape INSTALL_DIR and remove_one's rm -rf
	# would delete a tree outside it.
	case "$_target" in */*) die "bad version specifier: $_target" ;; esac
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
	# is safe; staying out of a subshell keeps `die` fatal to
	# the whole batch rather than just one iteration.
	for _destname in $_matches; do
		remove_one "$_destname"
	done
}

cmd_list() {
	if [ ! -d "$INSTALL_DIR" ]; then echo "No versions installed."; return 0; fi
	_default=""
	[ -L "$SYMLINK_DIR/julia" ] && _default=$(readlink "$SYMLINK_DIR/julia")
	ls "$INSTALL_DIR" 2>/dev/null | sed -n 's/^julia-//p' | sort -t. -k1,1n -k2,2n -k3,3n | while read -r _v; do
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
                                      (alias: rm)
  install-julia.sh list               list installed versions (alias: ls)
  install-julia.sh                    install the latest stable release

Options:
  -h, --help     show this help and exit
  -v, --version  show version and exit
  -y, --yes      do not prompt for confirmation
  --reinstall    if a stable version is already installed, re-download and replace it

Versions:
  1  1.12  1.12.6  1.13.0-rc1  pre  nightly  1.11-nightly  pr<num>
  (append ~x86_64, ~x86, or ~aarch64 to override the architecture)
  (switch resolves a numeric prefix to the greatest installed stable
  patch; prereleases, nightlies, and ~arch builds need their exact id)

See README.md for full documentation.
EOF
}

main() {
	# Walk every argument once: flags set their globals wherever they appear, and
	# the first two non-flags land in _cmd and _arg.
	_cmd=""
	_arg=""
	while [ $# -gt 0 ]; do
		case "$1" in
			-h | --help)    usage; exit 0 ;;
			-v | --version) printf 'install-julia.sh %s\n' "$SELF_VERSION"; exit 0 ;;
			-y | --yes)     NO_CONFIRM=1 ;;
			--reinstall)    REINSTALL=1 ;;
			-*)             die "unknown option: $1 (try --help)" ;;
			*)
				if   [ -z "$_cmd" ]; then _cmd=$1
				elif [ -z "$_arg" ]; then _arg=$1
				else die "unexpected extra argument: $1"
				fi ;;
		esac
		shift
	done

	# Check every hard dependency up front, before any command runs, so a missing
	# tool surfaces immediately instead of partway through an operation. gpgv/base64
	# are needed only when signature verification is on (the default).
	need curl
	need tar
	need mktemp
	need readlink
	[ "$NO_VERIFY" = 1 ] || { need gpgv; need base64; }

	case "$_cmd" in
		add)
			[ -n "$_arg" ] || die "usage: install-julia.sh add <version>"
			cmd_install "$_arg" 0 ;;
		switch)
			[ -n "$_arg" ] || die "usage: install-julia.sh switch <version|path>"
			cmd_switch "$_arg" ;;
		remove | rm)
			[ -n "$_arg" ] || die "usage: install-julia.sh remove <version>"
			cmd_remove "$_arg" ;;
		list | ls)
			cmd_list ;;
		"")
			cmd_install "" 1 ;;             # default: latest stable, set default
		*)
			cmd_install "$_cmd" 1 ;;        # install-julia.sh <version>
	esac
}

main "$@"
