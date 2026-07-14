param(
    [string]$BuildRoot = "build"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $repoRoot $BuildRoot
$stagingRoot = Join-Path $buildPath "staging"

if (Test-Path $buildPath) {
    Remove-Item -Path $buildPath -Recurse -Force
}

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

function New-LambdaPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionFolder,

        [Parameter(Mandatory = $true)]
        [string]$ZipName
    )

    $packageRoot = Join-Path $stagingRoot $ZipName
    $lambdaPackageRoot = Join-Path $packageRoot "lambdas"
    $targetFunctionRoot = Join-Path $lambdaPackageRoot $FunctionFolder
    $targetSharedRoot = Join-Path $lambdaPackageRoot "shared"

    New-Item -ItemType Directory -Path $targetFunctionRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $targetSharedRoot -Force | Out-Null

    Copy-Item -Path (Join-Path $repoRoot "lambdas\__init__.py") -Destination $lambdaPackageRoot -Force
    Copy-Item -Path (Join-Path $repoRoot "lambdas\$FunctionFolder\*") -Destination $targetFunctionRoot -Recurse -Force
    Copy-Item -Path (Join-Path $repoRoot "lambdas\shared\*") -Destination $targetSharedRoot -Recurse -Force

    $zipPath = Join-Path $buildPath $ZipName
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
}

New-LambdaPackage -FunctionFolder "StartTranscription" -ZipName "start_transcription.zip"
New-LambdaPackage -FunctionFolder "ProcessTranscript" -ZipName "process_transcript.zip"

Write-Host "Created Lambda packages in $buildPath"