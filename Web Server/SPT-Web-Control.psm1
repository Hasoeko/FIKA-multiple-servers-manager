Set-StrictMode -Version Latest

function Get-SptControlPaths {
    [pscustomobject]@{
        SingleServerExe = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\SPT.Server.exe'
        SingleLogDir = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\user\logs\spt'
        CoopServerExe = 'C:\Games\EscapeFromTarkov\EFT coop\SPT\SPT.Server.exe'
        CoopLogDir = 'C:\Games\EscapeFromTarkov\EFT coop\SPT\user\logs\spt'
        HeadlessExe = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\FikaHeadlessManager.exe'
        TarkovExe = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\EscapeFromTarkov.exe'
        BepInExLog = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\BepInEx\FullLogOutput.log'
        Host = '127.0.0.1'
        ServerPort = 6969
        StartupTimeoutSeconds = 180
    }
}

function Get-SptFileRoots {
    [pscustomobject]@{
        sp = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov'
        coop = 'C:\Games\EscapeFromTarkov\EFT coop'
    }
}

function Get-SptFileRootPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey
    )

    $roots = Get-SptFileRoots
    return [string]$roots.$RootKey
}

function Resolve-SptManagedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [AllowEmptyString()]
        [string]$RelativePath = ''
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $relative = [string]$RelativePath
    if ([System.IO.Path]::IsPathRooted($relative)) {
        throw 'Absolute paths are not allowed.'
    }

    $combinedPath = [System.IO.Path]::Combine($rootFullPath, $relative)
    $fullPath = [System.IO.Path]::GetFullPath($combinedPath)
    if ($fullPath -ne $rootFullPath -and -not $fullPath.StartsWith($rootFullPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path is outside the allowed folder.'
    }

    return $fullPath
}

function Resolve-SptFileRequestPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey,

        [AllowEmptyString()]
        [string]$RelativePath = ''
    )

    Resolve-SptManagedPath -RootPath (Get-SptFileRootPath -RootKey $RootKey) -RelativePath $RelativePath
}

function ConvertTo-SptRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$FullPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $pathFull = [System.IO.Path]::GetFullPath($FullPath)
    if ($pathFull -eq $rootFullPath) {
        return ''
    }

    return $pathFull.Substring($rootFullPath.Length + 1)
}

function Test-SptEditableFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $editableExtensions = @(
        '.json', '.txt', '.cfg', '.ini', '.log', '.xml', '.yaml', '.yml',
        '.md', '.js', '.css', '.html', '.htm', '.config', '.csv'
    )
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return $editableExtensions -contains $extension
}

function Get-SptDirectoryListing {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey,

        [AllowEmptyString()]
        [string]$RelativePath = ''
    )

    $rootPath = Get-SptFileRootPath -RootKey $RootKey
    $fullPath = Resolve-SptManagedPath -RootPath $rootPath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw 'Folder not found.'
    }

    $items = @(Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction Stop | Sort-Object @{ Expression = {
        if ($_.PSIsContainer) {
            0
        }
        elseif (Test-SptEditableFile -Path $_.FullName) {
            1
        }
        else {
            2
        }
    } }, Name | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            path = ConvertTo-SptRelativePath -RootPath $rootPath -FullPath $_.FullName
            type = if ($_.PSIsContainer) { 'folder' } else { 'file' }
            size = if ($_.PSIsContainer) { $null } else { $_.Length }
            modified = $_.LastWriteTime.ToString('s')
            editable = (-not $_.PSIsContainer -and (Test-SptEditableFile -Path $_.FullName))
        }
    })

    $parent = $null
    if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
        $parentFullPath = [System.IO.Directory]::GetParent($fullPath).FullName
        $parent = ConvertTo-SptRelativePath -RootPath $rootPath -FullPath $parentFullPath
    }

    [pscustomobject]@{
        root = $RootKey
        path = ConvertTo-SptRelativePath -RootPath $rootPath -FullPath $fullPath
        parent = $parent
        items = $items
    }
}

function Read-SptTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Resolve-SptFileRequestPath -RootKey $RootKey -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw 'File not found.'
    }
    if (-not (Test-SptEditableFile -Path $fullPath)) {
        throw 'This file type is not editable in the browser.'
    }

    $item = Get-Item -LiteralPath $fullPath
    if ($item.Length -gt 2097152) {
        throw 'File is too large for browser editing. Limit is 2 MB.'
    }

    [pscustomobject]@{
        path = $RelativePath
        content = [string](Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop)
        modified = $item.LastWriteTime.ToString('s')
    }
}

function Save-SptTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [AllowEmptyString()]
        [string]$Content = ''
    )

    $fullPath = Resolve-SptFileRequestPath -RootKey $RootKey -RelativePath $RelativePath
    if (-not (Test-SptEditableFile -Path $fullPath)) {
        throw 'This file type is not editable in the browser.'
    }
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'Parent folder not found.'
    }

    Set-Content -LiteralPath $fullPath -Value $Content -Encoding UTF8
    $item = Get-Item -LiteralPath $fullPath
    [pscustomobject]@{
        path = $RelativePath
        size = $item.Length
        modified = $item.LastWriteTime.ToString('s')
    }
}

function Save-SptUploadedFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey,

        [AllowEmptyString()]
        [string]$RelativePath = '',

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [AllowEmptyString()]
        [string]$UploadRelativePath = '',

        [Parameter(Mandatory = $true)]
        [string]$ContentBase64
    )

    if ($FileName -match '[\\/:*?"<>|]') {
        throw 'File name contains invalid characters.'
    }

    $folderPath = Resolve-SptFileRequestPath -RootKey $RootKey -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        throw 'Upload folder not found.'
    }

    if ([string]::IsNullOrWhiteSpace($UploadRelativePath)) {
        $UploadRelativePath = $FileName
    }

    if ([System.IO.Path]::IsPathRooted($UploadRelativePath)) {
        throw 'Absolute upload paths are not allowed.'
    }

    $segments = @($UploadRelativePath -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments.Count -eq 0) {
        throw 'Upload path is empty.'
    }

    foreach ($segment in $segments) {
        if ($segment -eq '.' -or $segment -eq '..' -or $segment -match '[\\/:*?"<>|]') {
            throw 'Upload path contains invalid characters.'
        }
    }

    $safeUploadRelativePath = $segments[0]
    for ($index = 1; $index -lt $segments.Count; $index++) {
        $safeUploadRelativePath = Join-Path $safeUploadRelativePath $segments[$index]
    }

    $targetRelativePath = $safeUploadRelativePath
    if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
        $targetRelativePath = Join-Path $RelativePath $safeUploadRelativePath
    }
    $targetPath = Resolve-SptManagedPath -RootPath (Get-SptFileRootPath -RootKey $RootKey) -RelativePath $targetRelativePath
    $targetFolder = [System.IO.Path]::GetDirectoryName($targetPath)
    if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    }

    $bytes = [System.Convert]::FromBase64String($ContentBase64)
    [System.IO.File]::WriteAllBytes($targetPath, $bytes)

    $item = Get-Item -LiteralPath $targetPath
    [pscustomobject]@{
        path = ConvertTo-SptRelativePath -RootPath (Get-SptFileRootPath -RootKey $RootKey) -FullPath $targetPath
        size = $item.Length
        modified = $item.LastWriteTime.ToString('s')
    }
}

function Move-SptPathToTrash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TrashRoot,

        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw 'Path not found.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $trashFolder = Join-Path (Join-Path $TrashRoot $RootKey) $timestamp
    New-Item -ItemType Directory -Path $trashFolder -Force | Out-Null
    $targetPath = Join-Path $trashFolder ([System.IO.Path]::GetFileName($SourcePath))
    $suffix = 1
    while (Test-Path -LiteralPath $targetPath) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
        $extension = [System.IO.Path]::GetExtension($SourcePath)
        $targetPath = Join-Path $trashFolder "$name-$suffix$extension"
        $suffix++
    }

    Move-Item -LiteralPath $SourcePath -Destination $targetPath -Force
    return $targetPath
}

function Remove-SptManagedPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sp', 'coop')]
        [string]$RootKey,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$TrashRoot
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'Cannot delete a root folder.'
    }

    $sourcePath = Resolve-SptFileRequestPath -RootKey $RootKey -RelativePath $RelativePath
    Move-SptPathToTrash -SourcePath $sourcePath -TrashRoot $TrashRoot -RootKey $RootKey
}

function Get-SptControlConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        $defaultConfig = [pscustomobject]@{
            port = 8787
            password = '0000'
        }

        $defaultConfig | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
        return $defaultConfig
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    if ($null -eq $config.PSObject.Properties['port']) {
        $config | Add-Member -NotePropertyName port -NotePropertyValue 8787
    }

    if ($null -eq $config.PSObject.Properties['password']) {
        $config | Add-Member -NotePropertyName password -NotePropertyValue '0000'
    }

    return $config
}

function Get-SptControlState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        $state = [pscustomobject]@{
            currentMode = $null
            logSessionActive = $false
            lastAction = 'idle'
            message = 'Ready'
            updatedAt = (Get-Date).ToString('s')
        }
        Save-SptControlState -StatePath $StatePath -State $state
        return $state
    }

    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ($null -eq $state.PSObject.Properties['logSessionActive']) {
        $state | Add-Member -NotePropertyName logSessionActive -NotePropertyValue $false
    }
    return $state
}

function Save-SptControlState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        $State
    )

    $State.updatedAt = (Get-Date).ToString('s')
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Set-SptControlState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [string]$CurrentMode,

        [Parameter(Mandatory = $true)]
        [string]$LastAction,

        [Parameter(Mandatory = $true)]
        [string]$Message
        ,

        [bool]$LogSessionActive
    )

    $state = Get-SptControlState -StatePath $StatePath
    if ($PSBoundParameters.ContainsKey('CurrentMode')) {
        $state.currentMode = $CurrentMode
    }
    if ($PSBoundParameters.ContainsKey('LogSessionActive')) {
        $state.logSessionActive = $LogSessionActive
    }
    $state.lastAction = $LastAction
    $state.message = $Message
    Save-SptControlState -StatePath $StatePath -State $state
    return $state
}

function Get-ServerConfigByMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('single', 'coop')]
        [string]$Mode
    )

    $paths = Get-SptControlPaths
    if ($Mode -eq 'coop') {
        return [pscustomobject]@{
            Mode = 'coop'
            Label = 'Coop'
            Exe = $paths.CoopServerExe
            LogDir = $paths.CoopLogDir
        }
    }

    [pscustomobject]@{
        Mode = 'single'
        Label = 'Single Player'
        Exe = $paths.SingleServerExe
        LogDir = $paths.SingleLogDir
    }
}

function Assert-SptFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file not found: $Path"
    }
}

function Get-SptManagedProcesses {
    $paths = Get-SptControlPaths
    $managedPaths = @(
        $paths.SingleServerExe.ToLowerInvariant(),
        $paths.CoopServerExe.ToLowerInvariant(),
        $paths.HeadlessExe.ToLowerInvariant(),
        $paths.TarkovExe.ToLowerInvariant()
    )

    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'SPT.Server.exe' OR Name = 'FikaHeadlessManager.exe' OR Name = 'EscapeFromTarkov.exe'" -ErrorAction SilentlyContinue)

    foreach ($process in $processes) {
        $exePath = [string]$process.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($exePath) -or $managedPaths -contains $exePath.ToLowerInvariant()) {
            $process
        }
    }
}

function Stop-SptManagedProcesses {
    $processes = @(Get-SptManagedProcesses)
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to stop process $($process.ProcessId): $($_.Exception.Message)"
        }
    }
    Start-Sleep -Milliseconds 600
    return $processes.Count
}

function Stop-SptHeadlessProcesses {
    $paths = Get-SptControlPaths
    $managedPaths = @(
        $paths.HeadlessExe.ToLowerInvariant(),
        $paths.TarkovExe.ToLowerInvariant()
    )
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'FikaHeadlessManager.exe' OR Name = 'EscapeFromTarkov.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $exePath = [string]$_.ExecutablePath
        [string]::IsNullOrWhiteSpace($exePath) -or $managedPaths -contains $exePath.ToLowerInvariant()
    })
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to stop headless/game process $($process.ProcessId): $($_.Exception.Message)"
        }
    }
    Start-Sleep -Milliseconds 600
    return $processes.Count
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutMilliseconds = 500
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $connection.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }

        $client.EndConnect($connection)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Wait-SptServerPort {
    $paths = Get-SptControlPaths
    $deadline = (Get-Date).AddSeconds($paths.StartupTimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -HostName $paths.Host -Port $paths.ServerPort) {
            return $true
        }

        Start-Sleep -Seconds 2
    }

    return $false
}

function Start-SptServer {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('single', 'coop')]
        [string]$Mode
    )

    $server = Get-ServerConfigByMode -Mode $Mode
    Assert-SptFile -Path $server.Exe
    $workingDirectory = [System.IO.Path]::GetDirectoryName($server.Exe)
    Start-Process -FilePath $server.Exe -WorkingDirectory $workingDirectory -PassThru
}

function Start-SptHeadless {
    $paths = Get-SptControlPaths
    Assert-SptFile -Path $paths.HeadlessExe
    $workingDirectory = [System.IO.Path]::GetDirectoryName($paths.HeadlessExe)
    Start-Process -FilePath $paths.HeadlessExe -WorkingDirectory $workingDirectory -PassThru
}

function Start-SptStack {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('single', 'coop')]
        [string]$Mode
    )

    $stopped = Stop-SptManagedProcesses
    $serverProcess = Start-SptServer -Mode $Mode

    if (-not (Wait-SptServerPort)) {
        throw "Timed out waiting for 127.0.0.1:6969 after starting $Mode server."
    }

    $headlessProcess = Start-SptHeadless
    [pscustomobject]@{
        stopped = $stopped
        serverPid = $serverProcess.Id
        headlessPid = $headlessProcess.Id
    }
}

function Restart-SptHeadless {
    $stopped = Stop-SptHeadlessProcesses
    $process = Start-SptHeadless
    [pscustomobject]@{
        stopped = $stopped
        headlessPid = $process.Id
    }
}

function Get-NewestLogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        return $null
    }

    $file = Get-ChildItem -LiteralPath $DirectoryPath -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $file) {
        return $null
    }

    return $file.FullName
}

function Get-LogLineLevel {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Line
    )

    if ($Line -match '(?i)\b(fatal|error|exception|stacktrace|traceback|failed|fail)\b') {
        return 'error'
    }

    if ($Line -match '(?i)\b(warn|warning)\b') {
        return 'warning'
    }

    if ($Line -match '(?i)\b(debug|trace|verbose)\b') {
        return 'debug'
    }

    return 'info'
}

function Get-LogSnapshot {
    param(
        [string]$Path,

        [int]$MaxLines = 500
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            lines = @()
            levels = @()
        }
    }

    $lines = @(Get-Content -LiteralPath $Path -Tail $MaxLines -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
    $levels = @()
    foreach ($line in $lines) {
        $levels += Get-LogLineLevel -Line $line
    }

    [pscustomobject]@{
        lines = @($lines)
        levels = @($levels)
    }
}

function Get-SptStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $state = Get-SptControlState -StatePath $StatePath
    $paths = Get-SptControlPaths
    $processes = @(Get-SptManagedProcesses)
    $serverRunning = @($processes | Where-Object { $_.Name -eq 'SPT.Server.exe' }).Count -gt 0
    $headlessRunning = @($processes | Where-Object { $_.Name -eq 'FikaHeadlessManager.exe' }).Count -gt 0
    $tarkovRunning = @($processes | Where-Object { $_.Name -eq 'EscapeFromTarkov.exe' }).Count -gt 0
    $mode = [string]$state.currentMode
    $serverLogPath = $null

    if (($mode -eq 'single' -or $mode -eq 'coop') -and [bool]$state.logSessionActive) {
        $server = Get-ServerConfigByMode -Mode $mode
        $serverLogPath = Get-NewestLogFile -DirectoryPath $server.LogDir
    }

    [pscustomobject]@{
        currentMode = $state.currentMode
        logSessionActive = [bool]$state.logSessionActive
        lastAction = $state.lastAction
        message = $state.message
        updatedAt = $state.updatedAt
        serverRunning = $serverRunning
        headlessRunning = ($headlessRunning -or $tarkovRunning)
        serverPortOpen = Test-TcpPort -HostName $paths.Host -Port $paths.ServerPort
        serverLogPath = $serverLogPath
        bepinexLogPath = $paths.BepInExLog
    }
}

function Invoke-SptControlAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('launch-single', 'launch-coop', 'restart-all', 'restart-headless', 'stop-all')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $state = Get-SptControlState -StatePath $StatePath

    switch ($Action) {
        'launch-single' {
            Set-SptControlState -StatePath $StatePath -CurrentMode 'single' -LogSessionActive $false -LastAction 'starting' -Message 'Starting single player server and headless...' | Out-Null
            $result = Start-SptStack -Mode 'single'
            Set-SptControlState -StatePath $StatePath -CurrentMode 'single' -LogSessionActive $true -LastAction 'running' -Message 'Single player server and headless are running.' | Out-Null
            return $result
        }
        'launch-coop' {
            Set-SptControlState -StatePath $StatePath -CurrentMode 'coop' -LogSessionActive $false -LastAction 'starting' -Message 'Starting coop server and headless...' | Out-Null
            $result = Start-SptStack -Mode 'coop'
            Set-SptControlState -StatePath $StatePath -CurrentMode 'coop' -LogSessionActive $true -LastAction 'running' -Message 'Coop server and headless are running.' | Out-Null
            return $result
        }
        'restart-all' {
            if ($state.currentMode -ne 'single' -and $state.currentMode -ne 'coop') {
                throw 'No current server mode is selected. Launch single player or coop first.'
            }
            Set-SptControlState -StatePath $StatePath -CurrentMode $state.currentMode -LogSessionActive $false -LastAction 'restarting' -Message "Restarting $($state.currentMode) server and headless..." | Out-Null
            $result = Start-SptStack -Mode $state.currentMode
            Set-SptControlState -StatePath $StatePath -CurrentMode $state.currentMode -LogSessionActive $true -LastAction 'running' -Message "Restarted $($state.currentMode) server and headless." | Out-Null
            return $result
        }
        'restart-headless' {
            Set-SptControlState -StatePath $StatePath -LastAction 'restarting-headless' -Message 'Restarting headless only...' | Out-Null
            $result = Restart-SptHeadless
            Set-SptControlState -StatePath $StatePath -LastAction 'running' -Message 'Headless restarted.' | Out-Null
            return $result
        }
        'stop-all' {
            $stopped = Stop-SptManagedProcesses
            Set-SptControlState -StatePath $StatePath -LogSessionActive $false -LastAction 'stopped' -Message "Stopped $stopped server/headless process(es)." | Out-Null
            return [pscustomobject]@{ stopped = $stopped }
        }
    }
}

Export-ModuleMember -Function *-Spt*, Get-NewestLogFile, Get-LogLineLevel, Get-LogSnapshot, Get-ServerConfigByMode
