<#
  ВОРОТА (gate): одна команда, один вердикт.

  Запуск из корня проекта:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\gate.ps1

  Параметры:
    -Quick          не собирать flutter build web (быстрее, но прогон считается частичным)
    -SkipServer     пропустить серверные тесты в Docker
    -SkipFlutter    пропустить проверки Flutter
    -StrictAnalyze  flutter analyze падает и на info-замечаниях
                    (по умолчанию падает только на warning и error)

  Код возврата:
    0  всё зелёное, ни одна проверка не пропущена
    1  есть упавшие проверки
    2  упавших нет, но часть проверок пропущена (прогон частичный)

  Скрипт ничего не удаляет и не трогает базу приложения: серверные тесты идут
  в отдельном Compose-проекте sadohod_isolated_qa на временной базе в памяти.
  Полные логи каждой проверки лежат в gate-logs\<дата-время>\.
#>
param(
    [switch]$Quick,
    [switch]$SkipServer,
    [switch]$SkipFlutter,
    [switch]$StrictAnalyze
)

# Коды возврата проверяем сами через $LASTEXITCODE, поэтому Continue, а не Stop.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $root (Join-Path 'gate-logs' $stamp)
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$results = New-Object System.Collections.ArrayList
$script:step = 0
$gateWatch = [Diagnostics.Stopwatch]::StartNew()

function Add-Result([string]$Name, [string]$Status, [double]$Seconds, [string]$Note) {
    [void]$results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Seconds = $Seconds; Note = $Note })
}

function Skip-Step([string]$Name, [string]$Reason) {
    Write-Host ''
    Write-Host ('--- ' + $Name + ' ---') -ForegroundColor Cyan
    Write-Host ('    ПРОПУЩЕНО: ' + $Reason) -ForegroundColor Yellow
    Add-Result $Name 'SKIP' 0 $Reason
}

function Fail-Step([string]$Name, [string]$Reason) {
    Write-Host ''
    Write-Host ('--- ' + $Name + ' ---') -ForegroundColor Cyan
    Write-Host ('    НЕ ЗАПУЩЕНО: ' + $Reason) -ForegroundColor Red
    Add-Result $Name 'FAIL' 0 $Reason
}

function Test-Tool([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Запускает команду через cmd.exe: так одинаково работают .bat-обёртки (flutter.bat),
# а stderr сливается с stdout внутри cmd и не превращается в красные ошибки PowerShell.
# Возвращает $true, если код возврата равен 0.
function Invoke-Step([string]$Name, [string]$WorkDir, [string]$CommandLine) {
    $script:step++
    $safe = $Name -replace '[^A-Za-z0-9._-]', '_'
    $log = Join-Path $logDir ('{0:00}-{1}.log' -f $script:step, $safe)
    Write-Host ''
    Write-Host ('--- ' + $Name + ' ---') -ForegroundColor Cyan
    Write-Host ('    ' + $CommandLine)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $code = $null
    Push-Location $WorkDir
    try {
        & cmd.exe /d /c ('chcp 65001 >nul & ' + $CommandLine + ' 2>&1') | ForEach-Object {
            Write-Host $_
            Add-Content -LiteralPath $log -Value $_ -Encoding UTF8
        }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $watch.Stop()
    $seconds = [math]::Round($watch.Elapsed.TotalSeconds)
    if ($code -eq 0) {
        Write-Host ('    ЗЕЛЁНЫЙ  (' + $seconds + ' c)') -ForegroundColor Green
        Add-Result $Name 'PASS' $seconds ''
        return $true
    }
    Write-Host ('    КРАСНЫЙ, код ' + $code + '  (' + $seconds + ' c). Конец вывода:') -ForegroundColor Red
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 15 | ForEach-Object { Write-Host ('    | ' + $_) } }
    Add-Result $Name 'FAIL' $seconds ('код ' + $code + ', лог: ' + $log)
    return $false
}

Write-Host '=== САДОХОД: ворота ===' -ForegroundColor Cyan
Write-Host ('Папка: ' + $root)
Write-Host ('Логи:  ' + $logDir)

# 1. Версии: RELEASE.json, Python/Dart/JS-константы и pubspec должны совпадать.
$python = $null
foreach ($candidate in @('python', 'py')) {
    if (Test-Tool $candidate) { $python = $candidate; break }
}
if ($python) {
    [void](Invoke-Step 'versions' $root ($python + ' tools/sync_version.py --check'))
} else {
    Fail-Step 'versions' 'Python не найден в PATH'
}

# 2. Сервер: набор на SQLite, затем PostgreSQL 17 + pgvector, всё в изолированном QA-проекте.
if ($SkipServer) {
    Skip-Step 'server-tests' 'указан -SkipServer'
} elseif (-not (Test-Tool 'docker')) {
    Fail-Step 'server-tests' 'docker не найден в PATH'
} else {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail-Step 'server-tests' 'Docker Desktop не запущен'
    } else {
        [void](Invoke-Step 'server-tests' $root 'docker compose -p sadohod_isolated_qa -f tools/compose.qa.yml up --build --abort-on-container-exit --exit-code-from tests')
        # Убираем только контейнеры QA-проекта; тома и база приложения не затрагиваются.
        & docker compose -p sadohod_isolated_qa -f tools/compose.qa.yml down *> $null
    }
}

# 3. Flutter: оба клиента по очереди.
if ($SkipFlutter) {
    Skip-Step 'flutter' 'указан -SkipFlutter'
} elseif (-not (Test-Tool 'flutter')) {
    Fail-Step 'flutter' 'flutter не найден в PATH'
} else {
    $analyze = 'flutter analyze'
    if (-not $StrictAnalyze) { $analyze += ' --no-fatal-infos' }
    foreach ($app in @('seller_app', 'buyer_app')) {
        $dir = Join-Path $root $app
        if (-not (Invoke-Step ($app + '-pub-get') $dir 'flutter pub get')) {
            foreach ($blocked in @('analyze', 'test', 'build-web')) {
                Add-Result ($app + '-' + $blocked) 'FAIL' 0 'не запускалось: pub get не прошёл'
            }
            continue
        }
        [void](Invoke-Step ($app + '-analyze') $dir $analyze)
        [void](Invoke-Step ($app + '-test') $dir 'flutter test')
        if ($Quick) {
            Skip-Step ($app + '-build-web') 'указан -Quick'
        } else {
            [void](Invoke-Step ($app + '-build-web') $dir 'flutter build web --dart-define=API_BASE_URL=http://localhost:8000')
        }
    }
}

# Итог.
$gateWatch.Stop()
Write-Host ''
Write-Host '=== ИТОГ ===' -ForegroundColor Cyan
$lines = @()
foreach ($r in $results) {
    $line = '{0,-5} {1,-26} {2,5} c  {3}' -f $r.Status, $r.Name, $r.Seconds, $r.Note
    $lines += $line
    $color = 'Green'
    if ($r.Status -eq 'FAIL') { $color = 'Red' }
    if ($r.Status -eq 'SKIP') { $color = 'Yellow' }
    Write-Host $line -ForegroundColor $color
}
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$skipped = @($results | Where-Object { $_.Status -eq 'SKIP' }).Count
$exitCode = 0
$verdict = 'ВСЁ ЗЕЛЁНОЕ: задачу можно считать законченной.'
if ($failed -gt 0) {
    $exitCode = 1
    $verdict = 'КРАСНЫЙ: упало проверок: ' + $failed + '. Задача не закончена.'
} elseif ($skipped -gt 0) {
    $exitCode = 2
    $verdict = 'ЧАСТИЧНЫЙ ПРОГОН: пропущено проверок: ' + $skipped + '. Это ещё не зелёный.'
}
$color = 'Green'
if ($exitCode -eq 1) { $color = 'Red' }
if ($exitCode -eq 2) { $color = 'Yellow' }
Write-Host ''
Write-Host $verdict -ForegroundColor $color
Write-Host ('Всего: ' + [math]::Round($gateWatch.Elapsed.TotalSeconds) + ' c. Логи: ' + $logDir)
$lines + '' + $verdict | Set-Content -LiteralPath (Join-Path $logDir 'summary.txt') -Encoding UTF8
exit $exitCode
