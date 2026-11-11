# 전체 테스트를 뒤에서 돌리기 (CI 방식, 2026-11-11 사용자 결정)
#   지금 커밋을 따로 떼어 낸 사본(git worktree, 저장소 옆 _test_worktree)에서 돌리므로
#   원본을 계속 고쳐도 테스트가 섞이지 않는다. 테스트 파일을 여러 묶음으로 나눠 동시에 돌린다.
# 사용: powershell -ExecutionPolicy Bypass -File tools/test_bg.ps1 [-Shards 4] [-Godot 경로]
# 결과: ..\_test_logs\summary.txt (실패만 자세히), 묶음별 로그 shard_N.log, 파일별 시간 times.json (다음 묶음 나누기에 씀)
# 화면이 필요한 ui_*.gd 점검은 여기서 돌리지 않는다 (작업마다 따로).

param(
    [int]$Shards = 4,
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$root = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$parent = Split-Path $root -Parent
$wt = Join-Path $parent "_test_worktree"
$logs = Join-Path $parent "_test_logs"

if ($Godot -eq "") {
    $cands = @($env:GODOT_BIN,
        "C:\Users\koo29\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
        "C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { $Godot = $c; break } }
}
if (-not (Test-Path $Godot)) { throw "Godot 실행 파일을 찾을 수 없다 (-Godot 경로 또는 환경 변수 GODOT_BIN)" }

# 1) 지금 커밋의 사본
$sha = (git -C $root rev-parse HEAD).Trim()
if (-not (Test-Path (Join-Path $wt ".git"))) {
    git -C $root worktree add --detach $wt $sha | Out-Null
} else {
    git -C $wt reset -q --hard $sha
}
# 가져오기 캐시(.godot)를 복사해 두면 사본에서 다시 가져오는 시간이 짧다
robocopy (Join-Path $root ".godot") (Join-Path $wt ".godot") /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
New-Item -ItemType Directory -Force $logs | Out-Null
& $Godot --headless --path $wt --import *> (Join-Path $logs "import.log")

# 2) 묶음 나누기: 지난번 파일별 시간으로 고르게 (없으면 1분으로 친다)
$times = @{}
$timesPath = Join-Path $logs "times.json"
if (Test-Path $timesPath) {
    (Get-Content $timesPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $times[$_.Name] = [double]$_.Value }
}
$files = Get-ChildItem (Join-Path $wt "tests") -Filter "test_*.gd" | Where-Object { $_.Name -ne "test_suite.gd" } | ForEach-Object { $_.Name }
$files = $files | Sort-Object { if ($times.ContainsKey($_)) { -$times[$_] } else { -60 } }
$groups = @(); $load = @()
for ($i = 0; $i -lt $Shards; $i++) { $groups += ,@(); $load += 0.0 }
foreach ($f in $files) {
    $k = 0
    for ($i = 1; $i -lt $Shards; $i++) { if ($load[$i] -lt $load[$k]) { $k = $i } }
    $groups[$k] += $f
    $load[$k] += $(if ($times.ContainsKey($f)) { $times[$f] } else { 60.0 })
}

# 3) 동시에 돌리기
$start = Get-Date
$procs = @()
for ($i = 0; $i -lt $Shards; $i++) {
    if ($groups[$i].Count -eq 0) { continue }
    $log = Join-Path $logs "shard_$i.log"
    $arg = @("--headless", "--path", "`"$wt`"", "-s", "res://tests/run_tests.gd", "--", ($groups[$i] -join ","))
    $procs += Start-Process -FilePath $Godot -ArgumentList $arg -RedirectStandardOutput $log -RedirectStandardError (Join-Path $logs "shard_$i.err") -NoNewWindow -PassThru
}
$procs | Wait-Process

# 4) 정리
$pass = 0; $fail = 0; $failed = @()
for ($i = 0; $i -lt $Shards; $i++) {
    $log = Join-Path $logs "shard_$i.log"
    if (-not (Test-Path $log)) { continue }
    $lines = Get-Content $log -Encoding UTF8
    $cur = ""
    foreach ($l in $lines) {
        if ($l -match "^결과: (\d+) 통과, (\d+) 실패") { $pass += [int]$Matches[1]; $fail += [int]$Matches[2] }
        elseif ($l -match "^\s+([\d\.]+)초\s+(test_\S+\.gd)") { $times[$Matches[2]] = [double]$Matches[1] }
        elseif ($l -match "^  실패  ") { $failed += $l.Trim() }
        elseif ($l -match "^        - ") { $failed += "    " + $l.Trim() }
        elseif ($l -match "SCRIPT ERROR|Parse Error") { $failed += "  [shard $i] " + $l.Trim() }
    }
}
($times | ConvertTo-Json) | Set-Content $timesPath -Encoding UTF8
$mins = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
$summary = @("커밋 $($sha.Substring(0,7)) · $Shards 묶음 · $mins 분", "결과: $pass 통과, $fail 실패") + $failed
$summary | Set-Content (Join-Path $logs "summary.txt") -Encoding UTF8
$summary | ForEach-Object { Write-Output $_ }
