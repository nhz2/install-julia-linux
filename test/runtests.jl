using Test
using Expect: ExpectProc, expect!

const script = joinpath(dirname(@__DIR__), "src", "install-julia.sh")
const workingdir = mktempdir()
const installdir = joinpath(workingdir, "packages/julias")
const symlinkdir = joinpath(workingdir, ".local/bin")
# Need to set this here instead of when running to work around Expect.jl bug/limitation
ENV["INSTALL_JULIA_INSTALL_DIR"] = installdir
ENV["INSTALL_JULIA_SYMLINK_DIR"] = symlinkdir

function cleanup()
    rm(installdir, force=true, recursive=true)
    rm(symlinkdir, force=true, recursive=true)
end

function run_script(args::String...; env=())
    _env = copy(ENV)
    for (k, v) in env
        _env[k] = v
    end
    out, err = IOBuffer(), IOBuffer()
    cmd = pipeline(ignorestatus(setenv(Cmd([script, args...]), _env)), stdout=out, stderr=err)
    p = run(cmd)
    (; code=p.exitcode, out=String(take!(out)), err=String(take!(err)))
end
function run_script_y(args::String...; kwargs...)
    run_script("-y", args...; kwargs...)
end


@testset "shellcheck" begin
    run(`shellcheck $(script) --severity=warning`)
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
    @test !isdir(installdir)   # died before mkdir -p INSTALL_DIR
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
    # ln -sfn's -n: a default link pointing at a DIRECTORY must be replaced,
    # not dereferenced (without -n the new link lands inside the directory)
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
end
@testset "offline mirror install" begin
    # A file:// mirror built from a local fixture exercises the full install path
    # offline: manifest resolution, download, GPG verification, staging, the
    # atomic claim, symlinks, and that a successful install leaves no litter.
    tarname = "julia-1.12.6-linux-x86_64.tar.gz"
    fixture = joinpath(dirname(@__DIR__), tarname)
    if !(isfile(fixture) && isfile(fixture * ".asc") && Sys.ARCH == :x86_64)
        @info "skipping offline mirror install tests ($tarname fixture not present)"
    else
        cleanup()
        mirror = mktempdir()
        bucket = joinpath(mirror, "bin/linux/x64/1.12")
        mkpath(bucket)
        cp(fixture, joinpath(bucket, tarname))
        cp(fixture * ".asc", joinpath(bucket, tarname * ".asc"))
        write(joinpath(mirror, "bin/versions.json"),
            """{"1.12.6":{"files":[{"url":"https://julialang-s3.julialang.org/bin/linux/x64/1.12/$tarname"}]}}""")
        env = ("INSTALL_JULIA_STABLE_URL" => "file://$mirror",)

        # fresh install: resolves 1.12 -> 1.12.6 from the manifest, reaps this
        # version's stale staging namespace, installs, links direct + rollup but
        # no default
        stale = joinpath(installdir, ".incoming.julia-1.12.6/424242")
        mkpath(joinpath(stale, "julia-1.12.6"))
        r = run_script_y("add", "1.12"; env)
        @test r.code == 0
        @test occursin("Resolved '1.12' -> 1.12.6 (release)", r.err)
        @test isfile(joinpath(installdir, "julia-1.12.6/bin/julia"))
        @test islink(joinpath(symlinkdir, "julia-1.12.6"))
        @test islink(joinpath(symlinkdir, "julia-1.12"))
        @test !islink(joinpath(symlinkdir, "julia"))   # add keeps the default alone
        @test !isdir(stale)
        @test isempty(filter(startswith("."), readdir(installdir)))

        # --reinstall takes the park-and-swap path and is just as clean
        r = run_script_y("--reinstall", "add", "1.12.6"; env)
        @test r.code == 0
        @test occursin("already installed; refreshing", r.err)
        @test isfile(joinpath(installdir, "julia-1.12.6/bin/julia"))
        @test isempty(filter(startswith("."), readdir(installdir)))
    end
end
# @testset "default" begin
#     cleanup()
#     r = run_script_y()
#     @test r.code == 0
#     @test startswith(r.err, "==> Resolved '' -> ")
#     resolved_version = split(r.err, ' ')[5]
#     @test readchomp(`$(symlinkdir*"/julia") --version`) == "julia version $(resolved_version)"
# end
