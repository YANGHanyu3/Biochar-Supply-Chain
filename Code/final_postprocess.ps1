# Final post-processing after chain #3: patch canonical C2 CSVs with extended
# incumbents, regenerate figures, rebuild PPTs, sync figures, run static check.
$ErrorActionPreference = "Continue"
$dir = $PSScriptRoot
Set-Location $dir

Write-Output "=== 1. patch canonical C2 CSVs ==="
python -X utf8 "patch_policyC_extended.py"

Write-Output "=== 2. print patched C2 numbers for paper check ==="
python -X utf8 -c "
import pandas as pd
for sc in ['near-term', 'mature-market medium']:
    s = pd.read_csv(rf'results_v2\{sc}\policy_C2_tax_credit_v2.csv')
    print('==', sc)
    print(s[['p_c','profit','bc','bc300','bc500','cc','emis','gap','status']].round(2).to_string())
"

Write-Output "=== 3. regenerate all figures ==="
python -X utf8 "visualize_v2.py" "near-term"
python -X utf8 "visualize_v2.py" "mature-market medium"
python -X utf8 "fig9_policy_compare.py" "near-term"
python -X utf8 "fig9_policy_compare.py" "mature-market medium"
python -X utf8 "fig10_tornado.py" "near-term"
python -X utf8 "fig10_tornado.py" "mature-market medium"
python -X utf8 "fig12_credit_basis.py"

Write-Output "=== 4. rebuild PPTs ==="
python -X utf8 "make_ppt.py" "near-term" "..\05_PPT\Biochar_Progress_near-term_v03.pptx"
python -X utf8 "make_ppt.py" "mature-market medium" "..\05_PPT\Biochar_Progress_mature-market_v03.pptx"

Write-Output "=== 5. sync figures to paper_draft/figures ==="
$dst = Join-Path (Split-Path $dir -Parent) "06_Model_LaTeX\paper_draft\figures"
if (-not (Test-Path $dst)) { $dst = Join-Path (Split-Path $dir -Parent) "Paper\paper_draft\figures" }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item "results_v2\near-term\figures\*.png" $dst -Force
Copy-Item "results_v2\mature-market medium\figures\*.png" $dst -Force
Copy-Item "results_v2b\fig11_v2b_mix.png" $dst -Force -ErrorAction SilentlyContinue
Copy-Item "results_v2b\fig12_credit_basis.png" $dst -Force
Get-ChildItem $dst | Select-Object Name, Length | Format-Table -AutoSize

Write-Output "=== 6. static tex check ==="
python -X utf8 "..\03_Data\WI_Working_Files\tex_static_check.py"

Write-Output "=== FINAL POST-PROCESSING DONE ==="
