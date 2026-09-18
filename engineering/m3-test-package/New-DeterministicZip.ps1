[CmdletBinding(PositionalBinding = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputZip,

    [Parameter(Mandatory = $true, Position = 2)]
    [long]$SourceDateEpoch,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName 'System.IO.Compression'
Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

function Test-FcxAbsolutePath {
    param([string]$Path)
    # IsPathFullyQualified is unavailable in Windows PowerShell 5.1.
    return (-not [string]::IsNullOrWhiteSpace($Path)) -and
        ($Path -match '^(?:[A-Za-z]:[\\/]|\\\\)')
}

# 1. Validate SourceDateEpoch
if ($SourceDateEpoch -lt 0) {
    throw "SourceDateEpoch must be a nonnegative Unix timestamp in seconds; received '$SourceDateEpoch'"
}

# 2. Validate SourceDirectory
if (-not (Test-FcxAbsolutePath $SourceDirectory)) {
    throw 'SourceDirectory must be an absolute path'
}
if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "SourceDirectory does not exist or is not a directory: '$SourceDirectory'"
}
$sourceItem = Get-Item -LiteralPath $SourceDirectory -Force
if (-not $sourceItem.PSIsContainer) {
    throw "SourceDirectory must be a directory: '$SourceDirectory'"
}
if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "SourceDirectory must not be a reparse point: '$SourceDirectory'"
}
$source = [System.IO.Path]::GetFullPath($SourceDirectory)
$sourcePrefix = if ($source.EndsWith('\')) { $source } else { $source + '\' }

# 3. Validate OutputZip
if (-not (Test-FcxAbsolutePath $OutputZip)) {
    throw 'OutputZip must be an absolute path'
}
if ($OutputZip.EndsWith('\') -or $OutputZip.EndsWith('/')) {
    throw 'OutputZip must be a file path, not a directory'
}
$output = [System.IO.Path]::GetFullPath($OutputZip)
$outputParent = Split-Path -Parent $output
if ([string]::IsNullOrWhiteSpace($outputParent) -or -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    throw "OutputZip parent directory does not exist: '$outputParent'"
}
$outputParentItem = Get-Item -LiteralPath $outputParent -Force
if (($outputParentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "OutputZip parent directory must not be a reparse point: '$outputParent'"
}

# 4. Reject output located inside source
if ($output.Equals($source, [System.StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputZip must not be located inside SourceDirectory: '$output'"
}

# 5. Check destination collision
if (Test-Path -LiteralPath $output) {
    if (-not $Force) {
        throw "OutputZip already exists: '$output'; use -Force to replace it"
    }
    $destItem = Get-Item -LiteralPath $output -Force
    if ($destItem.PSIsContainer) {
        throw "OutputZip destination cannot be an existing directory: '$output'"
    }
    if (($destItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "OutputZip destination must not be a reparse point: '$output'"
    }
}

# 6. Compute fixed UTC ZIP timestamp clamped to 1980 with two second precision
$minEpoch = 315532800L # 1980-01-01 00:00:00 UTC
$effectiveEpoch = if ($SourceDateEpoch -lt $minEpoch) { $minEpoch } else { $SourceDateEpoch }
# Clamp to two-second precision (DOS format resolution)
$effectiveEpoch = $effectiveEpoch - ($effectiveEpoch % 2L)
# Upper bound for DOS date format in ZipArchive (2107-12-31 23:59:58 UTC)
$maxEpoch = 4354819198L
if ($effectiveEpoch -gt $maxEpoch) {
    $effectiveEpoch = $maxEpoch
}
$epochBase = [System.DateTimeOffset]::new(1970, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
$fixedTimestamp = $epochBase.AddSeconds($effectiveEpoch)

# 7. Collect files recursively (including hidden files), rejecting reparse points
$queue = New-Object 'System.Collections.Generic.Queue[string]'
$queue.Enqueue($source)
$entryMap = New-Object 'System.Collections.Generic.Dictionary[string, string]' ([System.StringComparer]::Ordinal)

while ($queue.Count -gt 0) {
    $currentDir = $queue.Dequeue()
    $items = @(Get-ChildItem -LiteralPath $currentDir -Force)
    foreach ($item in $items) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse point detected at '$($item.FullName)'; reparse points are not supported"
        }

        if ($item.PSIsContainer) {
            $queue.Enqueue($item.FullName)
        }
        else {
            $fullPath = $item.FullName
            if (-not $fullPath.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "File '$fullPath' is outside SourceDirectory '$source'"
            }
            $relativePath = $fullPath.Substring($sourcePrefix.Length)
            $entryName = $relativePath.Replace('\', '/').TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($entryName)) {
                throw "Computed empty entry name for '$fullPath'"
            }
            if ($entryMap.ContainsKey($entryName)) {
                throw "Duplicate ZIP entry name detected: '$entryName'"
            }
            $entryMap.Add($entryName, $fullPath)
        }
    }
}

# 8. Sort normalized slash entry names with StringComparer.Ordinal and verify no duplicates
$sortedKeys = [string[]]($entryMap.Keys)
[System.Array]::Sort($sortedKeys, [System.StringComparer]::Ordinal)
for ($i = 1; $i -lt $sortedKeys.Length; $i++) {
    if ([System.StringComparer]::Ordinal.Equals($sortedKeys[$i], $sortedKeys[$i - 1])) {
        throw "Duplicate ZIP entry name detected: '$($sortedKeys[$i])'"
    }
}

# 9. Atomic temporary output in destination parent
$tempZipName = '.deterministic-zip-' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
$tempZipPath = Join-Path $outputParent $tempZipName
$ownedTempZip = $null
$zipStream = $null
$archive = $null

try {
    $zipStream = [System.IO.FileStream]::new(
        $tempZipPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $ownedTempZip = $tempZipPath

    $archive = [System.IO.Compression.ZipArchive]::new(
        $zipStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false
    )

    foreach ($entryName in $sortedKeys) {
        $sourceFile = $entryMap[$entryName]

        # Store entries without compression to avoid runtime compression differences
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::NoCompression)
        $entry.LastWriteTime = $fixedTimestamp
        $entry.ExternalAttributes = 0

        # Stream file bytes directly
        $entryStream = $entry.Open()
        try {
            $fileStream = [System.IO.File]::OpenRead($sourceFile)
            try {
                $fileStream.CopyTo($entryStream)
            }
            finally {
                $fileStream.Dispose()
            }
        }
        finally {
            $entryStream.Dispose()
        }

    }

    $archive.Dispose()
    $archive = $null
    $zipStream.Dispose()
    $zipStream = $null

    Move-Item -LiteralPath $tempZipPath -Destination $output -Force:$Force
    $ownedTempZip = $null
}
finally {
    if ($null -ne $archive) {
        try { $archive.Dispose() } catch {}
    }
    if ($null -ne $zipStream) {
        try { $zipStream.Dispose() } catch {}
    }
    if ($null -ne $ownedTempZip -and (Test-Path -LiteralPath $ownedTempZip)) {
        $candidateName = [System.IO.Path]::GetFileName($ownedTempZip)
        if ($candidateName.StartsWith('.deterministic-zip-', [System.StringComparison]::Ordinal)) {
            try { Remove-Item -LiteralPath $ownedTempZip -Force } catch {}
        }
    }
}

Write-Output $output
