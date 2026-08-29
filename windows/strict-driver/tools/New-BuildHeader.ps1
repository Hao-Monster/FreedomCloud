param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{32}$')]
    [string]$BuildId,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$resolvedParent = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::GetDirectoryName($OutputPath)
)
[System.IO.Directory]::CreateDirectory($resolvedParent) | Out-Null

$bytes = for ($index = 0; $index -lt $BuildId.Length; $index += 2) {
    '0x' + $BuildId.Substring($index, 2).ToLowerInvariant()
}
$content = @(
    '#pragma once'
    ''
    '// Generated from the signed package manifest. Do not edit or commit.'
    '#define FCX_STRICT_DRIVER_BUILD_ID_BYTES {' + ($bytes -join ', ') + '}'
    ''
) -join "`r`n"

$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $content,
    $encoding
)
