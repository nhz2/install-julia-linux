using Test

const script = joinpath(dirname(@__DIR__), "src", "install-julia.sh")
const workingdir = mktempdir()

function run_script(args::String...; input=nothing, env=())
    _env = copy(ENV)
    _env["INSTALL_JULIA_INSTALL_DIR"] = joinpath(workingdir, "packages/julias")
    _env["INSTALL_JULIA_SYMLINK_DIR"] = joinpath(workingdir, ".local/bin")
    for (k, v) in env
        _env[k] = v
    end
    out, err = IOBuffer(), IOBuffer()
    cmd = if isnothing(input)
        pipeline(ignorestatus(setenv(Cmd([script, args...]), _env)), stdout=out, stderr=err)
    else
        pipeline(ignorestatus(setenv(Cmd([script, args...]), _env)), stdout=out, stderr=err, stdin=IOBuffer(input))
    end
    p = run(cmd)
    (; code=p.exitcode, out=String(take!(out)), err=String(take!(err)))
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
@testset "default" begin
    r = run_script()
    @test r.code == 0
end
