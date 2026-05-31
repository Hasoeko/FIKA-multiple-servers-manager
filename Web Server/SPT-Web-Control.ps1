Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetDirectoryName($PSCommandPath)
$modulePath = Join-Path $root 'SPT-Web-Control.psm1'
$configPath = Join-Path $root 'config.json'
$statePath = Join-Path $root 'state.json'
$wwwRoot = Join-Path $root 'www'
$trashRoot = Join-Path $root 'Trash'

Import-Module $modulePath -Force

$config = Get-SptControlConfig -ConfigPath $configPath
$startupState = Get-SptControlState -StatePath $statePath
$startupState.logSessionActive = $false
Save-SptControlState -StatePath $statePath -State $startupState

$port = [int]$config.port
$password = [string]$config.password

function ConvertTo-JsonResponse {
    param($Value)

    if ($Value -is [hashtable]) {
        $ordered = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $ordered[$key] = $Value[$key]
        }
        $Value = [pscustomobject]$ordered
    }

    return (ConvertTo-Json -InputObject $Value -Depth 4 -Compress)
}

function Get-MimeType {
    param([string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8' }
        '.css' { 'text/css; charset=utf-8' }
        '.js' { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        default { 'application/octet-stream' }
    }
}

function Read-HttpRequest {
    param([System.Net.Sockets.TcpClient]$Client)

    $stream = $Client.GetStream()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $false, 4096, $true)
    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $parts = $requestLine.Split(' ')
    $headers = @{}

    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') {
            break
        }

        $separator = $line.IndexOf(':')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator).Trim()
            $value = $line.Substring($separator + 1).Trim()
            $headers[$name.ToLowerInvariant()] = $value
        }
    }

    $body = ''
    if ($headers.ContainsKey('content-length')) {
        $length = [int]$headers['content-length']
        if ($length -gt 0) {
            $buffer = New-Object char[] $length
            $read = $reader.ReadBlock($buffer, 0, $length)
            $body = -join $buffer[0..($read - 1)]
        }
    }

    [pscustomobject]@{
        Method = $parts[0]
        Target = $parts[1]
        Headers = $headers
        Body = $body
        Stream = $stream
    }
}

function Write-HttpResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [int]$StatusCode = 200,

        [string]$StatusText = 'OK',

        [string]$ContentType = 'application/json; charset=utf-8',

        [byte[]]$BodyBytes = @()
    )

    $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($BodyBytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($BodyBytes.Length -gt 0) {
        $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
    }
    $Stream.Flush()
}

function Write-Json {
    param(
        [System.IO.Stream]$Stream,
        [int]$StatusCode,
        [string]$StatusText,
        $Value
    )

    $json = ConvertTo-JsonResponse -Value $Value
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Write-HttpResponse -Stream $Stream -StatusCode $StatusCode -StatusText $StatusText -ContentType 'application/json; charset=utf-8' -BodyBytes $bytes
}

function Test-Authorized {
    param($Request)

    if (-not $Request.Headers.ContainsKey('x-spt-password')) {
        return $false
    }

    return $Request.Headers['x-spt-password'] -eq $password
}

function Get-RequestPathAndQuery {
    param([string]$Target)

    $split = $Target.Split('?', 2)
    $path = [System.Uri]::UnescapeDataString($split[0])
    $query = @{}

    if ($split.Count -eq 2) {
        foreach ($pair in $split[1].Split('&')) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }

            $kv = $pair.Split('=', 2)
            $key = [System.Uri]::UnescapeDataString($kv[0])
            $value = ''
            if ($kv.Count -eq 2) {
                $value = [System.Uri]::UnescapeDataString($kv[1])
            }
            $query[$key] = $value
        }
    }

    [pscustomobject]@{
        Path = $path
        Query = $query
    }
}

function Handle-ApiRequest {
    param($Request, $Route)

    if (-not (Test-Authorized -Request $Request)) {
        Write-Json -Stream $Request.Stream -StatusCode 401 -StatusText 'Unauthorized' -Value @{
            ok = $false
            error = 'Invalid password'
        }
        return
    }

    try {
        switch ($Route.Path) {
            '/api/status' {
                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    status = Get-SptStatus -StatePath $statePath
                }
                return
            }
            '/api/action' {
                if ($Request.Method -ne 'POST') {
                    Write-Json -Stream $Request.Stream -StatusCode 405 -StatusText 'Method Not Allowed' -Value @{ ok = $false; error = 'Use POST.' }
                    return
                }

                $body = $Request.Body | ConvertFrom-Json
                $result = Invoke-SptControlAction -Action ([string]$body.action) -StatePath $statePath
                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    result = $result
                    status = Get-SptStatus -StatePath $statePath
                }
                return
            }
            '/api/logs' {
                $type = 'server'
                if ($Route.Query.ContainsKey('type')) {
                    $type = $Route.Query['type']
                }

                $path = $null
                $state = Get-SptControlState -StatePath $statePath
                if ($type -eq 'bepinex') {
                    if ([bool]$state.logSessionActive) {
                        $path = (Get-SptControlPaths).BepInExLog
                    }
                }
                else {
                    if ([bool]$state.logSessionActive -and ($state.currentMode -eq 'single' -or $state.currentMode -eq 'coop')) {
                        $server = Get-ServerConfigByMode -Mode $state.currentMode
                        $path = Get-NewestLogFile -DirectoryPath $server.LogDir
                    }
                }

                $snapshot = Get-LogSnapshot -Path $path -MaxLines 160
                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    type = $type
                    path = $path
                    lines = $snapshot.lines
                    levels = $snapshot.levels
                }
                return
            }
            '/api/files/list' {
                $rootKey = 'sp'
                $path = ''
                if ($Route.Query.ContainsKey('root')) {
                    $rootKey = $Route.Query['root']
                }
                if ($Route.Query.ContainsKey('path')) {
                    $path = $Route.Query['path']
                }

                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    listing = Get-SptDirectoryListing -RootKey $rootKey -RelativePath $path
                }
                return
            }
            '/api/files/read' {
                $rootKey = 'sp'
                $path = ''
                if ($Route.Query.ContainsKey('root')) {
                    $rootKey = $Route.Query['root']
                }
                if ($Route.Query.ContainsKey('path')) {
                    $path = $Route.Query['path']
                }

                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    file = Read-SptTextFile -RootKey $rootKey -RelativePath $path
                }
                return
            }
            '/api/files/save' {
                if ($Request.Method -ne 'POST') {
                    Write-Json -Stream $Request.Stream -StatusCode 405 -StatusText 'Method Not Allowed' -Value @{ ok = $false; error = 'Use POST.' }
                    return
                }

                $body = $Request.Body | ConvertFrom-Json
                $result = Save-SptTextFile -RootKey ([string]$body.root) -RelativePath ([string]$body.path) -Content ([string]$body.content)
                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    file = $result
                }
                return
            }
            '/api/files/upload' {
                if ($Request.Method -ne 'POST') {
                    Write-Json -Stream $Request.Stream -StatusCode 405 -StatusText 'Method Not Allowed' -Value @{ ok = $false; error = 'Use POST.' }
                    return
                }

                $body = $Request.Body | ConvertFrom-Json
                $result = Save-SptUploadedFile -RootKey ([string]$body.root) -RelativePath ([string]$body.path) -FileName ([string]$body.name) -ContentBase64 ([string]$body.contentBase64)
                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    file = $result
                }
                return
            }
            '/api/files/delete' {
                if ($Request.Method -ne 'POST') {
                    Write-Json -Stream $Request.Stream -StatusCode 405 -StatusText 'Method Not Allowed' -Value @{ ok = $false; error = 'Use POST.' }
                    return
                }

                $body = $Request.Body | ConvertFrom-Json
                $trashPath = Remove-SptManagedPath -RootKey ([string]$body.root) -RelativePath ([string]$body.path) -TrashRoot $trashRoot
                Write-Json -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -Value @{
                    ok = $true
                    trashPath = $trashPath
                }
                return
            }
            default {
                Write-Json -Stream $Request.Stream -StatusCode 404 -StatusText 'Not Found' -Value @{ ok = $false; error = 'API route not found.' }
                return
            }
        }
    }
    catch {
        Set-SptControlState -StatePath $statePath -LastAction 'error' -Message $_.Exception.Message | Out-Null
        Write-Json -Stream $Request.Stream -StatusCode 500 -StatusText 'Server Error' -Value @{
            ok = $false
            error = $_.Exception.Message
        }
    }
}

function Handle-StaticRequest {
    param($Request, $Route)

    $relativePath = $Route.Path.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        $relativePath = 'index.html'
    }

    if ($relativePath.Contains('..')) {
        Write-Json -Stream $Request.Stream -StatusCode 400 -StatusText 'Bad Request' -Value @{ ok = $false; error = 'Invalid path.' }
        return
    }

    $filePath = Join-Path $wwwRoot $relativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Write-Json -Stream $Request.Stream -StatusCode 404 -StatusText 'Not Found' -Value @{ ok = $false; error = 'File not found.' }
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    Write-HttpResponse -Stream $Request.Stream -StatusCode 200 -StatusText 'OK' -ContentType (Get-MimeType -Path $filePath) -BodyBytes $bytes
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
$listener.Start()

$addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -ExpandProperty IPAddress)
Write-Host "SPT Web Control listening on port $port"
Write-Host "Local:   http://127.0.0.1:$port/"
foreach ($address in $addresses) {
    Write-Host "Network: http://$address`:$port/"
}
Write-Host 'Press Ctrl+C to stop.'

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $request = Read-HttpRequest -Client $client
            if ($null -eq $request) {
                continue
            }

            $route = Get-RequestPathAndQuery -Target $request.Target
            if ($route.Path.StartsWith('/api/')) {
                Handle-ApiRequest -Request $request -Route $route
            }
            else {
                Handle-StaticRequest -Request $request -Route $route
            }
        }
        catch {
            if ($null -ne $client -and $client.Connected) {
                $stream = $client.GetStream()
                Write-Json -Stream $stream -StatusCode 500 -StatusText 'Server Error' -Value @{ ok = $false; error = $_.Exception.Message }
            }
            Write-Warning $_.Exception.Message
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
