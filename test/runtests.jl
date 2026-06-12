using Test
using Expect: ExpectProc, expect!
using Downloads: download
using ChunkCodecLibZlib: GzipEncodeOptions, encode
import Tar
import JSON

const script = joinpath(dirname(@__DIR__), "src", "install-julia.sh")
const workingdir = mktempdir()
const installdir = joinpath(workingdir, "packages/julias")
const symlinkdir = joinpath(workingdir, ".local/bin")
# Need to set this here instead of when running to work around Expect.jl bug/limitation
ENV["INSTALL_JULIA_INSTALL_DIR"] = installdir
ENV["INSTALL_JULIA_SYMLINK_DIR"] = symlinkdir

# We need a signed julia release for testing
const mirror = joinpath(@__DIR__, "mirror")
if !isdir(mirror)
    mkdir(mirror)
    try
        local tarballname = "bin/linux/x64/1.0/julia-1.0.0-linux-x86_64.tar.gz"
        mkpath(dirname(joinpath(mirror, tarballname)))
        download(
            "https://julialang-s3.julialang.org/$(tarballname)",
            joinpath(mirror, tarballname)
        )
        download(
            "https://julialang-s3.julialang.org/$(tarballname).asc",
            joinpath(mirror, tarballname*".asc")
        )
        write(joinpath(mirror, "bin/versions.json"), read(joinpath(@__DIR__, "test-version.json")))
    catch
        rm(mirror; recursive=true, force=true)
        rethrow()
    end
end

function cleanup()
    rm(installdir, force=true, recursive=true)
    rm(symlinkdir, force=true, recursive=true)
end

# A fabricated julia tarball: the right layout (julia-<version>/bin/julia,
# executable) but a shell stub as the binary. Unsigned, so installing one
# requires INSTALL_JULIA_NO_VERIFY=1.
function fake_tarball(version)
    src = mktempdir()
    bin = joinpath(src, "julia-$version/bin")
    mkpath(bin)
    write(joinpath(bin, "julia"), "#!/bin/sh\necho fake julia $version\n")
    chmod(joinpath(bin, "julia"), 0o755)
    encode(GzipEncodeOptions(), read(Tar.create(src)))
end

# A mirror serving fake tarballs for the given versions, with a versions.json
# manifest shaped like the real one listing exactly them. `arch` is the
# (stable bucket dir, filename arch) pair, e.g. ("x64", "x86_64"), ("x86", "i686").
function fake_mirror(versions...; arch=("x64", "x86_64"))
    bucket, filearch = arch
    mr = joinpath(mktempdir(), "mirror")
    manifest = Dict()
    for v in versions
        minor = join(split(v, '.')[1:2], '.')
        name = "bin/linux/$bucket/$minor/julia-$v-linux-$filearch.tar.gz"
        path = joinpath(mr, name)
        mkpath(dirname(path))
        write(path, fake_tarball(v))
        manifest[v] = Dict(
            "files" => [Dict(
                "url" => "https://julialang-s3.julialang.org/$name",
                "version" => v, "os" => "linux", "arch" => filearch,
                "kind" => "archive", "extension" => "tar.gz",
            )],
            "stable" => !occursin('-', v),
        )
    end
    mkpath(joinpath(mr, "bin"))
    write(joinpath(mr, "bin/versions.json"), JSON.json(manifest))
    mr
end

function run_script(args::String...; env=(), dir=pwd())
    _env = copy(ENV)
    for (k, v) in env
        _env[k] = v
    end
    out, err = IOBuffer(), IOBuffer()
    cmd = pipeline(ignorestatus(setenv(Cmd([script, args...]), _env; dir)), stdout=out, stderr=err)
    p = run(cmd)
    (; code=p.exitcode, out=String(take!(out)), err=String(take!(err)))
end
function run_script_y(args::String...; kwargs...)
    run_script("-y", args...; kwargs...)
end

# Resolve `pre` (latest, prereleases included) against a synthetic versions.json
# listing exactly `versions`, and return the version it picked - i.e. the
# maximum under the script's SemVer comparator, via the real resolution path.
function resolve_max(versions...)
    cleanup()
    mr = fake_mirror(versions...)
    r = run_script_y("add", "pre"; env=("INSTALL_JULIA_STABLE_URL" => "file://$mr",
                                        "INSTALL_JULIA_NO_VERIFY" => "1"))
    @test r.code == 0
    m = match(r"Resolved 'pre' -> (\S+) \(release\)", r.err)
    m === nothing && error("no Resolved line in:\n$(r.err)")
    String(m.captures[1])
end


@testset "shellcheck" begin
    @test success(run(`shellcheck $(script) --severity=warning`))
end
@testset "version" begin
    r = run_script("--version")
    @test r.code == 0
    @test startswith(r.out, "install-julia.sh ")

    r = run_script("-v")
    @test r.code == 0
    @test startswith(r.out, "install-julia.sh ")

    r = run_script("--versio")
    @test r.code == 1
    @test r.err == "error: unknown option: --versio (try --help)\n"
end
@testset "help" begin
    r = run_script("--help")
    @test r.code == 0
    @test startswith(r.out, "Usage: install-julia.sh [options] [command] [version]")

    r = run_script("-h")
    @test r.code == 0
    @test startswith(r.out, "Usage: install-julia.sh [options] [command] [version]")

    r = run_script("--hel")
    @test r.code == 1
    @test r.err == "error: unknown option: --hel (try --help)\n"
end
@testset "spec validation" begin
    # a path-shaped spec must die in resolve_spec, before any network access or
    # any directory is created (case globs match '/', so without the guard
    # "1.2.3/../evil" parses as a release version and escapes INSTALL_DIR)
    cleanup()
    for spec in ("1.2.3/../../evil", "/evil", "1.11/x-nightly")
        r = run_script_y(spec)
        @test r.code == 1
        @test r.err == "error: bad version specifier: $spec\n"
    end

    # the catch-all arm: not a version, not a known keyword
    r = run_script_y("foo")
    @test r.code == 1
    @test r.err == "error: unrecognized version specifier: foo\n"
    @test !isdir(installdir)   # died before mkdir -p INSTALL_DIR

    # `remove` must reject a path-shaped target too: match_installed resolves an
    # exact id with [ -d "$INSTALL_DIR/julia-$q" ], so without this guard
    # "nightly/../../evil" would escape INSTALL_DIR and rm -rf a tree outside
    # it. The guard fires before match_installed, so remove_one is never reached.
    for spec in ("nightly/../../evil", "../../evil", "1.0/../evil")
        r = run_script_y("remove", spec)
        @test r.code == 1
        @test r.err == "error: bad version specifier: $spec\n"
    end

    # a slashless ".." can't traverse: with no '/', "$INSTALL_DIR/julia-.." is a
    # single component literally named "julia-..", not a parent reference, so
    # match_installed simply finds nothing rather than escaping the tree
    for spec in ("..", ".", "...")
        r = run_script_y("remove", spec)
        @test r.code == 1
        @test r.err == "error: no installed version matching '$spec'\n"
    end
end
@testset "usage errors" begin
    # commands that need an argument die with a usage line when it's missing
    for (cmd, usage) in (
        ("add", "add <version>"),
        ("switch", "switch <version|path>"),
        ("remove", "remove <version>"),
    )
        r = run_script_y(cmd)
        @test r.code == 1
        @test r.err == "error: usage: install-julia.sh $usage\n"
    end

    # and a third non-flag argument is rejected outright
    r = run_script_y("remove", "1.0", "extra")
    @test r.code == 1
    @test r.err == "error: unexpected extra argument: extra\n"
end
@testset "command aliases" begin
    cleanup()
    mkpath(joinpath(installdir, "julia-1.0.0/bin"))
    r = run_script("ls")
    @test r.code == 0
    @test r.out == "   1.0.0\n"
    r = run_script_y("rm", "1.0.0")
    @test r.code == 0
    @test occursin("Removed julia-1.0.0", r.err)
    @test isempty(readdir(installdir))

    # list over an empty-but-existing INSTALL_DIR prints nothing, same as a
    # missing one (remove leaves INSTALL_DIR behind, so this is the post-rm state)
    @test isdir(installdir)
    r = run_script("list")
    @test r.code == 0
    @test r.out == ""

    # uninstall is NOT a command; like any unknown word it parses as a version spec
    r = run_script_y("uninstall")
    @test r.code == 1
    @test r.err == "error: unrecognized version specifier: uninstall\n"
end
@testset "confirm prompt" begin
    # confirm() reads the answer from /dev/tty, so it needs a controlling
    # terminal. ExpectProc runs the script on a fresh pty, and `setsid --ctty`
    # makes that pty the controlling terminal (otherwise /dev/tty would be the
    # test runner's terminal - or nothing - and never the Expect pty).
    fakejulia = joinpath(ENV["INSTALL_JULIA_INSTALL_DIR"], "julia-1.10.0")
    cmd = `setsid -w -c $script remove 1.10.0`

    # answering "n" aborts and leaves the version in place
    mkpath(joinpath(fakejulia, "bin"))
    proc = ExpectProc(cmd, 30)
    @test occursin("Remove $fakejulia", expect!(proc, "[y/N] "))
    println(proc, "n")
    expect!(proc, "Aborted.")
    @test success(proc)
    @test isdir(fakejulia)

    # answering "y" removes it
    proc = ExpectProc(cmd, 30)
    expect!(proc, "[y/N] ")
    println(proc, "y")
    expect!(proc, "Removed julia-1.10.0")
    @test success(proc)
    @test !isdir(fakejulia)

    # `setsid` without --ctty leaves the script with no controlling terminal,
    # so confirm() cannot ask: it must decline, point at -y, and abort
    mkpath(joinpath(fakejulia, "bin"))
    out, err = IOBuffer(), IOBuffer()
    p = run(pipeline(ignorestatus(`setsid -w $script remove 1.10.0`), stdout=out, stderr=err))
    notty_err = String(take!(err))
    @test p.exitcode == 1
    @test occursin("no terminal available to confirm; exiting (pass -y to proceed non-interactively)", notty_err)
    @test isdir(fakejulia)

    # -y / --yes skip the prompt entirely, so removal proceeds with no terminal
    for flag in ("-y", "--yes")
        mkpath(joinpath(fakejulia, "bin"))
        out, err = IOBuffer(), IOBuffer()
        p = run(pipeline(ignorestatus(`setsid -w $script $flag remove 1.10.0`), stdout=out, stderr=err))
        yes_err = String(take!(err))
        @test p.exitcode == 0
        @test !occursin("[y/N]", yes_err)
        @test occursin("Removed julia-1.10.0", yes_err)
        @test !isdir(fakejulia)
    end
end
@testset "install prompt" begin
    cleanup()
    mr = fake_mirror("1.0.0")
    # ExpectProc offers no per-process env (see the ENV comment at the top),
    # so point the script at the fake mirror via the test process's own
    # environment for the duration of this testset
    withenv("INSTALL_JULIA_STABLE_URL" => "file://$mr",
            "INSTALL_JULIA_NO_VERIFY" => "1") do
        # answering "n" to a fresh install aborts before anything is downloaded
        cmd = `setsid -w -c $script add 1.0.0`
        proc = ExpectProc(cmd, 30)
        @test occursin("Install 1.0.0 into", expect!(proc, "[y/N] "))
        println(proc, "n")
        expect!(proc, "Aborted.")
        @test success(proc)
        @test !isdir(joinpath(installdir, "julia-1.0.0"))

        # answering "y" installs
        proc = ExpectProc(cmd, 30)
        expect!(proc, "[y/N] ")
        println(proc, "y")
        expect!(proc, "Installed 1.0.0")
        @test success(proc)
        @test isfile(joinpath(installdir, "julia-1.0.0/bin/julia"))

        # already installed, no --reinstall: the prompt offers a symlink
        # refresh + default switch, and "y" must not re-download
        proc = ExpectProc(`setsid -w -c $script 1.0.0`, 30)
        pre = expect!(proc, "[y/N] ")
        @test occursin("1.0.0 is already installed; make it the default and refresh its symlinks", pre)
        println(proc, "y")
        tail = expect!(proc, "Default 'julia' now points to 1.0.0")
        @test !occursin("Downloading", tail)
        @test success(proc)
        @test readlink(joinpath(symlinkdir, "julia")) ==
            joinpath(installdir, "julia-1.0.0/bin/julia")
    end
end
@testset "dependency checks" begin
    cleanup()
    # every hard dependency is checked up front, before any command runs; an
    # empty PATH loses curl first
    r = run_script("list"; env=("PATH" => "",))
    @test r.code == 1
    @test r.err == "error: required command not found: curl\n"

    # a PATH with the always-on tools but no gpgv: verification needs gpgv...
    farm = mktempdir()
    for tool in ("curl", "tar", "mktemp", "readlink")
        symlink(Sys.which(tool), joinpath(farm, tool))
    end
    r = run_script("list"; env=("PATH" => farm,))
    @test r.code == 1
    @test r.err == "error: required command not found: gpgv\n"

    # ...but NO_VERIFY=1 drops that requirement, and `list` with nothing
    # installed needs no external tools at all (and prints nothing)
    r = run_script("list"; env=("PATH" => farm, "INSTALL_JULIA_NO_VERIFY" => "1"))
    @test r.code == 0
    @test r.out == ""
end
@testset "staging reap" begin
    # remove reaps the staging namespace for exactly its version - an exact
    # directory name, so the namespace of a different version that shares the
    # prefix (here a prerelease) must survive.
    mkpath(joinpath(installdir, "julia-1.10.0/bin"))
    stale = joinpath(installdir, ".incoming.julia-1.10.0/424242")
    decoy = joinpath(installdir, ".incoming.julia-1.10.0-rc9/424242")
    inert = joinpath(installdir, ".old.424242julia14")
    for d in (stale, decoy, inert)
        mkpath(d)
        write(joinpath(d, "f"), "x")
    end
    r = run_script_y("remove", "1.10.0")
    @test r.code == 0
    @test !isdir(joinpath(installdir, "julia-1.10.0"))
    @test !isdir(stale)   # this version's leftover staging: yanked and deleted
    @test !isdir(inert)   # inert .old.* garbage: swept
    @test isdir(decoy)    # other version's staging: untouched
    rm(decoy, recursive=true)
end
@testset "symlink replacement" begin
    # a default link pointing at a DIRECTORY must be replaced, not
    # dereferenced (a naive mv onto it would land the new link inside the
    # directory), and link()'s rename swap must leave no scratch litter
    cleanup()
    dir = mktempdir()
    fake = joinpath(dir, "fake-julia")
    write(fake, "#!/bin/sh\nexit 0\n")
    chmod(fake, 0o755)
    trapdir = joinpath(dir, "trapdir")
    mkpath(trapdir)
    mkpath(symlinkdir)
    symlink(trapdir, joinpath(symlinkdir, "julia"))
    r = run_script_y("switch", fake)
    @test r.code == 0
    @test readlink(joinpath(symlinkdir, "julia")) == fake
    @test isempty(readdir(trapdir))   # nothing was created inside the directory
    @test isempty(filter(startswith("."), readdir(symlinkdir)))   # no .link.* scratch left
end
@testset "switch path handling" begin
    cleanup()
    # spaces in the binary path must survive the link plumbing unsplit
    dir = mktempdir()
    spacey = joinpath(dir, "fake julia dir")
    mkpath(spacey)
    bin = joinpath(spacey, "my julia")
    write(bin, "#!/bin/sh\n")
    chmod(bin, 0o755)
    r = run_script_y("switch", bin)
    @test r.code == 0
    @test readlink(joinpath(symlinkdir, "julia")) == bin

    # a relative path (./name, the documented cwd form) resolves against the
    # script's $PWD - spaces and all - not the test runner's
    rm(joinpath(symlinkdir, "julia"))
    r = run_script_y("switch", "./my julia"; dir=spacey)
    @test r.code == 0
    @test readlink(joinpath(symlinkdir, "julia")) == joinpath(spacey, "./my julia")

    # missing and non-executable targets die without touching the default
    r = run_script_y("switch", joinpath(spacey, "no such julia"))
    @test r.code == 1
    @test r.err == "error: $(joinpath(spacey, "no such julia")): no such file\n"

    notexec = joinpath(spacey, "not exec")
    write(notexec, "#!/bin/sh\n")
    r = run_script_y("switch", notexec)
    @test r.code == 1
    @test r.err == "error: $notexec is not executable\n"
    @test readlink(joinpath(symlinkdir, "julia")) == joinpath(spacey, "./my julia")

    # a slashless target is always an installed-version id, never a path: an
    # executable file named 1.0.0 sitting in the cwd must not be linked
    verfile = joinpath(spacey, "1.0.0")
    write(verfile, "#!/bin/sh\n")
    chmod(verfile, 0o755)
    r = run_script_y("switch", "1.0.0"; dir=spacey)
    @test r.code == 1
    @test r.err == "error: no installed version matching '1.0.0' (switch never installs; try: install-julia.sh add 1.0.0)\n"
    @test readlink(joinpath(symlinkdir, "julia")) == joinpath(spacey, "./my julia")
end
@testset "offline mirror install" begin
    # A file:// mirror built from a local fixture exercises the full install path
    # offline: manifest resolution, download, GPG verification, staging, the
    # atomic claim, symlinks, and that a successful install leaves no litter.
    cleanup()
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mirror",)

    # default should install 1.0.0
    r = run_script_y(; env)
    @test r.code == 0
    @test occursin("Resolved '' -> 1.0.0 (release)", r.err)
    binfile = joinpath(installdir, "julia-1.0.0/bin/julia")
    @test isfile(binfile)
    @test readdir(symlinkdir) == ["julia", "julia-1", "julia-1.0", "julia-1.0.0"]
    @test readdir(installdir) == ["julia-1.0.0"]
    @test readlink(joinpath(symlinkdir, "julia-1.0.0")) == binfile
    @test readlink(joinpath(symlinkdir, "julia-1.0"))   == binfile
    @test readlink(joinpath(symlinkdir, "julia-1"))     == binfile
    @test readlink(joinpath(symlinkdir, "julia"))       == binfile
    @test isempty(filter(startswith("."), readdir(installdir)))
    @test isempty(filter(startswith("."), readdir(symlinkdir)))
    cleanup()

    # fresh install: resolves 1.0 -> 1.0.0 from the manifest, reaps this
    # version's stale staging namespace, installs, links direct + rollup but
    # no default
    stale = joinpath(installdir, ".incoming.julia-1.0.0/424242")
    mkpath(joinpath(stale, "julia-1.0.0"))
    r = run_script_y("add", "1.0"; env)
    @test r.code == 0
    @test occursin("Resolved '1.0' -> 1.0.0 (release)", r.err)
    @test isfile(joinpath(installdir, "julia-1.0.0/bin/julia"))
    @test islink(joinpath(symlinkdir, "julia-1.0.0"))
    @test islink(joinpath(symlinkdir, "julia-1.0"))
    @test !islink(joinpath(symlinkdir, "julia"))   # add keeps the default alone
    @test !isdir(stale)
    @test isempty(filter(startswith("."), readdir(installdir)))
    @test isempty(filter(startswith("."), readdir(symlinkdir)))

    # --reinstall takes the park-and-swap path and is just as clean
    r = run_script_y("--reinstall", "add", "1.0.0"; env)
    @test r.code == 0
    @test occursin("already installed; refreshing", r.err)
    @test isfile(joinpath(installdir, "julia-1.0.0/bin/julia"))
    @test isempty(filter(startswith("."), readdir(installdir)))
    @test isempty(filter(startswith("."), readdir(symlinkdir)))

    # manually specify the arch
    r = run_script_y("1.0.0~x64"; env)
    @test r.code == 0
    @test occursin("Default 'julia' now points to 1.0.0~x64", r.err)
    @test isfile(joinpath(installdir, "julia-1.0.0~x64/bin/julia"))
    @test readlink(symlinkdir*"/julia") == joinpath(installdir, "julia-1.0.0~x64/bin/julia")
    @test isempty(filter(startswith("."), readdir(installdir)))
    @test isempty(filter(startswith("."), readdir(symlinkdir)))
end
@testset "verification failure" begin
    # the security-critical failure paths, each against its own hostile copy of
    # the mirror fixture: verification must fail closed, before anything is
    # installed or linked
    cleanup()
    tarballname = "bin/linux/x64/1.0/julia-1.0.0-linux-x86_64.tar.gz"

    # tampered tarball: a flipped byte must fail the GPG check (which runs
    # before unpacking), install nothing, and link nothing
    evil = joinpath(mktempdir(), "mirror")
    cp(mirror, evil)
    tarball = joinpath(evil, tarballname)
    data = read(tarball)
    data[end÷2] ⊻= 0xff
    write(tarball, data)
    r = run_script_y("add", "1.0.0"; env=("INSTALL_JULIA_STABLE_URL" => "file://$evil",))
    @test r.code == 1
    @test occursin("signature verification FAILED", r.err)
    @test !isdir(joinpath(installdir, "julia-1.0.0"))
    @test !isdir(symlinkdir)

    # missing signature: refuse to install rather than fall back to unverified
    nosig = joinpath(mktempdir(), "mirror")
    cp(mirror, nosig)
    rm(joinpath(nosig, tarballname * ".asc"))
    r = run_script_y("add", "1.0.0"; env=("INSTALL_JULIA_STABLE_URL" => "file://$nosig",))
    @test r.code == 1
    @test occursin("refusing to install unverified", r.err)
    @test !isdir(joinpath(installdir, "julia-1.0.0"))

    # version substitution: a genuine, validly-signed 1.0.0 tarball served under
    # a 1.0.1 URL passes GPG but must die on the version-binding check
    subst = joinpath(mktempdir(), "mirror")
    substname = "bin/linux/x64/1.0/julia-1.0.1-linux-x86_64.tar.gz"
    mkpath(dirname(joinpath(subst, substname)))
    for ext in ("", ".asc")
        cp(joinpath(mirror, tarballname * ext), joinpath(subst, substname * ext))
    end
    r = run_script_y("add", "1.0.1"; env=("INSTALL_JULIA_STABLE_URL" => "file://$subst",))
    @test r.code == 1
    @test occursin("Good signature from", r.err)   # the attack defeats GPG...
    @test occursin("version mismatch: requested 1.0.1 but tarball reports '1.0.0'", r.err)
    @test !isdir(joinpath(installdir, "julia-1.0.1"))

    # INSTALL_JULIA_NO_VERIFY=1 skips verification but must say so loudly
    cleanup()
    r = run_script_y("add", "1.0.0"; env=(
        "INSTALL_JULIA_STABLE_URL" => "file://$mirror",
        "INSTALL_JULIA_NO_VERIFY" => "1",
    ))
    @test r.code == 0
    @test occursin("signature verification disabled", r.err)
    @test isfile(joinpath(installdir, "julia-1.0.0/bin/julia"))
end
@testset "list and switch" begin
    cleanup()
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mirror",)
    r = run_script_y("add", "1.0.0"; env)
    @test r.code == 0
    binfile = joinpath(installdir, "julia-1.0.0/bin/julia")

    # `add` set no default, so list shows the version unmarked
    r = run_script("list")
    @test r.code == 0
    @test r.out == "   1.0.0\n"

    # switch resolves a numeric prefix to the greatest installed patch
    r = run_script_y("switch", "1.0")
    @test r.code == 0
    @test occursin("Default 'julia' now points to 1.0.0", r.err)
    @test readlink(joinpath(symlinkdir, "julia")) == binfile

    # and the default is now starred
    r = run_script("list")
    @test r.code == 0
    @test r.out == " * 1.0.0\n"

    # switch never installs
    r = run_script_y("switch", "9.9")
    @test r.code == 1
    @test occursin("no installed version matching '9.9'", r.err)
    @test readlink(joinpath(symlinkdir, "julia")) == binfile   # default untouched

    # list orders by version, not lexically: the POSIX numeric field sort that
    # replaced sort -V must rank 1.2.0 < 1.9.9 < 1.10.0 (lexically 1.10.0 would
    # sort before 1.9.9), with the prerelease of 1.10.1 after the 1.10.0 release
    cleanup()
    for v in ("1.10.0", "1.9.9", "1.2.0", "1.10.1-rc1")
        mkpath(joinpath(installdir, "julia-$v/bin"))
    end
    r = run_script("list")
    @test r.code == 0
    @test r.out == "   1.2.0\n   1.9.9\n   1.10.0\n   1.10.1-rc1\n"
end
@testset "switch prefix resolution" begin
    cleanup()
    for v in ("1.9.9", "1.10.0", "1.10.1-rc1", "1.10.2~x86", "1.2-nightly", "nightly", "2.0.0")
        mkpath(joinpath(installdir, "julia-$v/bin"))
    end
    target(v) = joinpath(installdir, "julia-$v/bin/julia")
    julialink() = readlink(joinpath(symlinkdir, "julia"))

    # a prefix resolves to the greatest installed plain stable patch under it:
    # prereleases, ~arch copies, and nightlies never match a prefix, and
    # version_gt ranks 1.10.0 over 1.9.9 (lexically it wouldn't be)
    r = run_script_y("switch", "1")
    @test r.code == 0
    @test occursin("Default 'julia' now points to 1.10.0", r.err)
    @test julialink() == target("1.10.0")

    r = run_script_y("switch", "1.9")
    @test r.code == 0
    @test julialink() == target("1.9.9")

    r = run_script_y("switch", "1.10")
    @test r.code == 0
    @test julialink() == target("1.10.0")

    # exact ids reach the builds prefixes can't
    for v in ("1.10.1-rc1", "1.10.2~x86", "1.2-nightly", "nightly")
        r = run_script_y("switch", v)
        @test r.code == 0
        @test julialink() == target(v)
    end

    # no plain stable build under the prefix -> error, even when a prerelease
    # (1.10.1-rc1), a nightly (1.2-nightly), or an arch copy (1.10.2~x86)
    # lives in that line; 1.1 must not match 1.10.0 across the component
    # boundary; and ~arch builds are exact-id-only, so a prefix~arch query
    # never resolves to one
    for q in ("1.10.1", "1.10.2", "1.2", "1.1", "3", "1.1~x86", "1.10~x86")
        r = run_script_y("switch", q)
        @test r.code == 1
        @test occursin("no installed version matching '$q'", r.err)
    end
    @test julialink() == target("nightly")   # the failures left the default alone
end
@testset "remove sweep" begin
    # a numeric prefix sweeps its whole line - releases, prereleases, the branch
    # nightly - on component boundaries (1.0 must not catch 1.10.0), dropping
    # symlinks that point into removed builds and only those
    cleanup()
    for v in ("1.0.0", "1.0.1", "1.0.0-rc1", "1.0-nightly", "1.10.0", "pr123")
        mkpath(joinpath(installdir, "julia-$v/bin"))
    end
    mkpath(symlinkdir)
    symlink(joinpath(installdir, "julia-1.0.1/bin/julia"), joinpath(symlinkdir, "julia-1.0"))
    symlink(joinpath(installdir, "julia-1.0.1/bin/julia"), joinpath(symlinkdir, "julia"))
    symlink(joinpath(installdir, "julia-1.10.0/bin/julia"), joinpath(symlinkdir, "julia-1.10"))

    r = run_script_y("remove", "1.0")
    @test r.code == 0
    @test occursin("4 installed versions match '1.0'", r.err)
    @test sort(readdir(installdir)) == ["julia-1.10.0", "julia-pr123"]
    @test !islink(joinpath(symlinkdir, "julia-1.0"))   # pointed into a removed build
    @test !islink(joinpath(symlinkdir, "julia"))       # default did too
    @test islink(joinpath(symlinkdir, "julia-1.10"))   # survivor's link untouched

    # rolling builds carry no numeric prefix: exact name only
    r = run_script_y("remove", "pr123")
    @test r.code == 0
    @test sort(readdir(installdir)) == ["julia-1.10.0"]

    # an exact branch-nightly id removes just the nightly, not its releases...
    for v in ("1.2.0", "1.2-nightly")
        mkpath(joinpath(installdir, "julia-$v/bin"))
    end
    r = run_script_y("remove", "1.2-nightly")
    @test r.code == 0
    @test sort(readdir(installdir)) == ["julia-1.10.0", "julia-1.2.0"]

    # ...while a major-prefix sweep catches releases and branch nightlies alike
    mkpath(joinpath(installdir, "julia-1.2-nightly/bin"))
    r = run_script_y("remove", "1")
    @test r.code == 0
    @test occursin("3 installed versions match '1'", r.err)
    @test isempty(readdir(installdir))

    # a full-version prefix sweeps that version's per-arch copies too (the ~arch
    # tag is stripped before the boundary match), alongside its prereleases - so
    # `remove 1.3.0` clears 1.3.0, 1.3.0-rc1, and 1.3.0~x86 together, while a
    # different patch in the same minor (1.3.1) is left alone
    cleanup()
    for v in ("1.3.0", "1.3.0-rc1", "1.3.0~x86", "1.3.0~aarch64", "1.3.1")
        mkpath(joinpath(installdir, "julia-$v/bin"))
    end
    r = run_script_y("remove", "1.3.0")
    @test r.code == 0
    @test occursin("4 installed versions match '1.3.0'", r.err)
    @test readdir(installdir) == ["julia-1.3.1"]
end
@testset "version comparison" begin
    # The SemVer comparator that replaced sort -V is exercised through real
    # resolution: `pre` picks the greatest version in a synthetic versions.json,
    # so resolve_max(set) is the maximum under the script's ordering. Each set
    # below isolates one precedence rule.

    # core numeric, two-digit boundary (lexically 1.10.0 would sort below 1.9.9)
    @test resolve_max("1.9.9", "1.10.0") == "1.10.0"
    @test resolve_max("1.99.99", "2.0.0") == "2.0.0"

    # a final release outranks its prerelease
    @test resolve_max("1.0.0-rc1", "1.0.0") == "1.0.0"

    # prerelease tags by ASCII order; rc10 < rc2 because these are alphanumeric
    # identifiers compared lexically, NOT numerically (matches Julia's v"...")
    @test resolve_max("1.0.0-alpha", "1.0.0-beta", "1.0.0-rc") == "1.0.0-rc"
    @test resolve_max("1.1.1-rc10", "1.1.1-rc2") == "1.1.1-rc2"

    # a numeric identifier is always below a non-numeric one
    @test resolve_max("1.0.0-1", "1.0.0-alpha") == "1.0.0-alpha"

    # all-digit identifiers compared numerically (so .11 > .2, not lexically)
    @test resolve_max("1.0.0-beta.2", "1.0.0-beta.11") == "1.0.0-beta.11"

    # a larger set of fields outranks a shorter prefix of it
    @test resolve_max("1.0.0-alpha", "1.0.0-alpha.1") == "1.0.0-alpha.1"

    @test resolve_max("1.0.0--", "1.0.0-a") == "1.0.0-a"
    @test resolve_max("1.0.0-a", "1.0.0--") == "1.0.0-a"
    @test resolve_max("1.0.0-0.0", "1.0.0-0") == "1.0.0-0.0"
    @test resolve_max("1.0.0-0", "1.0.0-0.0") == "1.0.0-0.0"

    # non versions and versions with build metadata in the manifest get ignored
    @test resolve_max("1.0.0", "2.0.00") == "1.0.0"
    @test resolve_max("2.0.00", "1.0.0") == "1.0.0"
    @test resolve_max("1.0.0", "2.0.0+build") == "1.0.0"
    @test resolve_max("2.0.0+build", "1.0.0") == "1.0.0"

    # a hyphen is a legal identifier character, not a separator: x-y-z is one
    # identifier, and the spec's "--" is a field of its own
    @test resolve_max("1.0.0-x-y-w", "1.0.0-x-y-z") == "1.0.0-x-y-z"
    @test resolve_max("1.0.0-x-y-z", "1.0.0-x-y-z.--") == "1.0.0-x-y-z.--"

    # the full SemVer precedence example, link by link (each pair's max is the
    # higher one), and the maximum of the whole set is the top of the chain
    chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
             "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
    for i in 1:length(chain)-1
        @test resolve_max(chain[i], chain[i+1]) == chain[i+1]
    end
    @test resolve_max(chain...) == "1.0.0"
end
@testset "prerelease resolution" begin
    # Fabricated unsigned versions (NO_VERIFY=1) make the whole resolution
    # matrix testable: which build each spec picks out of a manifest that mixes
    # releases and prereleases.
    cleanup()
    mr = fake_mirror("1.1.0", "1.1.1", "1.1.2-rc1", "1.2.0-rc1")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")

    # bare install: latest stable, never a prerelease (1.2.0-rc1 is newer)
    r = run_script_y(; env)
    @test r.code == 0
    @test occursin("Resolved '' -> 1.1.1 (release)", r.err)
    # the installed stub actually runs through the default symlink
    @test read(`$(joinpath(symlinkdir, "julia"))`, String) == "fake julia 1.1.1\n"

    # a numeric prefix is also stable-only: 1.1 picks 1.1.1, not 1.1.2-rc1
    r = run_script_y("add", "1.1"; env)
    @test occursin("Resolved '1.1' -> 1.1.1 (release)", r.err)

    # pre: greatest version overall, prereleases included
    r = run_script_y("add", "pre"; env)
    @test r.code == 0
    @test occursin("Resolved 'pre' -> 1.2.0-rc1 (release)", r.err)
    @test isfile(joinpath(installdir, "julia-1.2.0-rc1/bin/julia"))
    # prereleases never take the X.Y / X rollups: julia-1 still points at the
    # stable install above, and no julia-1.2 was created at all
    @test readlink(joinpath(symlinkdir, "julia-1")) ==
        joinpath(installdir, "julia-1.1.1/bin/julia")
    @test !ispath(joinpath(symlinkdir, "julia-1.2"))
    @test islink(joinpath(symlinkdir, "julia-1.2.0-rc1"))

    # a fully-qualified prerelease installs directly, also without rollups
    r = run_script_y("add", "1.1.2-rc1"; env)
    @test r.code == 0
    @test occursin("Resolved '1.1.2-rc1' -> 1.1.2-rc1 (release)", r.err)
    @test readlink(joinpath(symlinkdir, "julia-1.1")) ==
        joinpath(installdir, "julia-1.1.1/bin/julia")

    # prereleases sort BELOW their final release (the sort -V '~' mapping):
    # once 1.3.0 is out, pre must prefer it over 1.3.0-rc1 and 1.3.0-beta2
    cleanup()
    mr = fake_mirror("1.3.0-beta2", "1.3.0-rc1", "1.3.0")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")
    r = run_script_y("add", "pre"; env)
    @test r.code == 0
    @test occursin("Resolved 'pre' -> 1.3.0 (release)", r.err)

    # version binding still holds for fake builds: the relaxed sed reads the
    # no-trailing-slash dir entry that Tar.jl writes, so a Tar.jl tarball
    # served under the wrong version name is caught, not reported as 'unknown'
    wrongname = "bin/linux/x64/1.3/julia-1.3.1-linux-x86_64.tar.gz"
    mkpath(dirname(joinpath(mr, wrongname)))
    cp(joinpath(mr, "bin/linux/x64/1.3/julia-1.3.0-linux-x86_64.tar.gz"),
       joinpath(mr, wrongname))
    r = run_script_y("add", "1.3.1"; env)
    @test r.code == 1
    @test occursin("version mismatch: requested 1.3.1 but tarball reports '1.3.0'", r.err)

    # prerelease-vs-prerelease ordering (no final release in the line): `pre`
    # must pick the greatest tag per semver. alpha < beta < rc by ASCII order,
    # and crucially rc10 < rc2: these are alphanumeric identifiers compared
    # lexically (not numerically), so '1' < '2' at the third char makes rc2 the
    # winner - exactly as Julia's v"1.5.0-rc10" < v"1.5.0-rc2".
    cleanup()
    mr = fake_mirror("1.5.0-alpha", "1.5.0-beta1", "1.5.0-rc2", "1.5.0-rc10")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")
    r = run_script_y("add", "pre"; env)
    @test r.code == 0
    @test occursin("Resolved 'pre' -> 1.5.0-rc2 (release)", r.err)
    @test isfile(joinpath(installdir, "julia-1.5.0-rc2/bin/julia"))
end
@testset "resolution errors" begin
    cleanup()
    # a manifest fetch failure must die loudly, not masquerade as "no such
    # version" (the set -e subtlety pick_latest's comment describes)
    # (curl -S prints its own diagnostic line first, then the script dies)
    r = run_script_y("add", "1"; env=("INSTALL_JULIA_STABLE_URL" => "file:///nonexistent",))
    @test r.code == 1
    @test endswith(r.err, "error: could not fetch file:///nonexistent/bin/versions.json (network/HTTP error)\n")

    # a healthy manifest without the requested version: a prefix and a bare
    # spec die on their own distinct paths
    mr = fake_mirror("1.9.9", "1.10.0")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")
    r = run_script_y("add", "9"; env)
    @test r.code == 1
    @test r.err == "error: no stable release matching '9' for x86_64\n"

    empty = fake_mirror()
    r = run_script_y(; env=("INSTALL_JULIA_STABLE_URL" => "file://$empty",))
    @test r.code == 1
    @test r.err == "error: no stable release matching '' for x86_64\n"

    # sort -V across the two-digit minor boundary: 1.10.0 outranks 1.9.9
    # (a plain lexical sort would invert this)
    r = run_script_y(; env)
    @test r.code == 0
    @test occursin("Resolved '' -> 1.10.0 (release)", r.err)
    r = run_script_y("add", "1.9"; env)
    @test r.code == 0
    @test occursin("Resolved '1.9' -> 1.9.9 (release)", r.err)
end
@testset "path warning and flag position" begin
    cleanup()
    mr = fake_mirror("1.0.0")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")

    # SYMLINK_DIR off PATH: install warns, with a copy-pasteable export line
    r = run_script_y("add", "1.0.0"; env)
    @test r.code == 0
    @test occursin("$symlinkdir is not on your PATH", r.err)
    @test occursin("export PATH=\"$symlinkdir:\$PATH\"", r.err)

    # SYMLINK_DIR on PATH: no warning. -y in trailing position must work too:
    # flags set their globals wherever they appear among the arguments.
    r = run_script("add", "1.0.0", "-y";
                   env=(env..., "PATH" => ENV["PATH"] * ":" * symlinkdir))
    @test r.code == 0
    @test !occursin("[y/N]", r.err)
    @test !occursin("is not on your PATH", r.err)

    # and between command and version
    r = run_script("add", "-y", "1.0.0"; env)
    @test r.code == 0
    @test !occursin("[y/N]", r.err)
end
@testset "reinstall flag" begin
    cleanup()
    mr = fake_mirror("1.0.0")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")
    r = run_script_y("add", "1.0.0"; env)
    @test r.code == 0
    @test occursin("Downloading", r.err)   # fresh install downloads

    # -y alone on an installed stable release: symlink refresh only - no
    # re-download, and the installed tree itself is left untouched
    marker = joinpath(installdir, "julia-1.0.0/MARKER")
    write(marker, "x")
    r = run_script_y("add", "1.0.0"; env)
    @test r.code == 0
    @test !occursin("Downloading", r.err)
    @test occursin("symlink julia-1.0.0", r.err)
    @test isfile(marker)

    # auto re-download-and-replace takes BOTH -y and --reinstall
    r = run_script_y("--reinstall", "add", "1.0.0"; env)
    @test r.code == 0
    @test occursin("Downloading", r.err)
    @test occursin("already installed; refreshing", r.err)
    @test !isfile(marker)   # the build was replaced wholesale
    @test isfile(joinpath(installdir, "julia-1.0.0/bin/julia"))
end
@testset "interrupted download" begin
    cleanup()
    mr = fake_mirror("1.0.0")
    # a stalling curl shadowing the real one: it signals it was invoked, then
    # hangs like a dead network until the interrupt below kills it
    farm = mktempdir()
    sentinel = joinpath(farm, "curl-started")
    fakecurl = joinpath(farm, "curl")
    # sleep 30 is only a backstop; the group SIGINT below kills it immediately
    write(fakecurl, "#!/bin/sh\ntouch '$sentinel'\nexec sleep 30\n")
    chmod(fakecurl, 0o755)

    # A terminal's ctrl-C sends SIGINT to the whole foreground process group.
    # Emulate it exactly: setsid (not being a group leader itself) execs the
    # script in place as the leader of a fresh group, so its pid is the group
    # id, and kill(-pid) signals script and stalled curl at once.
    _env = copy(ENV)
    _env["INSTALL_JULIA_STABLE_URL"] = "file://$mr"
    _env["INSTALL_JULIA_NO_VERIFY"] = "1"
    _env["PATH"] = farm * ":" * ENV["PATH"]
    cmd = pipeline(ignorestatus(setenv(`setsid $script -y add 1.0.0`, _env)),
                   stdout=devnull, stderr=devnull)
    p = run(cmd, wait=false)
    @test timedwait(() -> isfile(sentinel), 10.0) == :ok   # download in flight
    pgid = -getpid(p)   # negative pid: signal the whole group
    @test @ccall(kill(pgid::Cint, Base.SIGINT::Cint)::Cint) == 0
    wait(p)
    @test p.termsignal == Base.SIGINT   # died from the signal, not an orderly exit

    # the interrupt left staging litter, but nothing half-installed at a
    # claimable path and no symlinks
    @test !isdir(joinpath(installdir, "julia-1.0.0"))
    @test isdir(joinpath(installdir, ".incoming.julia-1.0.0"))
    @test !isdir(symlinkdir)

    # ...and the next install of the same version reaps it on the way through
    r = run_script_y("add", "1.0.0"; env=(
        "INSTALL_JULIA_STABLE_URL" => "file://$mr",
        "INSTALL_JULIA_NO_VERIFY" => "1",
    ))
    @test r.code == 0
    @test readdir(installdir) == ["julia-1.0.0"]   # no .incoming.*, no .old.*
    @test isfile(joinpath(installdir, "julia-1.0.0/bin/julia"))
end
@testset "nightly and pr" begin
    # A NIGHTLY_BASE-shaped fake mirror: a master nightly, a 1.11 branch
    # nightly, and a pr123 build (nightlies use the filename arch as the
    # bucket dir, with no x64 alias and no minor dir for master).
    cleanup()
    nmr = joinpath(mktempdir(), "mirror")
    for (name, ver) in (
        ("bin/linux/x86_64/julia-latest-linux-x86_64.tar.gz", "1.99.0-DEV"),
        ("bin/linux/x86_64/1.11/julia-latest-linux-x86_64.tar.gz", "1.11.8-DEV"),
        ("bin/linux/x86_64/julia-pr123-linux-x86_64.tar.gz", "1.98.0-DEV"),
    )
        mkpath(dirname(joinpath(nmr, name)))
        write(joinpath(nmr, name), fake_tarball(ver))
    end
    env = ("INSTALL_JULIA_NIGHTLY_URL" => "file://$nmr",
           "INSTALL_JULIA_NO_VERIFY" => "1")

    # master nightly: rolling label, real version read from the tarball, no rollups
    r = run_script_y("nightly"; env)
    @test r.code == 0
    @test occursin("Resolved 'nightly' -> nightly (nightly)", r.err)
    @test occursin("Installed 1.99.0-DEV", r.err)
    @test read(`$(joinpath(symlinkdir, "julia"))`, String) == "fake julia 1.99.0-DEV\n"
    @test !ispath(joinpath(symlinkdir, "julia-1"))   # rolling builds never roll up

    # re-running a rolling build refreshes it (the park-and-swap path), no prompt under -y
    r = run_script_y("add", "nightly"; env)
    @test r.code == 0
    @test occursin("already installed; refreshing", r.err)

    # branch nightly gets its own label and install dir
    r = run_script_y("add", "1.11-nightly"; env)
    @test r.code == 0
    @test occursin("Resolved '1.11-nightly' -> 1.11-nightly (nightly)", r.err)
    @test read(`$(joinpath(symlinkdir, "julia-1.11-nightly"))`, String) ==
        "fake julia 1.11.8-DEV\n"

    r = run_script_y("add", "x-nightly"; env)
    @test r.code == 1
    @test r.err == "error: unrecognized version specifier: x-nightly\n"

    # pr builds are unsigned by design: install skips verification with a
    # warning even when verification is otherwise on
    r = run_script_y("add", "pr123"; env=("INSTALL_JULIA_NIGHTLY_URL" => "file://$nmr",))
    @test r.code == 0
    @test occursin("PR builds are not signed; skipping signature verification", r.err)
    @test read(`$(joinpath(symlinkdir, "julia-pr123"))`, String) == "fake julia 1.98.0-DEV\n"
    @test !ispath(joinpath(symlinkdir, "julia-1"))

    # a pr with no published build dies on the HEAD probe, before installing anything
    r = run_script_y("add", "pr999999999"; env)
    @test r.code == 1
    @test occursin("download failed", r.err)
    @test !isdir(joinpath(installdir, "julia-pr999999999"))

    r = run_script_y("add", "pr12ab"; env)
    @test r.code == 1
    @test r.err == "error: bad pr spec: pr12ab (expected pr<number>)\n"
end
@testset "rollup raising" begin
    # raise_rollup only ever raises: installing an OLDER patch must not lower
    # the X.Y / X links, but a missing link is recreated by the next install
    cleanup()
    mr = fake_mirror("2.0.1", "2.0.2")
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")
    newer = joinpath(installdir, "julia-2.0.2/bin/julia")
    older = joinpath(installdir, "julia-2.0.1/bin/julia")

    r = run_script_y("add", "2.0.2"; env)
    @test r.code == 0
    @test sort(readdir(symlinkdir)) == ["julia-2", "julia-2.0", "julia-2.0.2"]
    @test readdir(installdir) == ["julia-2.0.2"]
    @test readlink(joinpath(symlinkdir, "julia-2.0")) == newer
    @test readlink(joinpath(symlinkdir, "julia-2"))   == newer

    # older patch: direct link appears, rollups stay on 2.0.2
    r = run_script_y("add", "2.0.1"; env)
    @test r.code == 0
    @test sort(readdir(symlinkdir)) == ["julia-2", "julia-2.0", "julia-2.0.1", "julia-2.0.2"]
    @test sort(readdir(installdir)) == ["julia-2.0.1", "julia-2.0.2"]
    @test readlink(joinpath(symlinkdir, "julia-2.0.1")) == older
    @test readlink(joinpath(symlinkdir, "julia-2.0")) == newer
    @test readlink(joinpath(symlinkdir, "julia-2"))   == newer

    # removal drops the newer build's links without repointing them, and
    # leaves exactly the other version's link, build, and no litter
    r = run_script_y("remove", "2.0.2")
    @test r.code == 0
    @test readdir(symlinkdir) == ["julia-2.0.1"]
    @test readdir(installdir) == ["julia-2.0.1"]

    # ...and re-adding the remaining version self-heals the missing rollups
    # (already installed, so -y just refreshes the symlinks)
    r = run_script_y("add", "2.0.1"; env)
    @test r.code == 0
    @test sort(readdir(symlinkdir)) == ["julia-2", "julia-2.0", "julia-2.0.1"]
    @test readdir(installdir) == ["julia-2.0.1"]
    @test readlink(joinpath(symlinkdir, "julia-2.0")) == older
    @test readlink(joinpath(symlinkdir, "julia-2"))   == older

    # a DANGLING rollup (target gone, link left behind) is also healed, not
    # treated as already-newer
    rm(joinpath(symlinkdir, "julia-2.0"))
    symlink(newer, joinpath(symlinkdir, "julia-2.0"))   # 2.0.2 is gone: dangling
    r = run_script_y("add", "2.0.1"; env)
    @test r.code == 0
    @test readlink(joinpath(symlinkdir, "julia-2.0")) == older
    @test sort(readdir(symlinkdir)) == ["julia-2", "julia-2.0", "julia-2.0.1"]

    # removing the OLDER build keeps the newer one fully intact: only the
    # older build's direct link goes (the rollups point into 2.0.2, not 2.0.1)
    r = run_script_y("add", "2.0.2"; env)
    @test r.code == 0
    @test sort(readdir(symlinkdir)) == ["julia-2", "julia-2.0", "julia-2.0.1", "julia-2.0.2"]
    @test readlink(joinpath(symlinkdir, "julia-2.0")) == newer   # raised back
    r = run_script_y("remove", "2.0.1")
    @test r.code == 0
    @test sort(readdir(symlinkdir)) == ["julia-2", "julia-2.0", "julia-2.0.2"]
    @test readdir(installdir) == ["julia-2.0.2"]
    @test readlink(joinpath(symlinkdir, "julia-2.0")) == newer
    @test readlink(joinpath(symlinkdir, "julia-2"))   == newer
end
@testset "arch override" begin
    cleanup()
    # an x86 mirror: stable bucket dir "x86", filename arch "i686"
    mr = fake_mirror("1.0.0"; arch=("x86", "i686"))
    env = ("INSTALL_JULIA_STABLE_URL" => "file://$mr",
           "INSTALL_JULIA_NO_VERIFY" => "1")

    # prefix spec + override: resolves against the overridden arch's builds,
    # labels by the literal spelling the user typed, and skips the rollups
    r = run_script_y("add", "1~x86"; env)
    @test r.code == 0
    @test occursin("Resolved '1~x86' -> 1.0.0~x86 (release)", r.err)
    @test read(`$(joinpath(symlinkdir, "julia-1.0.0~x86"))`, String) == "fake julia 1.0.0\n"
    @test readdir(symlinkdir) == ["julia-1.0.0~x86"]   # no rollups, no default

    # bare override (spec is empty): latest stable for that arch, as default
    r = run_script_y("~x86"; env)
    @test r.code == 0
    @test occursin("Default 'julia' now points to 1.0.0~x86", r.err)

    # nightly + override
    nmr = joinpath(mktempdir(), "mirror")
    nname = "bin/linux/i686/julia-latest-linux-i686.tar.gz"
    mkpath(dirname(joinpath(nmr, nname)))
    write(joinpath(nmr, nname), fake_tarball("1.99.0-DEV"))
    r = run_script_y("add", "nightly~x86"; env=(
        "INSTALL_JULIA_NIGHTLY_URL" => "file://$nmr",
        "INSTALL_JULIA_NO_VERIFY" => "1",
    ))
    @test r.code == 0
    @test occursin("Resolved 'nightly~x86' -> nightly~x86 (nightly)", r.err)
    @test read(`$(joinpath(symlinkdir, "julia-nightly~x86"))`, String) ==
        "fake julia 1.99.0-DEV\n"

    # an unrecognized-but-well-formed arch passes straight through to the URL,
    # so a future Julia arch works with no script update; hyphens are allowed
    for futurearch in ("risx", "x-86")
        rmr = fake_mirror("1.0.0"; arch=(futurearch, futurearch))
        r = run_script_y("add", "1.0.0~$futurearch"; env=(
            "INSTALL_JULIA_STABLE_URL" => "file://$rmr",
            "INSTALL_JULIA_NO_VERIFY" => "1",
        ))
        @test r.code == 0
        @test occursin("Resolved '1.0.0~$futurearch' -> 1.0.0~$futurearch (release)", r.err)
        @test isfile(joinpath(installdir, "julia-1.0.0~$futurearch/bin/julia"))
    end

    # malformed overrides die in resolve_spec, before installing anything.
    # The arch token is everything after the LEFTMOST ~ (a version never
    # contains ~), so "1.0.0~x86~x64" is one bad token, not an x64 override.
    before = sort(readdir(installdir))
    for spec in ("1.0.0~", "1.0.0~~", "1.0.0~x86~x64", "1.0.0~x.86")
        r = run_script_y("add", spec; env)
        @test r.code == 1
        @test r.err == "error: bad arch override in '$spec' (arch must be one or more of A-Za-z0-9_-)\n"
    end
    @test sort(readdir(installdir)) == before

    # a numeric-prefix remove sweeps ~arch copies of that line too, and only them
    @test sort(readdir(installdir)) ==
        ["julia-1.0.0~risx", "julia-1.0.0~x-86", "julia-1.0.0~x86", "julia-nightly~x86"]
    r = run_script_y("remove", "1.0")
    @test r.code == 0
    @test occursin("3 installed versions match '1.0'", r.err)
    @test readdir(installdir) == ["julia-nightly~x86"]
    @test readdir(symlinkdir) == ["julia-nightly~x86"]   # default pointed into a removed copy
end
