# Installs @SHORT@ @VARIANT@ into a Beyond All Reason install. Run through Install.bat.
param(
    [string]$BarData = "",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$Short = "@SHORT@"
$Variant = "@VARIANT@"
$Engine = "@ENGINE@"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here "$Short\$Variant"

function Say($msg) { Write-Host "  $msg" }
function Fail($msg) {
    Write-Host ""
    Write-Host "  INSTALL FAILED: $msg" -ForegroundColor Red
    exit 1
}
function Ask($question) {
    if ($Yes) { return $true }
    $a = Read-Host "  $question [y/N]"
    return $a -match '^(y|yes)$'
}

function DataDirOf($dir) {
    if (-not $dir) { return $null }
    foreach ($d in @($dir, (Join-Path $dir "data"))) {
        if (Test-Path -LiteralPath (Join-Path $d "engine") -PathType Container) {
            return (Resolve-Path -LiteralPath $d).Path
        }
    }
    return $null
}

function FindBar {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason"),
        (Join-Path $env:ProgramFiles "Beyond-All-Reason")
    )
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} "Beyond-All-Reason") }
    foreach ($hive in @("HKCU:", "HKLM:", "HKLM:\SOFTWARE\WOW6432Node")) {
        $key = "$hive\Software\Microsoft\Windows\CurrentVersion\Uninstall"
        if ($hive -like "*WOW6432Node") { $key = "$hive\Microsoft\Windows\CurrentVersion\Uninstall" }
        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like "Beyond*All*Reason*" -and $p.InstallLocation) { $roots += $p.InstallLocation }
        }
    }
    foreach ($r in $roots) {
        $d = DataDirOf $r
        if ($d) { return $d }
    }
    return $null
}

function BarProcesses($root) {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    })
}

# The lobby hides every AI it has no simple name for while simpleAiList is on (its default), and the
# checkbox sits on the Developer tab, which only devmode.txt shows. The lobby rewrites IGL_data.lua
# when it closes, so this runs with BAR closed.
function ShowFullAiList($data) {
    $devmode = Join-Path $data "devmode.txt"
    if (-not (Test-Path -LiteralPath $devmode)) { New-Item -ItemType File -Path $devmode | Out-Null }
    $igl = Join-Path $data "LuaMenu\Config\IGL_data.lua"
    if (Test-Path -LiteralPath $igl) {
        $text = [IO.File]::ReadAllText($igl)
        if ($text -match 'simpleAiList\s*=\s*false') { return }
        Copy-Item -LiteralPath $igl "$igl.before-apex" -Force
        if ($text -match 'simpleAiList\s*=\s*true') {
            $text = $text -replace 'simpleAiList\s*=\s*true', 'simpleAiList = false'
        } elseif ($text -match '\["Chili lobby"\]\s*=\s*\{') {
            $text = ([regex]'(\["Chili lobby"\]\s*=\s*\{)').Replace($text, "`$1`n`t`tsimpleAiList = false,", 1)
        } elseif ($text -match 'return\s*\{') {
            $text = ([regex]'(return\s*\{)').Replace($text, "`$1`n`t[`"Chili lobby`"] = {`n`t`tsimpleAiList = false,`n`t},", 1)
        } else {
            throw "unrecognised lobby settings file $igl"
        }
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $igl) | Out-Null
        $text = "return {`n`t[`"Chili lobby`"] = {`n`t`tsimpleAiList = false,`n`t},`n}`n"
    }
    [IO.File]::WriteAllText($igl, $text, (New-Object Text.UTF8Encoding($false)))
}

function PickFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select your Beyond All Reason install folder (the one that contains 'data')"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

Write-Host ""
Write-Host "  Installing $Short $Variant for Beyond All Reason" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath (Join-Path $Payload "AIInfo.lua"))) {
    Fail "the AI files are missing from $Payload. Extract the whole zip and run Install.bat again."
}

if ($BarData) {
    $data = DataDirOf $BarData
    if (-not $data) { Fail "no BAR install at $BarData (expected a folder with data\engine inside)." }
} else {
    $data = FindBar
    if (-not $data) {
        Say "Could not find Beyond All Reason automatically."
        Say "A window will open: pick the folder you installed BAR into."
        $data = DataDirOf (PickFolder)
        if (-not $data) { Fail "no BAR install selected (the folder needs a data\engine folder inside)." }
    }
}
Say "BAR found:  $data"

$engines = @(Get-ChildItem -LiteralPath (Join-Path $data "engine") -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "AI\Skirmish") } |
    Sort-Object LastWriteTime -Descending)
if ($engines.Count -eq 0) { Fail "BAR has no engine installed yet. Start BAR once, let it update, then run this again." }

$eng = $engines | Where-Object { $_.Name -eq $Engine } | Select-Object -First 1
if (-not $eng) {
    $eng = $engines[0]
    Write-Host ""
    Say "This AI was built for engine $Engine, which is not installed."
    Say "Installed: $(($engines | ForEach-Object { $_.Name }) -join ', ')"
    Say "It may fail to load on $($eng.Name). A build for that engine is safer."
    if (-not (Ask "Install into $($eng.Name) anyway?")) { Fail "cancelled." }
}
Say "Engine:     $($eng.Name)"

$target = Join-Path $eng.FullName "AI\Skirmish\$Short\$Variant"
$barRoot = $data
if ((Split-Path -Leaf $data) -eq "data") { $barRoot = Split-Path -Parent $data }
if (Test-Path -LiteralPath $target) {
    Say "Replacing the copy already installed."
    try {
        Remove-Item -LiteralPath $target -Recurse -Force
    } catch {
        if ((BarProcesses $barRoot).Count -gt 0) { Fail "a game is running and has this AI loaded. Close BAR and run this again." }
        Fail "could not remove the old copy at $target : $($_.Exception.Message)"
    }
}

try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $Payload -Destination $target -Recurse -Force
    Get-ChildItem -LiteralPath $target -Recurse -File | Unblock-File
} catch {
    Fail "copying to $target failed: $($_.Exception.Message)"
}
if (-not (Test-Path -LiteralPath (Join-Path $target "SkirmishAI.dll"))) { Fail "the copy is incomplete at $target." }
Say "AI files:   $target"

$listed = $false
while ($true) {
    if ((BarProcesses $barRoot).Count -eq 0) {
        try {
            ShowFullAiList $data
            $listed = $true
        } catch {
            Say "Could not change the lobby setting: $($_.Exception.Message)"
        }
        break
    }
    Write-Host ""
    Say "BAR is open. Its lobby must be closed to switch on the full AI list"
    Say "(it saves its settings when it closes and would undo the change)."
    if ($Yes) { break }
    $a = Read-Host "  Close BAR completely, then press Enter (or type S to skip)"
    if ($a -match '^(s|skip)$') { break }
}

Write-Host ""
Write-Host "  Done. $Short $Variant is installed." -ForegroundColor Green
if ($listed) {
    Say "The lobby will show the full AI list (devmode.txt made, 'Simple AI list' off)."
} else {
    Say "The lobby setting was NOT changed. To see $Short in the AI list, run Install.bat"
    Say "again with BAR closed, or make an empty file named devmode.txt in"
    Say "$data"
    Say "and untick 'Simple AI list' under Settings > Developer in the lobby."
}
Write-Host ""
Say "Start BAR. In a lobby, Add AI and pick $Short $Variant."
Say "Only the player hosting the game needs this. After a BAR engine update,"
Say "run Install.bat again."
exit 0
