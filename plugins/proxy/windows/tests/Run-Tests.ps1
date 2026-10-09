param(
    [ValidateSet('Regression', 'NativeCompile')]
    [string]$Mode = 'Regression',
    [string]$MsvcRoot = 'C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Tools\MSVC\14.44.35207',
    [string]$WindowsSdkRoot = 'C:\Program Files (x86)\Windows Kits\10',
    [string]$WindowsSdkVersion = '10.0.26100.0'
)
$ErrorActionPreference = 'Stop'
$sourceName = switch ($Mode) {
    'Regression' { 'proxy_settings_test.cpp' }
    'NativeCompile' { '..\proxy_plugin.cpp' }
}
$buildDirectory = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
$logPath = Join-Path $buildDirectory ($Mode + '.log')
$testStopwatch = [Diagnostics.Stopwatch]::StartNew()
$compiler = Join-Path $MsvcRoot 'bin\Hostx64\x64\cl.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw "MSVC not found: $compiler" }
$includeDirectories = @(
    (Join-Path $MsvcRoot 'include'),
    (Join-Path $WindowsSdkRoot "Include\$WindowsSdkVersion\ucrt"),
    (Join-Path $WindowsSdkRoot "Include\$WindowsSdkVersion\shared"),
    (Join-Path $WindowsSdkRoot "Include\$WindowsSdkVersion\um")
)
$libraryDirectories = @(
    (Join-Path $MsvcRoot 'lib\x64'),
    (Join-Path $WindowsSdkRoot "Lib\$WindowsSdkVersion\ucrt\x64"),
    (Join-Path $WindowsSdkRoot "Lib\$WindowsSdkVersion\um\x64")
)
foreach ($toolchainDirectory in ($includeDirectories + $libraryDirectories)) {
    if (!(Test-Path -LiteralPath $toolchainDirectory)) {
        throw "Toolchain directory missing: $toolchainDirectory"
    }
}
$env:INCLUDE = $includeDirectories -join ';'
$env:LIB = $libraryDirectories -join ';'
$source = Join-Path $PSScriptRoot $sourceName
$executable = Join-Path $buildDirectory ($Mode + '.exe')
$object = Join-Path $buildDirectory ($Mode + '.obj')
if ($Mode -eq 'NativeCompile') {
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
    $flutterDirectory = Join-Path $repositoryRoot 'windows\flutter\ephemeral'
    $wrapperInclude = Join-Path $flutterDirectory 'cpp_client_wrapper\include'
    & $compiler /nologo /c /std:c++17 /EHsc /W4 /WX /wd4100 /D_HAS_EXCEPTIONS=0 `
        /DFLUTTER_PLUGIN_IMPL /DUNICODE /D_UNICODE `
        /D_SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING `
        "/I$flutterDirectory" "/I$wrapperInclude" "/Fo$object" $source 2>&1 |
        Tee-Object -FilePath $logPath
    $compileExitCode = $LASTEXITCODE
    "COMPILER_EXIT=$compileExitCode ELAPSED_MS=$($testStopwatch.ElapsedMilliseconds)" |
        Tee-Object -FilePath $logPath -Append
    exit $compileExitCode
}
& $compiler /nologo /std:c++17 /EHsc /W4 /WX /D_HAS_EXCEPTIONS=0 "/Fo$object" "/Fe$executable" $source wininet.lib rasapi32.lib 2>&1 |
    Tee-Object -FilePath $logPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $executable 2>&1 | Tee-Object -FilePath $logPath -Append
$testExitCode = $LASTEXITCODE
"TEST_PROCESS_EXIT=$testExitCode ELAPSED_MS=$($testStopwatch.ElapsedMilliseconds)" |
    Tee-Object -FilePath $logPath -Append
exit $testExitCode
