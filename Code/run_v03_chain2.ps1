# v0.3 chain #2: verification (02 LP) + C2 re-runs with CORRECTED H/C eligibility
# (300C chars H/C 0.9-1.4 -> never VM0044-eligible; 500C chars H/C 0.40-0.52 -> eligible).
# Sequential (8 threads per MIP).
$ErrorActionPreference = "Continue"
if (-not $env:JULIA_PROJECT) { $env:JULIA_PROJECT = Join-Path $env:USERPROFILE ".julia\environments\v1.11" }
$dir = $PSScriptRoot
Set-Location $dir
$log = Join-Path $dir "v03_rerun_log2.txt"
"===== v03 chain #2 start $(Get-Date) =====" | Out-File -FilePath $log -Encoding utf8

function Run([string]$label, [string[]]$jargs) {
    Write-Output "===== [$label] $($jargs -join ' ') @ $(Get-Date -Format 'HH:mm:ss') ====="
    "===== [$label] $($jargs -join ' ') @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Out-File -FilePath $log -Append -Encoding utf8
    & julia @jargs | Tee-Object -FilePath $log -Append
    Write-Output "----- [$label] exit $LASTEXITCODE @ $(Get-Date -Format 'HH:mm:ss') -----"
    "----- [$label] exit $LASTEXITCODE -----" | Out-File -FilePath $log -Append -Encoding utf8
}

# 1) LP equivalence check: baseline profit/duals must be unchanged by the CC-column edit
Run "02-near"  @("02_LP_duals_v2.jl", "near-term")
Run "02-mature" @("02_LP_duals_v2.jl", "mature-market medium")

# 2) Canonical C2 (tiered tax 25/50/100 + VM0044 credit), 4 prices, both scenarios
Run "06C2-near"  @("06_policy_C.jl", "near-term")
Run "06C2-mature" @("06_policy_C.jl", "mature-market medium")

# 3) H/C +0.25 stress: ag-residue 500C chars flip to ineligible (corn 0.49->0.74 etc.)
Run "06C2hc-near"  @("06_policy_C.jl", "near-term", "datadir=biochar_data_v2_hc+0.25/near-term", "prices=50,200", "tag=hc+0.25")
Run "06C2hc-mature" @("06_policy_C.jl", "mature-market medium", "datadir=biochar_data_v2_hc+0.25/mature-market medium", "prices=50,200", "tag=hc+0.25")

# 4) v2b (quality-differentiated) C2, both scenarios
Run "06C2v2b-near"  @("06_policy_C_v2b.jl", "near-term")
Run "06C2v2b-mature" @("06_policy_C_v2b.jl", "mature-market medium")

Write-Output "===== v03 chain #2 DONE @ $(Get-Date -Format 'HH:mm:ss') ====="
"===== v03 chain #2 DONE $(Get-Date) =====" | Out-File -FilePath $log -Append -Encoding utf8
