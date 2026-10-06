# Move match and tournament dirs older than N days to an archive drive the
# dashboard does not scan (his ruling 2026-10-06: old runs go to the spinning
# disks). Same layout under the destination; a dir is removed from the repo
# only after robocopy copied it without failure.
#   powershell -File tools/archive_runs.ps1 [-Days 3] [-Dest G:\bar-ai-archive] [-DryRun]
param([int]$Days = 3, [string]$Dest = "G:\bar-ai-archive", [switch]$DryRun)
$root = Split-Path -Parent $PSScriptRoot
$cut = (Get-Date).AddDays(-$Days)
$moved = 0; $failed = 0
foreach ($kind in @("tournaments", "matches")) {
    $src = Join-Path $root $kind
    $old = Get-ChildItem $src -Directory | Where-Object { ($_.Name -notlike "_*") -and ($_.LastWriteTime -lt $cut) }
    "{0}: {1} dir(s) older than {2} days" -f $kind, $old.Count, $Days
    if ($DryRun) { continue }
    foreach ($d in $old) {
        $to = Join-Path (Join-Path $Dest $kind) $d.Name
        robocopy $d.FullName $to /E /MOVE /MT:16 /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -lt 8) {
            if (Test-Path $d.FullName) { Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            $moved++
        } else {
            $failed++
            "FAILED {0} (robocopy {1})" -f $d.FullName, $LASTEXITCODE
        }
    }
}
"moved {0}, failed {1} -> {2}" -f $moved, $failed, $Dest
