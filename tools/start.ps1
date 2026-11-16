param([Parameter(Mandatory=$true)][ValidateSet('First','Update')][string]$Mode)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
$projectName = 'sadohod_mvp_v0_2'
$volumeNames = @{
    db = 'sadohod_mvp_v0_2_sadohod_pg'
    photos = 'sadohod_mvp_v0_2_sadohod_uploads'
    state = 'sadohod_mvp_v0_2_sadohod_admin_state'
}
function Say([string]$s) { Write-Host $s }
function Fail([string]$reason) { throw $reason }
function DockerRun([string[]]$arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $res = @(& docker @arguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw ('Docker: ' + (($res | Out-String).Trim())) }
    return $res
}
function ContainerId([string]$service) {
    $ids = @(@(& docker ps -aq --filter "label=com.docker.compose.project=$projectName" --filter "label=com.docker.compose.service=$service") | Where-Object { $_ -and $_.Trim() })
    if ($LASTEXITCODE -ne 0) { Fail 'Не удалось получить список контейнеров Docker.' }
    if ($ids.Count -gt 1) { Fail "Найдено несколько контейнеров '$service'. Требуется ручная проверка." }
    if ($ids.Count -eq 0) { return '' }
    return $ids[0].Trim()
}
function DockerEnvironment([string]$containerId) {
    $result = @{}
    if (-not $containerId) { return $result }
    $json = & docker inspect --format '{{json .Config.Env}}' $containerId 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $result }
    foreach ($kv in ($json | ConvertFrom-Json)) {
        $pos = $kv.IndexOf('=')
        if ($pos -gt 0) { $result[$kv.Substring(0, $pos)] = $kv.Substring($pos + 1) }
    }
    return $result
}
function QuoteDotEnv([string]$value) {
    if ($value.Contains("`n") -or $value.Contains("`r")) { Fail 'В конфигурации есть многострочное значение. Нужна ручная проверка настроек.' }
    return "'" + $value.Replace("'", "\'") + "'"
}
function WaitForDb([string]$id) {
    for ($i=0; $i -lt 40; $i++) {
        & docker exec $id pg_isready -U sadohod -d sadohod *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    Fail 'PostgreSQL пока недоступен. Данные не изменены.'
}
function WaitForApi() {
    for ($i=0; $i -lt 30; $i++) {
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/health' -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200) { return }
        } catch {}
        Start-Sleep -Seconds 2
    }
    Fail 'Сервер не ответил на /health. Проверьте через ПРОВЕРИТЬ САДОХОД.bat.'
}
function PortBusy([int]$port) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne(400)) { return $false }
        $tcp.EndConnect($ar)
        return $true
    } catch { return $false } finally { $tcp.Close() }
}
$lock = New-Object System.Threading.Mutex($false, 'Local\SadohodSetup')
$locked = $false
try {
    try { $locked = $lock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { Fail 'Другой запуск уже выполняется.' }
    Say '=== САДОХОД: запуск ==='
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Fail 'Docker Desktop не установлен. Установите Docker Desktop, затем снова запустите файл.'
    }
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) {
        $desktop = Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'
        if (Test-Path $desktop) {
            Say 'Запускаю Docker Desktop...'
            Start-Process -FilePath $desktop | Out-Null
            for ($i=0; $i -lt 60; $i++) {
                Start-Sleep -Seconds 2
                & docker info --format '{{.ServerVersion}}' *> $null
                if ($LASTEXITCODE -eq 0) { break }
            }
        }
    }
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'Docker Desktop не запущен. Откройте его и повторите запуск.' }
    Say '[OK] Docker работает.'

    $flutter = (Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $flutter) { Fail 'Добавьте flutter в PATH и повторите запуск.' }
    $env:COMPOSE_PROJECT_NAME = $projectName
    $env:COMPOSE_FILE = Join-Path $root 'docker-compose.yml'
    DockerRun @('compose','version') | Out-Null
    foreach ($port in @(55114,55115)) {
        if (PortBusy $port) { Fail "Порт $port занят. Закройте прежнее окно запуска Flutter и повторите." }
    }
    $volumes = @(DockerRun @('volume','ls','-q'))
    $found = @($volumeNames.Values | Where-Object { $volumes -contains $_ })
    $envFile = Join-Path $root '.env'
    if ($Mode -eq 'First') {
        $containers = @(DockerRun @('ps','-aq','--filter',"label=com.docker.compose.project=$projectName"))
        $env:COMPOSE_FILE += ';' + (Join-Path $root 'docker-compose.first.yml')
        $pending = Join-Path $root '.first-install.pending'
        $resuming = Test-Path -LiteralPath $pending -PathType Leaf
        if ($resuming) {
            $installId = [IO.File]::ReadAllText($pending)
            if ($installId -notmatch '^[a-f0-9]{32}$' -or -not (Test-Path -LiteralPath $envFile)) {
                Fail 'Для продолжения первого запуска нужны исходные файлы .env и .first-install.pending.'
            }
            foreach ($vol in $found) {
                $meta = (DockerRun @('volume','inspect',$vol) | Out-String | ConvertFrom-Json)
                if ($meta.Labels.'ru.sadohod.install' -ne $installId) { Fail "Том $vol принадлежит другой установке." }
            }
            foreach ($id in $containers) {
                $meta = (DockerRun @('inspect',$id) | Out-String | ConvertFrom-Json)
                if ($meta.Config.Labels.'ru.sadohod.install' -ne $installId) { Fail 'Найден контейнер другой установки.' }
            }
        } else {
            if ($found.Count -or $containers.Count) { Fail 'Найдены данные Садохода. Используйте ОБНОВИТЬ САДОХОД.' }
            foreach ($port in @(5432,8000)) {
                if (PortBusy $port) { Fail "Освободите порт $port и повторите запуск." }
            }
            $installId = [Guid]::NewGuid().ToString('N')
        }
        $env:SADOHOD_INSTALL_ID = $installId
        if (-not (Test-Path -LiteralPath $envFile)) {
            $bytes = New-Object byte[] 32
            $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
            $password = [BitConverter]::ToString($bytes).Replace('-','')
            [IO.File]::WriteAllText($envFile, "POSTGRES_PASSWORD=$password", [Text.Encoding]::ASCII)
        }
        [IO.File]::WriteAllText($pending, $installId, [Text.Encoding]::ASCII)
        DockerRun @('compose','build','api') | Out-Null
        DockerRun @('compose','up','-d','api') | Out-Null
    } else {
        if ($found.Count -ne $volumeNames.Count) {
            Fail 'Для обновления нужны все три тома проекта: база, фото и настройки. Проверьте Docker Desktop и выбранный Docker context.'
        }
        $oldDb = ContainerId 'db'
        $oldApi = ContainerId 'api'
        foreach ($item in @(@{id=$oldDb; mounts=@{'/var/lib/postgresql/data'=$volumeNames.db}},
                            @{id=$oldApi; mounts=@{'/app/backend/media/products/uploads'=$volumeNames.photos; '/app/state'=$volumeNames.state}})) {
            if (-not $item.id) { continue }
            $info = (DockerRun @('inspect',$item.id) | Out-String | ConvertFrom-Json)
            foreach ($dest in $item.mounts.Keys) {
                $mount = @($info.Mounts | Where-Object { $_.Destination -eq $dest })
                if ($mount.Count -ne 1 -or $mount[0].Name -ne $item.mounts[$dest]) {
                    Fail "Контейнер использует другое хранилище для $dest. Проверьте конфигурацию установки."
                }
            }
        }
        if ($oldApi) {
            $apiInfo = (DockerRun @('inspect',$oldApi) | Out-String | ConvertFrom-Json)
            $env:SADOHOD_INSTALL_ID = $apiInfo.Config.Labels.'ru.sadohod.install'
            $configs = @($apiInfo.Config.Labels.'com.docker.compose.project.config_files' -split ',')
            $names = @($configs | ForEach-Object { Split-Path $_ -Leaf } | Where-Object { $_ -notin @('docker-compose.first.yml','docker-compose.update.yml') })
            if ($names[0] -ne 'docker-compose.yml' -or @($names | Where-Object { $_ -notin @('docker-compose.yml','docker-compose.ml.yml','docker-compose.https.yml') }).Count) {
                Fail 'Обнаружена индивидуальная конфигурация Compose. Обновите её с учётом прежних файлов.'
            }
            $env:COMPOSE_FILE = ($names | ForEach-Object { Join-Path $root $_ }) -join ';'
        }
        $env:COMPOSE_FILE += ';' + (Join-Path $root 'docker-compose.update.yml')
        $dbEnvironment = DockerEnvironment $oldDb
        $apiEnvironment = DockerEnvironment $oldApi

        $envFile = Join-Path $root '.env'
        if (-not (Test-Path -LiteralPath $envFile)) {
            $oldEnv = $null
            if ($oldDb) {
                $info = (DockerRun @('inspect',$oldDb) | Out-String | ConvertFrom-Json)
                $oldFolder = $info.Config.Labels.'com.docker.compose.project.working_dir'
                if ($oldFolder -and (Test-Path -LiteralPath $oldFolder -PathType Container)) {
                    $candidate = Join-Path $oldFolder '.env'
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $oldEnv = $candidate }
                }
            }
            if ($oldEnv) {
                Copy-Item -LiteralPath $oldEnv -Destination $envFile
                Say '[OK] Настройки из старой папки подключены.'
            } elseif ($dbEnvironment.ContainsKey('POSTGRES_PASSWORD')) {
                # When the old .env is unavailable, reconstruct only values from the
                # *running or stopped existing containers*. Never print credentials.
                $settings = [ordered]@{}
                $settings['POSTGRES_PASSWORD'] = $dbEnvironment['POSTGRES_PASSWORD']
                foreach ($key in @('SMTP_HOST','SMTP_PORT','SMTP_FROM','SMTP_USER','SMTP_PASSWORD','TELEGRAM_BOT_TOKEN','TELEGRAM_GROUP_ID','SADOHOD_BIND')) {
                    if ($apiEnvironment.ContainsKey($key)) { $settings[$key] = $apiEnvironment[$key] }
                }
                $lines = @('# Local settings restored from existing Docker containers.')
                foreach ($key in $settings.Keys) { $lines += ($key + '=' + (QuoteDotEnv ([string]$settings[$key]))) }
                [System.IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
                Say '[OK] Настройки восстановлены из существующих контейнеров.'
            } else {
                Fail 'Не удалось найти старые настройки подключения. Ничего не запускаю, чтобы не подменить базу. Файлы целы.'
            }
        }
        # Safety check: do not recreate DB using an unintended password.
        if ($dbEnvironment.ContainsKey('POSTGRES_PASSWORD')) {
            $composeText = (& docker compose config --format json 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0) { Fail 'Не удалось проверить конфигурацию Docker Compose.' }
            $compose = $composeText | ConvertFrom-Json
            $newPass = [string]$compose.services.db.environment.POSTGRES_PASSWORD
            if ($newPass -cne [string]$dbEnvironment['POSTGRES_PASSWORD']) {
                Fail 'Пароль в новой конфигурации не совпадает с действующим сервером. Никаких изменений не выполнено.'
            }
        }

        if (-not $oldDb) {
            Say 'Запускаю существующую базу для резервного копирования...'
            DockerRun @('compose','up','-d','db') | Out-Null
            $oldDb = ContainerId 'db'
        } else {
            $state = & docker inspect --format '{{.State.Running}}' $oldDb
            if ($state -ne 'true') { DockerRun @('start',$oldDb) | Out-Null }
        }
        if (-not $oldDb) { Fail 'Не удалось найти контейнер PostgreSQL.' }
        WaitForDb $oldDb
        DockerRun @('exec',$oldDb,'sh','-ec','export PGPASSWORD=$POSTGRES_PASSWORD; exec psql -w -h 127.0.0.1 -U sadohod -d sadohod -Atc SELECT\ 1') | Out-Null
        $schemaCheck = @(& docker exec $oldDb psql -U sadohod -d sadohod -tAc "SELECT to_regclass('public.sellers') IS NOT NULL" 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not (($schemaCheck | Out-String).Trim() -eq 't')) {
            Fail 'Существующий PostgreSQL-том найден, но таблицы продавцов нет. Не рискую запускать новый сервер на неизвестной базе.'
        }

        $apiWasRunning = $oldApi -and $apiInfo.State.Running
        DockerRun @('compose','build','api') | Out-Null
        $stamp = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
        $backupDir = Join-Path $root ('backups\' + $stamp)
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        $dumpName = "sadohod_$stamp.dump"
        Say 'Создаю резервную копию базы и фотографий...'
        try {
            if ($apiWasRunning) { DockerRun @('stop',$oldApi) | Out-Null }
            DockerRun @('exec',$oldDb,'pg_dump','-U','sadohod','-d','sadohod','-Fc','-f',"/tmp/$dumpName") | Out-Null
            DockerRun @('cp',("${oldDb}:/tmp/$dumpName"),(Join-Path $backupDir 'database.dump')) | Out-Null
            DockerRun @('exec',$oldDb,'rm','-f',"/tmp/$dumpName") | Out-Null
            $dump = Get-Item -LiteralPath (Join-Path $backupDir 'database.dump')
            if ($dump.Length -lt 1024) { Fail 'Резервная копия базы неожиданно мала.' }

            # Restore the actual file copied to Windows into an isolated database.
            $verifyDb = 'sadohod_verify_' + [Guid]::NewGuid().ToString('N')
            $restoreFile = "/tmp/$verifyDb.dump"
            DockerRun @('exec',$oldDb,'createdb','-U','sadohod','-T','template0',$verifyDb) | Out-Null
            try {
                DockerRun @('cp',(Join-Path $backupDir 'database.dump'),("${oldDb}:$restoreFile")) | Out-Null
                DockerRun @('exec',$oldDb,'pg_restore','--exit-on-error','-U','sadohod','-d',$verifyDb,$restoreFile) | Out-Null
                $sql = 'SELECT (SELECT count(*) FROM sellers),(SELECT count(*) FROM products),(SELECT count(*) FROM pavilions),(SELECT count(*) FROM product_images)'
                $expected = (DockerRun @('exec',$oldDb,'psql','-U','sadohod','-d','sadohod','-Atc',$sql) | Out-String).Trim()
                $restored = (DockerRun @('exec',$oldDb,'psql','-U','sadohod','-d',$verifyDb,'-Atc',$sql) | Out-String).Trim()
                if ($expected -ne $restored) { Fail 'Количество продавцов, товаров, павильонов или фото в копии отличается.' }
                Say 'Проверяю миграции на восстановленной копии базы...'
                DockerRun @('compose','run','--rm','--no-deps','-T','api',
                    'python','-m','backend.app.migration_rehearsal','--verify-database',$verifyDb) | Out-Null
                Say '[OK] Миграции на копии прошли; существующие записи сохранены.'

            } finally {
                DockerRun @('exec',$oldDb,'dropdb','-U','sadohod',$verifyDb) | Out-Null
                DockerRun @('exec',$oldDb,'rm','-f',$restoreFile) | Out-Null
            }
            # Attach existing volumes strictly read-only, then copy their data to Windows.
            $readerName = 'sadohod_readonly_backup_' + $PID
            $readerId = ''
            try {
                $image = (& docker inspect --format '{{.Config.Image}}' $oldDb).Trim()
                if ($LASTEXITCODE -ne 0 -or -not $image) { Fail 'Не удалось определить образ для резервного копирования.' }
                $readerOutput = DockerRun @('run','-d','--name',$readerName,'--entrypoint','sh',
                    '--mount',"type=volume,source=$($volumeNames.photos),target=/data_photos,readonly",
                    '--mount',"type=volume,source=$($volumeNames.state),target=/data_state,readonly",
                    $image,'-c','while true; do sleep 60; done')
                $readerId = [string]($readerOutput | Select-Object -Last 1)
                $photosDir = Join-Path $backupDir 'photos'
                $stateDir = Join-Path $backupDir 'state'
                New-Item -ItemType Directory -Path $photosDir,$stateDir -Force | Out-Null
                DockerRun @('cp',("${readerId}:/data_photos/."),$photosDir) | Out-Null
                DockerRun @('cp',("${readerId}:/data_state/."),$stateDir) | Out-Null
            } finally {
                if ($readerId) { & docker rm -f $readerId *> $null }
            }
            Say ('[OK] Копия сохранена: backups\' + $stamp)
        } catch {
            if ($apiWasRunning) { DockerRun @('start',$oldApi) | Out-Null }
            Fail ('Не удалось закончить резервное копирование или проверку миграций: ' + $_.Exception.Message + '. Новый сервер не запускался.')
        }

        Say 'Обновляю единый сервер...'
        DockerRun @('compose','up','-d','--no-deps','api') | Out-Null
        if ($names -contains 'docker-compose.https.yml') {
            DockerRun @('compose','up','-d','--no-deps','https') | Out-Null
        }
    }
    WaitForApi
    if ($Mode -eq 'First') { Remove-Item -LiteralPath $pending }
    Say '[OK] API работает: http://localhost:8000'
    $runner = Join-Path $PSScriptRoot 'run_client.ps1'
    foreach ($app in @('buyer','seller')) {
        $arguments = '-NoExit -NoProfile -ExecutionPolicy Bypass -File "' + $runner + '" -App ' + $app + ' -Flutter "' + $flutter + '"'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $root | Out-Null
        Say ('[OK] Запускается приложение: ' + $app)
    }
    Say ''
    Say 'Сервер готов. Flutter откроет Chrome после сборки обоих приложений.'
    Say 'Покупатель: http://localhost:55114'
    Say 'Продавец:  http://localhost:55115'
    Say 'Старые Docker Volumes не удалялись.'
} catch {
    Write-Host '' -ForegroundColor Red
    Write-Host ('ОСТАНОВЛЕНО: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Старые данные не удалялись. Можно прислать скриншот этого окна.'
    exit 1
} finally {
    if ($locked) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
