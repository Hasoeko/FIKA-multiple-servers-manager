Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$portHost = '127.0.0.1'
$port = 6969
$startupTimeoutSeconds = 180

$servers = @(
    [pscustomobject]@{
        Key = '1'
        Name = 'Single player SPT server'
        Path = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\SPT.Server.exe'
    },
    [pscustomobject]@{
        Key = '2'
        Name = 'Coop SPT server'
        Path = 'C:\Games\EscapeFromTarkov\EFT coop\SPT\SPT.Server.exe'
    }
)

$headlessPath = 'C:\Games\EscapeFromTarkov\EscapeFromTarkov\FikaHeadlessManager.exe'

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

function Wait-ForTcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -HostName $HostName -Port $Port) {
            return $true
        }

        Start-Sleep -Seconds 2
    }

    return $false
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file not found: $Path"
    }
}

Write-Host ''
Write-Host 'SPT Launcher'
Write-Host '============'
Write-Host ''

foreach ($server in $servers) {
    Write-Host "$($server.Key). $($server.Name)"
}

Write-Host ''
$choice = Read-Host 'Choose server [1-2]'
$selectedServer = $servers | Where-Object { $_.Key -eq $choice } | Select-Object -First 1

if ($null -eq $selectedServer) {
    throw "Invalid choice: $choice"
}

Assert-FileExists -Path $selectedServer.Path
Assert-FileExists -Path $headlessPath

Write-Host ''
Write-Host "Starting $($selectedServer.Name)..."

$serverWorkingDirectory = [System.IO.Path]::GetDirectoryName($selectedServer.Path)
$serverProcess = Start-Process `
    -FilePath $selectedServer.Path `
    -WorkingDirectory $serverWorkingDirectory `
    -PassThru

Write-Host "Server process started with PID $($serverProcess.Id)."
Write-Host "Waiting for $portHost`:$port to accept connections..."

if (-not (Wait-ForTcpPort -HostName $portHost -Port $port -TimeoutSeconds $startupTimeoutSeconds)) {
    throw "Timed out after $startupTimeoutSeconds seconds waiting for $portHost`:$port."
}

Write-Host "Server is listening on $portHost`:$port."
Write-Host 'Starting Fika Headless Manager...'

$headlessWorkingDirectory = [System.IO.Path]::GetDirectoryName($headlessPath)
$headlessProcess = Start-Process `
    -FilePath $headlessPath `
    -WorkingDirectory $headlessWorkingDirectory `
    -PassThru

Write-Host "Fika Headless Manager started with PID $($headlessProcess.Id)."
Write-Host ''
