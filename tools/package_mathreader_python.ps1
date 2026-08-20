# Package python/mathreader_app for Serious Python.
# Usage (from repo root):
#   .\tools\package_mathreader_python.ps1 Android
#   .\tools\package_mathreader_python.ps1 Windows
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Android", "iOS", "Darwin", "Windows", "Linux")]
    [string]$Platform
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$env:SERIOUS_PYTHON_VERSION = "3.12"
$env:SERIOUS_PYTHON_SITE_PACKAGES = Join-Path $root "build\site-packages"
$env:SERIOUS_PYTHON_APP = Join-Path $root "build\python-app"
$env:SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES = "mathreader"
$env:SERIOUS_PYTHON_BUNDLE_ID = "dev.changkevin.scrapyard"
# Mobile pip is --only-binary :all:; allow sdists for these pure-Python packages.
$env:SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS = "imutils,ply,idx2numpy"

New-Item -ItemType Directory -Force -Path $env:SERIOUS_PYTHON_SITE_PACKAGES | Out-Null
New-Item -ItemType Directory -Force -Path $env:SERIOUS_PYTHON_APP | Out-Null

$req = if ($Platform -eq "Android" -or $Platform -eq "iOS") {
    "python\mathreader_app\requirements-mobile.txt"
} else {
    "python\mathreader_app\requirements-desktop.txt"
}

Write-Host "Packaging MathReader sidecar for $Platform (Python $($env:SERIOUS_PYTHON_VERSION))"
dart run serious_python:main package python/mathreader_app -p $Platform `
    -r -r -r $req `
    -r --no-deps -r mathreader==0.163
if ($LASTEXITCODE -ne 0) {
    throw "serious_python package failed with exit code $LASTEXITCODE"
}

# Drop the unused Keras .h5 / training dumps so the bundle stays TFLite-only.
Get-ChildItem -Path $env:SERIOUS_PYTHON_SITE_PACKAGES -Recurse -Include *.h5,*.npz -ErrorAction SilentlyContinue |
    Remove-Item -Force
Get-ChildItem -Path $env:SERIOUS_PYTHON_APP -Recurse -Include *.h5,*.npz -ErrorAction SilentlyContinue |
    Remove-Item -Force

Write-Host "Done. SERIOUS_PYTHON_APP=$($env:SERIOUS_PYTHON_APP)"
