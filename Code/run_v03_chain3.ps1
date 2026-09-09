# v0.3 chain #3: extend C2 solves at 1800 s for the points with the largest
# MIP gaps (near-term pc=100 gap 7.8%; near/mature pc=150/200 ~3-4.6%).
$ErrorActionPreference = "Continue"
if (-not $env:JULIA_PROJECT) { $env:JULIA_PROJECT = Join-Path $env:USERPROFILE ".julia\environments\v1.11" }
$dir = $PSScriptRoot
Set-Location $dir
$log = Join-Path $dir "v03_rerun_log3.txt"
"===== v03 chain #3 start $(Get-Date) =====" | Out-File -FilePath $log -Encoding utf8

function Run([string]$label, [string[]]$jargs) {
    Write-Output "===== [$label] $($jargs -join ' ') @ $(Get-Date -Format 'HH:mm:ss') ====="
    "===== [$label] $($jargs -join ' ') @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Out-File -FilePath $log -Append -Encoding utf8
    & julia @jargs | Tee-Object -FilePath $log -Append
    Write-Output "----- [$label] exit $LASTEXITCODE @ $(Get-Date -Format 'HH:mm:ss') -----"
    "----- [$label] exit $LASTEXITCODE -----" | Out-File -FilePath $log -Append -Encoding utf8
}

# 06 C2 keyword args: datadir=..., tag=..., prices=..., timelimit=...
# tag=extended writes policy_C2_extended_v2.csv (rows for the requested prices only)
Run "06C2ext-near"  @("06_policy_C.jl", "near-term", "prices=100,200", "timelimit=1800", "tag=extended")
Run "06C2ext-mature" @("06_policy_C.jl", "mature-market medium", "prices=150,200", "timelimit=1800", "tag=extended")

Write-Output "===== v03 chain #3 DONE @ $(Get-Date -Format 'HH:mm:ss') ====="
"===== v03 chain #3 DONE $(Get-Date) =====" | Out-File -FilePath $log -Append -Encoding utf8
