# IPTV Stream Availability Test Script
# This script reads m3u files, extracts all stream URLs and tests their availability
# It can also remove unavailable streams from the original file

# Parameters
param (
    [string]$InputFile = "index.m3u",
    [string]$OutputFile = "iptv-test-results.txt",
    [int]$Timeout = 5,  # Timeout in seconds
    [int]$MaxStreams = 0,  # Maximum number of streams to test, 0 means test all
    [switch]$RemoveUnavailable = $false,  # Whether to remove unavailable streams
    [string]$CleanOutputFile = ""  # Output file for cleaned m3u (if not specified, will use InputFile-clean.m3u)
)

# Display start information
Write-Host "Starting IPTV stream availability test..." -ForegroundColor Cyan
Write-Host "Input file: $InputFile" -ForegroundColor Cyan
Write-Host "Timeout: $Timeout seconds" -ForegroundColor Cyan

# Check if file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "Error: File not found $InputFile" -ForegroundColor Red
    exit 1
}

# Read M3U file content
$content = Get-Content $InputFile -Encoding UTF8
Write-Host "Read $($content.Count) lines of data" -ForegroundColor Green

# Extract URLs
$urls = @()
$names = @()
$currentName = ""

for ($i = 0; $i -lt $content.Count; $i++) {
    $line = $content[$i]
    
    # Extract channel name
    if ($line -match "#EXTINF:.*,(.*)$") {
        $currentName = $matches[1]
    }
    # Extract URL
    elseif ($line -match "^https?://.*" -or $line -match "^rtmp://.*") {
        $urls += $line
        $names += $currentName
    }
}

Write-Host "Found $($urls.Count) stream URLs" -ForegroundColor Green

# Limit test count
if ($MaxStreams -gt 0 -and $MaxStreams -lt $urls.Count) {
    Write-Host "Will only test the first $MaxStreams streams" -ForegroundColor Yellow
    $urls = $urls[0..($MaxStreams-1)]
    $names = $names[0..($MaxStreams-1)]
}

# Create result file
"IPTV Stream Availability Test Results" | Out-File $OutputFile -Encoding UTF8
"Test Time: $(Get-Date)" | Out-File $OutputFile -Append -Encoding UTF8
"Total Tests: $($urls.Count)" | Out-File $OutputFile -Append -Encoding UTF8
"" | Out-File $OutputFile -Append -Encoding UTF8

# Test result counters
$workingCount = 0
$failedCount = 0
$failedUrls = @()

# Test each URL
for ($i = 0; $i -lt $urls.Count; $i++) {
    $url = $urls[$i]
    $name = $names[$i]
    
    Write-Progress -Activity "Testing Streams" -Status "Testing: $name" -PercentComplete (($i / $urls.Count) * 100)
    
    try {
        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.Timeout = $Timeout * 1000
        
        try {
            $response = $request.GetResponse()
            $statusCode = [int]$response.StatusCode
            $response.Close()
            
            if ($statusCode -ge 200 -and $statusCode -lt 400) {
                $status = "Available"
                $workingCount++
                $failedUrls += $false
                Write-Host "[$($i+1)/$($urls.Count)] $name - Available [$statusCode]" -ForegroundColor Green
            } else {
                $status = "Unavailable (Status Code: $statusCode)"
                $failedCount++
                $failedUrls += $true
                Write-Host "[$($i+1)/$($urls.Count)] $name - Unavailable [$statusCode]" -ForegroundColor Red
            }
        } catch {
            $status = "Unavailable (Error: $($_.Exception.Message))"
            $failedCount++
            $failedUrls += $true
            Write-Host "[$($i+1)/$($urls.Count)] $name - Unavailable (Connection Error)" -ForegroundColor Red
        }
    } catch {
        $status = "Unavailable (Error: $($_.Exception.Message))"
        $failedCount++
        $failedUrls += $true
        Write-Host "[$($i+1)/$($urls.Count)] $name - Unavailable (Request Error)" -ForegroundColor Red
    }
    
    # Write results
    "$($i+1). $name - $status" | Out-File $OutputFile -Append -Encoding UTF8
    $url | Out-File $OutputFile -Append -Encoding UTF8
    "" | Out-File $OutputFile -Append -Encoding UTF8
}

Write-Progress -Activity "Testing Streams" -Completed

# Write statistics
"" | Out-File $OutputFile -Append -Encoding UTF8
"Statistics:" | Out-File $OutputFile -Append -Encoding UTF8
"Available: $workingCount" | Out-File $OutputFile -Append -Encoding UTF8
"Unavailable: $failedCount" | Out-File $OutputFile -Append -Encoding UTF8
"Availability Rate: $([math]::Round(($workingCount / $urls.Count) * 100, 2))%" | Out-File $OutputFile -Append -Encoding UTF8

# If RemoveUnavailable is specified, create a cleaned version of the m3u file
if ($RemoveUnavailable) {
    # Set default clean output file if not specified
    if ([string]::IsNullOrEmpty($CleanOutputFile)) {
        $CleanOutputFile = [System.IO.Path]::GetFileNameWithoutExtension($InputFile) + "-clean.m3u"
    }
    
    Write-Host "Creating cleaned m3u file without unavailable streams..." -ForegroundColor Cyan
    
    # Create a hashtable of unavailable URLs for quick lookup
    $unavailableUrls = @{}
    for ($i = 0; $i -lt $urls.Count; $i++) {
        if ($i -ge $failedUrls.Count) { continue }
        if ($failedUrls[$i]) {
            $unavailableUrls[$urls[$i]] = $true
        }
    }
    
    # Read the original file and write a new one without unavailable streams
    $cleanContent = @()
    $skipNext = $false
    
    foreach ($line in $content) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }
        
        if ($line -match "^https?://.*" -or $line -match "^rtmp://.*") {
            if ($unavailableUrls.ContainsKey($line)) {
                # Remove this URL and its preceding EXTINF line
                $cleanContent = $cleanContent[0..($cleanContent.Count-2)]
                continue
            }
        }
        
        $cleanContent += $line
    }
    
    # Write the cleaned content to file
    $cleanContent | Out-File $CleanOutputFile -Encoding UTF8
    
    Write-Host "Cleaned m3u file saved to: $CleanOutputFile" -ForegroundColor Green
    Write-Host "Removed $failedCount unavailable streams" -ForegroundColor Yellow
}

# Display completion information
Write-Host "`nTest completed!" -ForegroundColor Cyan
Write-Host "Available: $workingCount" -ForegroundColor Green
Write-Host "Unavailable: $failedCount" -ForegroundColor Red
Write-Host "Availability Rate: $([math]::Round(($workingCount / $urls.Count) * 100, 2))%" -ForegroundColor Cyan
Write-Host "Results saved to: $OutputFile" -ForegroundColor Cyan