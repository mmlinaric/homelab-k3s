param(
    [string]$RenderedManifest
)

$ErrorActionPreference = "Stop"

if ($RenderedManifest) {
    $rendered = Get-Content -LiteralPath $RenderedManifest -Raw
} else {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $rendered = (kubectl kustomize (Join-Path $repositoryRoot "platform")) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "Kustomize rendering failed for platform"
    }
}

$documents = [regex]::Split($rendered, "(?m)^---\s*$")

function Get-ResourceDocument {
    param(
        [string]$Kind,
        [string]$Name
    )

    $matches = @($documents | Where-Object {
        $_ -match "(?m)^kind: $([regex]::Escape($Kind))\s*$" -and
        $_ -match "(?m)^  name: $([regex]::Escape($Name))\s*$"
    })

    if ($matches.Count -ne 1) {
        throw "Expected exactly one $Kind/$Name in the rendered platform manifest, found $($matches.Count)"
    }

    return $matches[0]
}

function Assert-Match {
    param(
        [string]$Document,
        [string]$Pattern,
        [string]$Description
    )

    if ($Document -notmatch $Pattern) {
        throw "Longhorn authentication validation failed: $Description"
    }
}

$ingress = Get-ResourceDocument -Kind "IngressRoute" -Name "longhorn-lan"
$oauthRoutePattern = '(?ms)^  - kind: Rule\s+match: Host\(`longhorn\.mmlinaric\.com`\) && PathPrefix\(`/oauth2/`\)\s+middlewares:\s+- name: longhorn-lan-only\s+priority: 20\s+services:\s+- name: longhorn-oauth2-proxy\s+port: 4180\s*$'
$frontendRoutePattern = '(?ms)^  - kind: Rule\s+match: Host\(`longhorn\.mmlinaric\.com`\)\s+middlewares:\s+- name: longhorn-lan-only\s+- name: longhorn-forward-auth\s+priority: 10\s+services:\s+- name: longhorn-frontend\s+port: 80\s*$'
Assert-Match -Document $ingress -Pattern $oauthRoutePattern -Description "the OAuth callback route must be LAN-only and terminate at OAuth2 Proxy"
Assert-Match -Document $ingress -Pattern $frontendRoutePattern -Description "the only Longhorn frontend route must apply both LAN and ForwardAuth middleware"
if ([regex]::Matches($ingress, '(?m)^\s+- name: longhorn-frontend\s*$').Count -ne 1) {
    throw "Longhorn authentication validation failed: expected exactly one route to longhorn-frontend"
}

$lanOnly = Get-ResourceDocument -Kind "Middleware" -Name "longhorn-lan-only"
Assert-Match -Document $lanOnly -Pattern '(?m)^\s+- 192\.168\.88\.0/24\s*$' -Description "the source restriction must allow only the administrator LAN"

$forwardAuth = Get-ResourceDocument -Kind "Middleware" -Name "longhorn-forward-auth"
Assert-Match -Document $forwardAuth -Pattern '(?m)^    address: http://longhorn-oauth2-proxy\.longhorn-system\.svc\.cluster\.local:4180/\s*$' -Description "ForwardAuth must use the in-cluster OAuth2 Proxy"

$deployment = Get-ResourceDocument -Kind "Deployment" -Name "longhorn-oauth2-proxy"
Assert-Match -Document $deployment -Pattern '(?m)^\s+- --allowed-role=longhorn:admin\s*$' -Description "OAuth2 Proxy must require the Longhorn administrator role"
Assert-Match -Document $deployment -Pattern '(?m)^\s+- --code-challenge-method=S256\s*$' -Description "the OIDC authorization flow must require PKCE S256"
Assert-Match -Document $deployment -Pattern '(?m)^\s+- --trusted-proxy-ip=10\.42\.0\.0/16\s*$' -Description "OAuth2 Proxy must reject forwarded headers from outside the pod network"

$networkPolicy = Get-ResourceDocument -Kind "NetworkPolicy" -Name "longhorn-oauth2-proxy"
Assert-Match -Document $networkPolicy -Pattern '(?ms)namespaceSelector:\s+matchLabels:\s+kubernetes\.io/metadata\.name: traefik' -Description "only Traefik may connect to OAuth2 Proxy"

$externalSecret = Get-ResourceDocument -Kind "ExternalSecret" -Name "longhorn-oauth2-proxy"
Assert-Match -Document $externalSecret -Pattern "(?m)^\s+cookie-secret: '\{\{ \.cookieSecret \| b64dec \}\}'\s*$" -Description "the Base64 cookie secret must be decoded before mounting"

Write-Output "Longhorn authentication boundary validation completed successfully."
