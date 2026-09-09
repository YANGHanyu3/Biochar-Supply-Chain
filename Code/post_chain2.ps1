# Post-chain-2: regenerate policy figures (fig8/fig9 use the NEW C2 CSVs),
# rebuild PPTs, sync all figures into paper_draft/figures.
$ErrorActionPreference = "Continue"
$dir = $PSScriptRoot
Set-Location $dir

Write-Output "=== regenerate visualize_v2 (fig2/3/6/7/8) both scenarios ==="
python -X utf8 "visualize_v2.py" "near-term"
python -X utf8 "visualize_v2.py" "mature-market medium"

Write-Output "=== regenerate fig9 policy compare both scenarios ==="
python -X utf8 "fig9_policy_compare.py" "near-term"
python -X utf8 "fig9_policy_compare.py" "mature-market medium"

Write-Output "=== regenerate fig10 tornado (unchanged inputs, refresh) ==="
python -X utf8 "fig10_tornado.py" "near-term" 2>&1 | Out-String | Write-Output
python -X utf8 "fig10_tornado.py" "mature-market medium" 2>&1 | Out-String | Write-Output

Write-Output "=== rebuild PPTs ==="
python -X utf8 "make_ppt.py" "near-term" "..\05_PPT\Biochar_Progress_near-term_v03.pptx"
python -X utf8 "make_ppt.py" "mature-market medium" "..\05_PPT\Biochar_Progress_mature-market_v03.pptx"

Write-Output "=== sync figures to paper_draft/figures ==="
$dst = Join-Path (Split-Path $dir -Parent) "06_Model_LaTeX\paper_draft\figures"
if (-not (Test-Path $dst)) { $dst = Join-Path (Split-Path $dir -Parent) "Paper\paper_draft\figures" }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item "results_v2\near-term\figures\*.png" $dst -Force
Copy-Item "results_v2\mature-market medium\figures\*.png" $dst -Force
# v2b figures (fig11/fig12) live elsewhere; copy the canonical ones
Copy-Item "results_v2b\fig11_v2b_mix.png" $dst -Force -ErrorAction SilentlyContinue
Copy-Item "results_v2b\fig12_credit_basis.png" $dst -Force
Get-ChildItem $dst | Select-Object Name, Length | Format-Table -AutoSize
Write-Output "post-chain-2 DONE"
