# v0.3 review re-run chain: policy B non-binding caps -> policy A extended (pc=25/50, 1800s)
# Sequential (8 threads per MIP, safe for this machine).
$ErrorActionPreference = "Continue"
$dir = $PSScriptRoot
if (-not $env:JULIA_PROJECT) { $env:JULIA_PROJECT = Join-Path $env:USERPROFILE ".julia\environments\v1.11" }
Set-Location $dir
$log = Join-Path $dir "v03_rerun_log.txt"
"===== v03 rerun chain start $(Get-Date) =====" | Out-File -FilePath $log -Encoding utf8

function Run([string]$label, [string[]]$jargs) {
    Write-Output "===== [$label] $($jargs -join ' ') @ $(Get-Date -Format 'HH:mm:ss') ====="
    "===== [$label] $($jargs -join ' ') @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Out-File -FilePath $log -Append -Encoding utf8
    & julia @jargs | Tee-Object -FilePath $log -Append
    Write-Output "----- [$label] exit $LASTEXITCODE @ $(Get-Date -Format 'HH:mm:ss') -----"
    "----- [$label] exit $LASTEXITCODE -----" | Out-File -FilePath $log -Append -Encoding utf8
}

# 1) Policy B: non-binding cap points added (LP, fast)
Run "05B-near"  @("05_policy_B.jl", "near-term")
Run "05B-mature" @("05_policy_B.jl", "mature-market medium")

# 2) Policy A: extended solve time for pc=25/50 (free-z MIP, 1800 s each)
Run "04ext-near"  @("04_policy_A.jl", "near-term", "0.9", "prices=25,50", "timelimit=1800", "tag=extended")
Run "04ext-mature" @("04_policy_A.jl", "mature-market medium", "0.9", "prices=25,50", "timelimit=1800", "tag=extended")

# 3) H/C eligibility stress test. The paper reports the +0.25 shift only
#    (SI A.7); it is generated with  HC_SHIFT=+0.25 python generate_data_v2.py
#    and re-solved by run_v03_chain2.ps1 (tag=hc+0.25). An earlier version of
#    this script referenced biochar_data_v2_hc+0.1 / _hc-0.1, which are not
#    produced or used anywhere; those lines were removed 2026-09-09.

Write-Output "===== v03 rerun chain DONE @ $(Get-Date -Format 'HH:mm:ss') ====="
"===== v03 rerun chain DONE $(Get-Date) =====" | Out-File -FilePath $log -Append -Encoding utf8
