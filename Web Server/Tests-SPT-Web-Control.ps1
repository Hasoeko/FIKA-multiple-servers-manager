Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSCommandPath
$modulePath = Join-Path $root 'SPT-Web-Control.psm1'

Import-Module $modulePath -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        $Actual,

        [Parameter(Mandatory = $true)]
        $Expected,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$paths = Get-SptControlPaths
Assert-Equal $paths.SingleServerExe 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\SPT.Server.exe' 'Single player server path mismatch.'
Assert-Equal $paths.SingleLogDir 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\user\logs\spt' 'Single player SPT log directory mismatch.'
Assert-Equal $paths.CoopServerExe 'C:\Games\EscapeFromTarkov\EFT coop\SPT\SPT.Server.exe' 'Coop server path mismatch.'
Assert-Equal $paths.CoopLogDir 'C:\Games\EscapeFromTarkov\EFT coop\SPT\user\logs\spt' 'Coop SPT log directory mismatch.'
Assert-Equal $paths.HeadlessExe 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\FikaHeadlessManager.exe' 'Headless path mismatch.'
Assert-Equal $paths.TarkovExe 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\EscapeFromTarkov.exe' 'Tarkov process path mismatch.'
Assert-Equal $paths.BepInExLog 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\BepInEx\FullLogOutput.log' 'BepInEx log path mismatch.'

$fileRoots = Get-SptFileRoots
Assert-Equal $fileRoots.sp 'C:\Games\EscapeFromTarkov\EscapeFromTarkov' 'SP file root mismatch.'
Assert-Equal $fileRoots.coop 'C:\Games\EscapeFromTarkov\EFT coop' 'Coop file root mismatch.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('spt-web-control-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$realEditablePath = $null
$realListTestDir = $null

try {
    $configPath = Join-Path $tempRoot 'config.json'
    $config = Get-SptControlConfig -ConfigPath $configPath
    Assert-Equal $config.port 8787 'Default port mismatch.'
    Assert-Equal $config.password '0000' 'Default password mismatch.'
    Assert-True (Test-Path -LiteralPath $configPath -PathType Leaf) 'Config file was not created.'

    $statePath = Join-Path $tempRoot 'state.json'
    $state = Get-SptControlState -StatePath $statePath
    Assert-True (-not [bool]$state.logSessionActive) 'Default state should not show old server logs.'

    $state.currentMode = 'single'
    $state.logSessionActive = $false
    Save-SptControlState -StatePath $statePath -State $state
    $status = Get-SptStatus -StatePath $statePath
    Assert-True ($null -eq $status.serverLogPath) 'Server log path should stay hidden before a web launch/restart.'

    Assert-Equal (Get-LogLineLevel 'Fatal exception happened') 'error' 'Fatal lines should be error.'
    Assert-Equal (Get-LogLineLevel 'WARN missing profile') 'warning' 'Warn lines should be warning.'
    Assert-Equal (Get-LogLineLevel '[Debug] loaded plugin') 'debug' 'Debug lines should be debug.'
    Assert-Equal (Get-LogLineLevel 'Server started') 'info' 'Normal lines should be info.'

    $logDir = Join-Path $tempRoot 'logs'
    New-Item -ItemType Directory -Path $logDir | Out-Null
    $oldLog = Join-Path $logDir 'old.log'
    $newLog = Join-Path $logDir 'new.log'
    Set-Content -LiteralPath $oldLog -Value 'old'
    Set-Content -LiteralPath $newLog -Value 'new'
    (Get-Item -LiteralPath $oldLog).LastWriteTime = (Get-Date).AddMinutes(-5)
    (Get-Item -LiteralPath $newLog).LastWriteTime = Get-Date

    $latest = Get-NewestLogFile -DirectoryPath $logDir
    Assert-Equal $latest $newLog 'Newest log selection mismatch.'

    $sampleLog = Join-Path $tempRoot 'sample.log'
    Set-Content -LiteralPath $sampleLog -Value @(
        'Server started',
        'WARN missing profile',
        'Fatal exception happened'
    )
    $snapshot = Get-LogSnapshot -Path $sampleLog -MaxLines 10
    Assert-Equal $snapshot.lines.Count 3 'Log snapshot should return three text lines.'
    Assert-Equal $snapshot.levels.Count 3 'Log snapshot should return three levels.'
    Assert-Equal $snapshot.lines[0] 'Server started' 'Log lines should be plain strings.'
    Assert-Equal $snapshot.levels[1] 'warning' 'Warning level mismatch.'
    Assert-Equal $snapshot.levels[2] 'error' 'Error level mismatch.'
    $snapshotJson = ConvertTo-Json -InputObject $snapshot -Depth 4 -Compress
    Assert-True (-not $snapshotJson.Contains('PSPath')) 'Serialized log snapshot should not include PowerShell file metadata.'

    $realEditableName = 'codex-helper-read-' + [guid]::NewGuid().ToString('N') + '.txt'
    $realEditablePath = Join-Path $fileRoots.sp $realEditableName
    Set-Content -LiteralPath $realEditablePath -Value 'plain editable content'
    $editable = Read-SptTextFile -RootKey 'sp' -RelativePath $realEditableName
    Assert-Equal $editable.content.GetType().FullName 'System.String' 'Editable file content should be a plain string.'
    $editableJson = ConvertTo-Json -InputObject $editable -Depth 4 -Compress
    Assert-True (-not $editableJson.Contains('PSPath')) 'Serialized editable file content should not include PowerShell file metadata.'

    $realListTestName = 'codex-list-order-' + [guid]::NewGuid().ToString('N')
    $realListTestDir = Join-Path $fileRoots.sp $realListTestName
    New-Item -ItemType Directory -Path $realListTestDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $realListTestDir 'folder-a') | Out-Null
    Set-Content -LiteralPath (Join-Path $realListTestDir 'editable.txt') -Value 'editable'
    Set-Content -LiteralPath (Join-Path $realListTestDir 'binary.dll') -Value 'binary'
    $listing = Get-SptDirectoryListing -RootKey 'sp' -RelativePath $realListTestName
    Assert-Equal $listing.items[0].type 'folder' 'Folders should appear before files.'
    Assert-Equal $listing.items[1].name 'editable.txt' 'Editable files should appear before uneditable files.'
    Assert-Equal $listing.items[2].name 'binary.dll' 'Uneditable files should appear at the bottom.'

    $fileRoot = Join-Path $tempRoot 'managed-root'
    New-Item -ItemType Directory -Path $fileRoot | Out-Null
    $safePath = Resolve-SptManagedPath -RootPath $fileRoot -RelativePath 'user\mods\config.json'
    Assert-Equal $safePath (Join-Path $fileRoot 'user\mods\config.json') 'Safe managed path mismatch.'

    $pathRejected = $false
    try {
        Resolve-SptManagedPath -RootPath $fileRoot -RelativePath '..\outside.txt' | Out-Null
    }
    catch {
        $pathRejected = $true
    }
    Assert-True $pathRejected 'Path traversal should be rejected.'

    Assert-True (Test-SptEditableFile -Path 'profile.json') 'JSON files should be editable.'
    Assert-True (-not (Test-SptEditableFile -Path 'EscapeFromTarkov.exe')) 'EXE files should not be editable.'

    $trashRoot = Join-Path $tempRoot 'trash'
    $deleteSource = Join-Path $fileRoot 'delete-me.txt'
    Set-Content -LiteralPath $deleteSource -Value 'move me'
    $trashTarget = Move-SptPathToTrash -SourcePath $deleteSource -TrashRoot $trashRoot -RootKey 'sp'
    Assert-True (-not (Test-Path -LiteralPath $deleteSource)) 'Deleted file should leave source location.'
    Assert-True (Test-Path -LiteralPath $trashTarget -PathType Leaf) 'Deleted file should move to trash.'
    Assert-True ($trashTarget.StartsWith((Join-Path $trashRoot 'sp'))) 'Trash path should preserve source root key.'
}
finally {
    if ($realEditablePath -and (Test-Path -LiteralPath $realEditablePath)) {
        Remove-Item -LiteralPath $realEditablePath -Force
    }
    if ($realListTestDir -and (Test-Path -LiteralPath $realListTestDir)) {
        Remove-Item -LiteralPath $realListTestDir -Recurse -Force
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host 'All SPT web control helper tests passed.'
