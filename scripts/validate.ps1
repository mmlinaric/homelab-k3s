$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$renderDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "homelab-k3s-rendered"
New-Item -ItemType Directory -Path $renderDirectory -Force | Out-Null

$targets = @("platform", "apps", "clusters/homelab", "recovery/keycloak", "recovery/keycloak/point-in-time")
foreach ($target in $targets) {
    $outputName = $target.Replace("/", "-") + ".yaml"
    kubectl kustomize (Join-Path $repositoryRoot $target) | Set-Content (Join-Path $renderDirectory $outputName)
    if ($LASTEXITCODE -ne 0) {
        throw "Kustomize rendering failed for $target"
    }
}

if (Get-Command kubeconform -ErrorAction SilentlyContinue) {
    kubeconform -kubernetes-version 1.36.0 -strict -summary -ignore-missing-schemas $renderDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Kubeconform validation failed"
    }
} else {
    Write-Warning "kubeconform is not installed, schema validation was skipped"
}

if (Get-Command yamllint -ErrorAction SilentlyContinue) {
    yamllint -c (Join-Path $repositoryRoot ".yamllint.yaml") $repositoryRoot
    if ($LASTEXITCODE -ne 0) {
        throw "YAML linting failed"
    }
} else {
    Write-Warning "yamllint is not installed, style validation was skipped"
}

$forbiddenCharacter = [char]0x2014
$forbidden = rg -n $forbiddenCharacter $repositoryRoot
if ($LASTEXITCODE -eq 0) {
    throw "An em dash was found:`n$forbidden"
}

Write-Output "Manifest validation completed successfully."
