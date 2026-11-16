$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
Write-Host '=== Проверка Садохода ==='
$release = Get-Content -LiteralPath (Join-Path $root 'RELEASE.json') -Raw | ConvertFrom-Json
Write-Host ("Файлы: {0}+{1} / {2}" -f $release.version, $release.build_number, $release.release_id)
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host '[!] Docker не найден'; exit 1 }
& docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) { Write-Host '[!] Docker Desktop не запущен'; exit 1 }
Write-Host '[OK] Docker'
& docker compose ps
try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/health' -UseBasicParsing -TimeoutSec 3
    if ($r.StatusCode -eq 200) {
        $server = $r.Content | ConvertFrom-Json
        Write-Host ("[OK] API: {0}+{1} / {2}" -f $server.version, $server.build_number, $server.release_id)
        if ($server.version -ne $release.version -or $server.build_number -ne $release.build_number -or $server.release_id -ne $release.release_id) {
            Write-Host '[!] Запущенный API отличается от файлов этой папки.'
        }
    } else { Write-Host '[!] Сервер: ошибка' }
} catch { Write-Host '[!] Сервер недоступен' }
foreach ($app in @(@{name='Покупатель';port=55114},@{name='Продавец';port=55115})) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect('127.0.0.1',$app.port,$null,$null)
        if ($result.AsyncWaitHandle.WaitOne(400)) {
            $client.EndConnect($result)
            Write-Host ('[OK] '+$app.name+': http://localhost:'+$app.port)
        } else { Write-Host ('[!] '+$app.name+' не запущен') }
    } catch { Write-Host ('[!] '+$app.name+' не запущен') }
    finally { $client.Close() }
}
Write-Host '--- Последние сообщения сервера ---'
& docker compose logs --tail 25 api
