$port = 8080
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Ensure uploads directory exists
$uploadsPath = Join-Path $root "uploads"
if (-not (Test-Path $uploadsPath)) {
    New-Item -ItemType Directory -Force $uploadsPath | Out-Null
}

# Ensure JSON database file exists
$dbPath = Join-Path $root "db.json"
if (-not (Test-Path $dbPath)) {
    $defaultDb = @{
        users           = @()
        friend_requests = @()
        messages        = @()
        posts           = @()
    }
    $defaultDb | ConvertTo-Json -Depth 10 | Out-File $dbPath -Encoding utf8
}

function Get-DB {
    try {
        $content = Get-Content $dbPath -Raw -ErrorAction Stop
        return $content | ConvertFrom-Json
    }
    catch {
        return @{ users = @(); friend_requests = @(); messages = @(); posts = @() }
    }
}

function Save-DB($db) {
    $db | ConvertTo-Json -Depth 10 | Out-File $dbPath -Encoding utf8
}

# Get local IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress
if (-not $ip) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   RabtaChat Pro - Persistent Server" -ForegroundColor Cyan  
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PC browser:        http://localhost:$port" -ForegroundColor Green
Write-Host "  Phone 1 browser:   http://${ip}:$port" -ForegroundColor Yellow
Write-Host "  Phone 2 browser:   http://${ip}:$port" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Shareable link for others on your network:" -ForegroundColor Yellow
Write-Host "  http://${ip}:$port" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Dono devices ek hi network/WiFi par hone chahiye!" -ForegroundColor Magenta
Write-Host "  Band karne ke liye: Ctrl+C" -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$mimeTypes = @{
    '.html'  = 'text/html; charset=utf-8'
    '.css'   = 'text/css'
    '.js'    = 'application/javascript'
    '.json'  = 'application/json'
    '.png'   = 'image/png'
    '.jpg'   = 'image/jpeg'
    '.jpeg'  = 'image/jpeg'
    '.gif'   = 'image/gif'
    '.svg'   = 'image/svg+xml'
    '.ico'   = 'image/x-icon'
    '.woff'  = 'font/woff'
    '.woff2' = 'font/woff2'
    '.ttf'   = 'font/ttf'
    '.mp4'   = 'video/mp4'
    '.webm'  = 'video/webm'
    '.mp3'   = 'audio/mpeg'
    '.wav'   = 'audio/wav'
    '.webp'  = 'image/webp'
    '.txt'   = 'text/plain'
}

$tcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
$tcpListener.Start()
Write-Host "Server running on port $port..." -ForegroundColor Green
Write-Host ""

try {
    while ($true) {
        $client = $tcpListener.AcceptTcpClient()
        $stream = $client.GetStream()
        
        # Read the initial bytes (up to 65536 bytes)
        $buffer = New-Object byte[] 65536
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        if ($bytesRead -eq 0) { $stream.Close(); $client.Close(); continue }
        
        $requestText = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
        
        # Split headers and body
        $headerEnd = $requestText.IndexOf("`r`n`r`n")
        if ($headerEnd -lt 0) { $stream.Close(); $client.Close(); continue }
        
        $headersPart = $requestText.Substring(0, $headerEnd)
        $bodyPart = $requestText.Substring($headerEnd + 4)
        
        # Parse first line: METHOD PATH VERSION
        $firstLine = ($headersPart -split "`r`n")[0]
        $parts = $firstLine -split ' '
        $method = if ($parts.Length -ge 1) { $parts[0].ToUpper() } else { 'GET' }
        $urlPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
        
        # Remove query parameters from path
        $queryIndex = $urlPath.IndexOf('?')
        $queryString = ""
        if ($queryIndex -ge 0) {
            $queryString = $urlPath.Substring($queryIndex + 1)
            $urlPath = $urlPath.Substring(0, $queryIndex)
        }
        $urlPath = [System.Uri]::UnescapeDataString($urlPath)
        if ($urlPath -eq '/') { $urlPath = '/index.html' }
        
        # Parse Content-Length header
        $contentLength = 0
        foreach ($line in ($headersPart -split "`r`n")) {
            if ($line.ToLower().StartsWith("content-length:")) {
                $contentLength = [int]($line -replace "(?i)content-length:\s*", "").Trim()
            }
        }
        
        # Read the rest of the body if needed
        $readBodyBytes = [System.Text.Encoding]::UTF8.GetByteCount($bodyPart)
        $bytesRemaining = $contentLength - $readBodyBytes
        
        if ($bytesRemaining -gt 0) {
            $bodyBytesList = New-Object System.Collections.Generic.List[byte]
            $bodyBytesList.AddRange([System.Text.Encoding]::UTF8.GetBytes($bodyPart))
            
            while ($bytesRemaining -gt 0) {
                $chunkSize = [Math]::Min(65536, $bytesRemaining)
                $chunkBuffer = New-Object byte[] $chunkSize
                $chunkRead = $stream.Read($chunkBuffer, 0, $chunkBuffer.Length)
                if ($chunkRead -eq 0) { break }
                $bodyBytesList.AddRange($chunkBuffer[0..($chunkRead - 1)])
                $bytesRemaining -= $chunkRead
            }
            $bodyPart = [System.Text.Encoding]::UTF8.GetString($bodyBytesList.ToArray())
        }

        # Helper to send JSON responses
        function Send-JSON($obj, $status = "200 OK") {
            $json = $obj | ConvertTo-Json -Depth 10
            $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $respHeader = "HTTP/1.1 $status`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($jsonBytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Headers: Content-Type`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::UTF8.GetBytes($respHeader)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($jsonBytes, 0, $jsonBytes.Length)
        }

        # Helper to parse JSON body
        function Get-RequestBodyJson {
            try {
                return $bodyPart | ConvertFrom-Json
            }
            catch {
                return $null
            }
        }

        # CORS preflight
        if ($method -eq 'OPTIONS') {
            $responseHeader = "HTTP/1.1 204 No Content`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($responseHeader)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Close(); $client.Close(); continue
        }

        # API Endpoints
        if ($urlPath.StartsWith('/api/')) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $clientIP = $client.Client.RemoteEndPoint
            Write-Host "[$timestamp] API -> $method $urlPath" -ForegroundColor Magenta

            # SIGNUP
            if ($urlPath -eq '/api/signup' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $userExists = $null
                if ($data.username) {
                    $userExists = $db.users | Where-Object { $_.username -eq $data.username }
                }
                
                if ($userExists) {
                    Send-JSON @{ success = $false; message = "Username already exists!" }
                }
                else {
                    $newUser = @{
                        id       = "usr_" + [Guid]::NewGuid().ToString().Replace("-", "").Substring(0, 12)
                        name     = $data.name
                        username = $data.username
                        password = $data.password
                        country  = $data.country
                        avatar   = if ($data.name) { $data.name.Substring(0, 1).ToUpper() } else { "U" }
                        color    = "linear-gradient(135deg, #6366f1, #ec4899)"
                        bio      = "Hello, I am using RabtaChat Pro!"
                        status   = "online"
                    }
                    $db.users += $newUser
                    Save-DB $db
                    Send-JSON @{ success = $true; user = $newUser }
                }
                $stream.Close(); $client.Close(); continue
            }

            # LOGIN
            if ($urlPath -eq '/api/login' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $user = $db.users | Where-Object { $_.username -eq $data.username }
                if ($user) {
                    if ($user.password -eq $data.password) {
                        $user.status = "online"
                        Save-DB $db
                        Send-JSON @{ success = $true; created = $false; user = $user }
                    }
                    else {
                        Send-JSON @{ success = $false; message = "Incorrect password for this username." }
                    }
                }
                else {
                    $newUser = @{
                        id       = "usr_" + [Guid]::NewGuid().ToString().Replace("-", "").Substring(0, 12)
                        name     = if ($data.name) { $data.name } else { "New User" }
                        username = $data.username
                        password = $data.password
                        country  = if ($data.country) { $data.country } else { "Pakistan" }
                        avatar   = if ($data.name) { $data.name.Substring(0, 1).ToUpper() } else { "U" }
                        color    = "linear-gradient(135deg, #6366f1, #ec4899)"
                        bio      = "Hello, I am using RabtaChat Pro!"
                        status   = "online"
                    }
                    $db.users += $newUser
                    Save-DB $db
                    Send-JSON @{ success = $true; created = $true; user = $newUser }
                }
                $stream.Close(); $client.Close(); continue
            }

            # FRIEND REQUEST
            if ($urlPath -eq '/api/friends/request' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $exists = $db.friend_requests | Where-Object { 
                    ($_.sender -eq $data.sender -and $_.receiver -eq $data.receiver) -or 
                    ($_.sender -eq $data.receiver -and $_.receiver -eq $data.sender)
                }
                
                if (-not $exists) {
                    $req = @{
                        id       = "req_" + [Guid]::NewGuid().ToString().Replace("-", "").Substring(0, 12)
                        sender   = $data.sender
                        receiver = $data.receiver
                        status   = "pending"
                    }
                    $db.friend_requests += $req
                    Save-DB $db
                }
                Send-JSON @{ success = $true }
                $stream.Close(); $client.Close(); continue
            }

            # ACCEPT FRIEND
            if ($urlPath -eq '/api/friends/accept' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $req = $db.friend_requests | Where-Object { 
                    $_.sender -eq $data.sender -and $_.receiver -eq $data.receiver -and $_.status -eq 'pending'
                }
                
                if ($req) {
                    $req.status = "accepted"
                    Save-DB $db
                    Send-JSON @{ success = $true }
                }
                else {
                    Send-JSON @{ success = $false; message = "Request not found." }
                }
                $stream.Close(); $client.Close(); continue
            }

            # SYNC
            if ($urlPath -eq '/api/sync' -and $method -eq 'GET') {
                $targetUsername = ""
                if ($queryString) {
                    foreach ($param in ($queryString -split '&')) {
                        $pair = $param -split '='
                        if ($pair[0] -eq 'username' -and $pair.Length -gt 1) {
                            $targetUsername = [System.Uri]::UnescapeDataString($pair[1])
                        }
                    }
                }
                
                $db = Get-DB
                $myRequests = $db.friend_requests | Where-Object { $_.sender -eq $targetUsername -or $_.receiver -eq $targetUsername }
                
                $allUsers = $db.users | ForEach-Object {
                    @{
                        name     = $_.name
                        username = $_.username
                        avatar   = $_.avatar
                        color    = $_.color
                        bio      = $_.bio
                        status   = $_.status
                        country  = $_.country
                    }
                }
                
                $myMessages = $db.messages | Where-Object { $_.sender -eq $targetUsername -or $_.receiver -eq $targetUsername }
                $allReels = $db.posts
                
                Send-JSON @{
                    success        = $true
                    users          = $allUsers
                    friendRequests = $myRequests
                    messages       = $myMessages
                    reels          = $allReels
                }
                $stream.Close(); $client.Close(); continue
            }

            # SEND MESSAGE
            if ($urlPath -eq '/api/messages/send' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $msg = @{
                    id              = "msg_" + [Guid]::NewGuid().ToString().Replace("-", "").Substring(0, 12)
                    sender          = $data.sender
                    receiver        = $data.receiver
                    text            = $data.text
                    type            = if ($data.type) { $data.type } else { 'text' }
                    fileUrl         = $data.fileUrl
                    voiceTranscript = $data.voiceTranscript
                    timestamp       = (Get-Date).ToString("o")
                }
                $db.messages += $msg
                Save-DB $db
                
                Send-JSON @{ success = $true; message = $msg }
                $stream.Close(); $client.Close(); continue
            }

            # DELETE MESSAGE(S)
            if ($urlPath -eq '/api/messages/delete' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $idsToDelete = @()
                if ($data.id) {
                    $idsToDelete += $data.id
                }
                if ($data.ids) {
                    $idsToDelete += $data.ids
                }
                
                if ($idsToDelete.Count -gt 0) {
                    $db.messages = $db.messages | Where-Object { $idsToDelete -notcontains $_.id }
                    Save-DB $db
                    Send-JSON @{ success = $true }
                }
                else {
                    Send-JSON @{ success = $false; message = "No message ID provided." }
                }
                $stream.Close(); $client.Close(); continue
            }

            # CLEAR ALL MESSAGES (CLEAR CHAT)
            if ($urlPath -eq '/api/messages/clear' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                if ($data.sender -and $data.receiver) {
                    $sender = $data.sender.Replace("@", "").ToLower()
                    $receiver = $data.receiver.Replace("@", "").ToLower()
                    
                    $db.messages = $db.messages | Where-Object { 
                        -not (($_.sender.ToLower() -eq $sender -and $_.receiver.ToLower() -eq $receiver) -or 
                              ($_.sender.ToLower() -eq $receiver -and $_.receiver.ToLower() -eq $sender))
                    }
                    Save-DB $db
                    Send-JSON @{ success = $true }
                }
                else {
                    Send-JSON @{ success = $false; message = "Sender and receiver required." }
                }
                $stream.Close(); $client.Close(); continue
            }

            # DELETE FRIEND (AND THEIR MESSAGES)
            if ($urlPath -eq '/api/friends/delete' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                if ($data.sender -and $data.receiver) {
                    $sender = $data.sender.Replace("@", "").ToLower()
                    $receiver = $data.receiver.Replace("@", "").ToLower()
                    
                    $db.friend_requests = $db.friend_requests | Where-Object { 
                        -not (($_.sender.ToLower() -eq $sender -and $_.receiver.ToLower() -eq $receiver) -or 
                              ($_.sender.ToLower() -eq $receiver -and $_.receiver.ToLower() -eq $sender))
                    }
                    
                    $db.messages = $db.messages | Where-Object { 
                        -not (($_.sender.ToLower() -eq $sender -and $_.receiver.ToLower() -eq $receiver) -or 
                              ($_.sender.ToLower() -eq $receiver -and $_.receiver.ToLower() -eq $sender))
                    }
                    Save-DB $db
                    Send-JSON @{ success = $true }
                }
                else {
                    Send-JSON @{ success = $false; message = "Sender and receiver required." }
                }
                $stream.Close(); $client.Close(); continue
            }

            # CREATE POST
            if ($urlPath -eq '/api/posts/create' -and $method -eq 'POST') {
                $data = Get-RequestBodyJson
                $db = Get-DB
                
                $videoUrl = ""
                if ($data.videoBase64) {
                    $base64 = $data.videoBase64
                    $metaEnd = $base64.IndexOf("base64,")
                    if ($metaEnd -ge 0) {
                        $base64 = $base64.Substring($metaEnd + 7)
                    }
                    
                    $bytes = [System.Convert]::FromBase64String($base64)
                    $fileName = "reel_" + (Get-Date -UFormat "%Y%m%d_%H%M%S") + "_" + [Guid]::NewGuid().ToString().Substring(0, 6) + ".webm"
                    $filePath = Join-Path $root "uploads\$fileName"
                    [System.IO.File]::WriteAllBytes($filePath, $bytes)
                    
                    $videoUrl = "/uploads/" + $fileName
                }
                
                $newReel = @{
                    id        = "reel_" + [Guid]::NewGuid().ToString().Replace("-", "").Substring(0, 12)
                    user      = @{
                        name     = $data.name
                        username = $data.username
                        initials = $data.initials
                        color    = $data.color
                    }
                    url       = $videoUrl
                    desc      = $data.desc
                    filter    = if ($data.filter) { $data.filter } else { 'none' }
                    music     = $data.music
                    location  = $data.location
                    likes     = 0
                    liked     = $false
                    comments  = @()
                    timestamp = (Get-Date).ToString("o")
                }
                
                $db.posts += $newReel
                Save-DB $db
                Send-JSON @{ success = $true; post = $newReel }
                $stream.Close(); $client.Close(); continue
            }

            # Generic 404 for unknown API
            Send-JSON @{ success = $false; message = "API endpoint not found" } "404 Not Found"
            $stream.Close(); $client.Close(); continue
        }

        # Serve static files
        $filePath = Join-Path $root ($urlPath.TrimStart('/').Replace('/', '\'))
        $timestamp = Get-Date -Format "HH:mm:ss"
        $clientIP = $client.Client.RemoteEndPoint

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { 'application/octet-stream' }
            
            $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
            $responseHeader = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($fileBytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($responseHeader)
            
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($fileBytes, 0, $fileBytes.Length)
            
            Write-Host "[$timestamp] $clientIP -> $urlPath" -ForegroundColor DarkGray
        }
        else {
            $body = "<h1>404 - Not Found</h1>"
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $responseHeader = "HTTP/1.1 404 Not Found`r`nContent-Type: text/html`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($responseHeader)
            
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
            
            Write-Host "[$timestamp] 404: $urlPath" -ForegroundColor Red
        }
        
        $stream.Close()
        $client.Close()
    }
}
finally {
    $tcpListener.Stop()
    Write-Host "Server stopped." -ForegroundColor Red
}
