# Садоход — production deployment

Эта инструкция относится только к НОВОМУ Linux VPS. Ни один шаг здесь не требуется
выполнять на рабочем Windows Docker. Локальный Compose-проект sadohod_mvp_v0_2,
его PostgreSQL, фотографии и файлы .env не затрагиваются.

## Архитектура и ограничения

- Самостоятельный docker-compose.production.yml, проект sadohod_public.
  Не комбинировать его с docker-compose.yml локальной установки.
- Отдельные volumes: public_pg, public_uploads, public_admin_state,
  public_ml_cache, public_caddy_data, public_caddy_config.
- FastAPI и PostgreSQL не публикуют порты наружу. Caddy: только 80/443.
- Dockerfile.production не включает demo_data и исходные демонстрационные фото.
- DEMO_SEED=0 и SEARCH_BACKEND=clip проверяются до старта и в FastAPI.
  Использовать только новую пустую БД, не импортировать демонстрационную локальную БД.
- FORWARDED_ALLOW_IPS=* разрешён только в такой схеме, где API не имеет
  внешнего порта, а в gateway network входят лишь доверенные сервисы.
- Никогда не открывать 5432 и 8000 через firewall/публикацию Docker.
- SMTP, пароли, ADMIN_TOKEN — секреты вне Git. Не публиковать docker compose
  config без --quiet: команда может показать секреты.

## После покупки сервера: первый запуск

1. Linux VPS: SSH-ключи, firewall (80, 443, SSH), Docker Engine + Compose v2,
   мониторинг диска/CPU/RAM. Ресурсы подбирать по нагрузочному тесту OpenCLIP.
2. DNS A/AAAA для отдельного API-домена (например api.sadohod.ru) указать
   на VPS. Открыть 80/443 для автоматического публичного сертификата Caddy.
3. Клонировать проверенный commit develop в /srv/sadohod на НОВЫЙ сервер.
   Не переносить локальные volumes, базы, .env, фотографии и демо-аккаунты.
4. Создать .env.production:
   
       cd /srv/sadohod
       cp .env.production.example .env.production
       chmod 600 .env.production
       openssl rand -hex 32    # отдельный POSTGRES_PASSWORD
       openssl rand -hex 32    # отдельный ADMIN_TOKEN

   Секреты сохранить отдельно. POSTGRES_PASSWORD должен быть URL-safe,
   рекомендуется 64 hex символа. Заполнить реальные API_DOMAIN, SMTP_HOST,
   SMTP_PORT (465/587), SMTP_FROM, SMTP_USER, SMTP_PASSWORD и ADMIN_TOKEN.
   ALLOWED_ORIGINS оставить пустым для одних нативных клиентов или перечислить
   точные HTTPS origins браузерных фронтендов.
5. Проверить конфигурацию офлайн, до запуска:

       python3 tools/check_production_env.py --env .env.production
       docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public config --quiet

6. Запустить только на новом VPS:

       docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public up -d --build
       docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public ps
       docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public logs --tail=100 api

   При первом старте OpenCLIP может загрузить веса и построить индекс.
   Ошибка модели не считается успешной готовностью API.
7. Проверить с внешнего устройства HTTPS-сертификат и /health:
   status=ok, demo=false, search_backend=clip. Проверить HTTP->HTTPS,
   запрет прямого доступа к портам 5432/8000 и корректный CORS.
8. Отдельный тестовый email для OTP: доставка кода, срок жизни, лимиты,
   отсутствие кода в ответе API/логах. Проверить регистрацию продавца,
   модерацию товара/фото, павильоны, поиск OpenCLIP, чат и уведомления.
   Тестовые записи удалять только штатными административными действиями.
9. Собрать приложения с явным
   --dart-define=API_BASE_URL=https://<API_DOMAIN>.
   Мобильная release-сборка отказывается от localhost, 10.0.2.2,
   неуказанного и HTTP-адреса. Проверить работу на физических устройствах.
10. Перед публичным запуском: нагрузочные тесты, реальная ML-выборка,
    внешний backup и успешная репетиция восстановления.

## Резервное копирование

       bash tools/backup_production.sh /srv/sadohod-backups

Сохраняются database.dump (custom PostgreSQL dump), user-volumes.tar.gz
(uploads/ и state/), SHA256SUMS с закрытыми правами доступа.
Скрипт НЕ удаляет оригинальные тома. PostgreSQL dump транзакционно согласован,
но файловая копия и БД не снимаются атомарно вместе: для строгой согласованности
на время snapshot остановить загрузки/изменение товаров (maintenance window).

Шифровать копии, держать их ВНЕ VPS, обеспечить несколько поколений.
Периодическая задача cron/systemd timer — только после успешной ручной копии
и restore drill. Секреты .env.production хранить отдельно в защищённом vault,
не прикладывать их к обычным архивам, логам и Git.

## Репетиция восстановления (БЕЗ доступа к production volumes)

На отдельном тестовом хосте или в изолированной Docker-среде:

       bash tools/restore_drill.sh /path/to/backup/20261119T...

Скрипт проверяет SHA256 и tar, запрещает опасные пути и символьные ссылки
в архиве, поднимает ТОЛЬКО изолированный проект sadohod_restore_drill
с тремя НОВЫМИ томами (PostgreSQL, фотографии uploads, админ-состояние state),
восстанавливает БД и физически копирует файлы в соответствующие тома.
SHA256 каждого файла проверяется после копирования непосредственно внутри
тестового контейнера. Если хотя бы один тестовый том уже существует, скрипт
откажется перезаписывать его. После репетиции сверять ссылки БД на фотографии.

Автоматический CI выполняет полный круг на синтетических данных:
создание связанных записей, backup, восстановление в новые тома, сравнение
содержимого и отрицательные тесты для повреждённых/неполных архивов и
повторного восстановления. Команда локального запуска исключительно
на отдельном тестовом компьютере с Docker, без рабочих томов:

       bash tools/test_backup_restore_integration.sh

Этот тест НЕ является репетицией на реальном VPS; восстановление в ином
окружении и offsite backup требуется дополнительно после покупки сервера.

## Реальное восстановление после сбоя

1. Остановить приём записей, сохранить логи инцидента и статус старой системы.
2. На НОВОМ VPS/НОВЫХ томах клонировать прежний проверенный SHA,
   восстановить секреты из приватного хранилища и выполнить preflight.
3. Проверить SHA256 архива и выбрать согласованную пару database.dump и
   user-volumes.tar.gz. Не перезаписывать работающие volumes.
4. Поднять только новую БД. Восстановить dump командой pg_restore
   -U sadohod -d sadohod --no-owner --no-privileges --exit-on-error.
   Вновь созданные volumes uploads/state заполнить из архива;
   восстановление пользовательских файлов не должно менять старые тома.
5. Запустить API/Caddy, проверить /health, SMTP, модерацию, фото, поиск.
   Переключать DNS/трафик лишь после успешного smoke-test.

## Обновление и откат

1. Записать SHA текущей версии и Alembic revision. Установить окно обслуживания.
2. Снять backup, провести контроль целостности и убедиться в возможности
   восстановления перед миграциями БД.
3. В новой проверенной версии повторить preflight и Compose config --quiet.
4. Выполнить docker compose ... -f docker-compose.production.yml up -d --build,
   проверить журналы, /health, доступ к фотографиям и OTP.
5. При регрессии кода БЕЗ изменения БД вернуть прежний SHA/образ и повторить
   smoke-test. При несовместимой миграции НЕ делать слепой downgrade:
   развернуть прежний SHA вместе с предобновлённым backup в изолированные
   новые volumes и переключить трафик после QA.

Никогда не выполнять docker compose down -v над local или public проектом.

## Что нельзя признать проверенным без реальной инфраструктуры

Публичный TLS/автопродление, фактическая SMTP-доставка, firewall, сеть VPS,
производительность OpenCLIP, автоматический backup по расписанию, внешний
restore после аварии, работа нативных релизов с настоящим API.
