param(
    [Parameter(Mandatory=$true)][ValidateSet('buyer','seller')][string]$App,
    [Parameter(Mandatory=$true)][string]$Flutter
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($App -eq 'buyer') { $folder = 'buyer_app'; $port = 55114 }
else { $folder = 'seller_app'; $port = 55115 }
Set-Location (Join-Path $root $folder)
$release = Get-Content -LiteralPath (Join-Path $root 'RELEASE.json') -Raw | ConvertFrom-Json
Write-Host ("Садоход: {0} / {1}+{2} / {3}" -f $App, $release.version, $release.build_number, $release.release_id)
Write-Host 'Подготавливаю Flutter...'
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get завершился ошибкой.' }
Write-Host "Запускаю Chrome на http://localhost:$port ..."
& $Flutter run -d chrome --web-port $port --dart-define=API_BASE_URL=http://localhost:8000
if ($LASTEXITCODE -ne 0) { throw 'Flutter не смог запустить приложение.' }
