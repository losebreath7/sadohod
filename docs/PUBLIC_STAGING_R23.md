# Садоход · быстрый запуск публичного staging API

**Это подготовка нового VPS, не команда для рабочего Windows Docker.**
Локальный Compose `sadohod_mvp_v0_2` и его три тома остаются без изменений.
Публичная конфигурация использует отдельный проект `sadohod_public`.
До проверки на реальных фото и резервного восстановления не переключать пользователей.

## 1. Минимальные условия

- Linux VPS с Docker Engine + Compose v2, 4 vCPU и 8–16 GB RAM как начальная
  конфигурация для CPU OpenCLIP (не гарантия p95, подобрать после замеров).
- DNS A/AAAA для `api.example.com` на VPS. Доступны порты 80/443 и SSH;
  порт 5432 и 8000 **не открывать** в фаерволе.
- Git checkout проверенного `develop` после PR-review, права на Docker.
  SSL выдаёт Caddy автоматически. Учётные данные — только вне Git.
- Отдельный локальный резервный каталог и внешнее хранилище backup. Виртуальный
  сервер без копий вне VPS недостаточен для production.

## 2. Настройка

```bash
cd /srv/sadohod
cp .env.public.example .env.public
chmod 600 .env.public
openssl rand -hex 32
```

Скопировать выведенный пароль в `POSTGRES_PASSWORD` в `.env.public`;
заполнить `API_DOMAIN` (без `https://`). Не оставлять `api.example.com`.
При необходимости браузерных клиентов заполнить `ALLOWED_ORIGINS` точными
HTTPS-origin, например `https://buyer.example.com,https://seller.example.com`.
Для нативных клиентов CORS не нужен.

Использовать **одну и ту же** команду Compose; все три файла обязательны:

```bash
docker compose --env-file .env.public \
  -f docker-compose.yml -f docker-compose.ml.yml -f docker-compose.public.yml \
  -p sadohod_public config --quiet

docker compose --env-file .env.public \
  -f docker-compose.yml -f docker-compose.ml.yml -f docker-compose.public.yml \
  -p sadohod_public up -d --build
```

При первом старте OpenCLIP скачает веса в сохранённый том ML-кеша и
проиндексирует изображения. API не станет готовым до завершения индексации.
Смотреть журнал:
```bash
docker compose --env-file .env.public \
 -f docker-compose.yml -f docker-compose.ml.yml -f docker-compose.public.yml \
 -p sadohod_public logs -f --tail=100 api
```

Проверить `https://<API_DOMAIN>/health`: `status=ok`,
`search_backend=clip`, `demo=false`. Проверить, что HTTP переходит на HTTPS,
и что внешний доступ к `:8000` и `:5432` закрыт.

## 3. Приёмка поиска и клиентских приложений

- Сначала пройти server + Flutter gate. PR #42 с исправлением поиска должен
  быть протестирован и перенесён в `develop` до публичного включения поиска.
- Прогнать независимую контрольную выборку фото через
  `backend.tools.evaluate_photo_search_live`. Проверить top-5, пустые запросы,
  задержку p95 и индексацию нового фото продавца. Не объявлять качество модели
  проверенным на основе unit-тестов со stub-векторами.
- Сделать тест регистрации (нужен настроенный SMTP), одобрения павильона,
  модерации и публикации, загрузки и замены фото, поиска, чатов и уведомлений.
- Flutter release/web-сборки обоих клиентов требуют явного
  `--dart-define=API_BASE_URL=https://<API_DOMAIN>`. Без этой настройки
  нативное приложение обращается к localhost / Android emulator.
  Пример: `flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com`.
  Не отправлять эту сборку пользователям до проверки HTTPS, секретов и фото.
- Админ-панель `/preview` и модераторский вход требуют отдельной проверки
  защиты доступов до production; публичный URL сам по себе не заменяет
  авторизацию и аудит.

## 4. Резервное копирование

```bash
bash tools/backup_public.sh
```

Скрипт сохраняет PostgreSQL custom dump, uploads и состояние администратора
в `backups/public/<UTC-time>`. Права — приватные. Хранить копию **вне VPS**,
ограничить доступ, периодически проверять целостность SHA256 и восстановление
на другом проекте Docker. Не считать dump проверенной резервной копией без
репетиции восстановления. Для регулярной работы настроить cron/systemd timer
после первой успешной ручной копии и репетиции восстановления.

## Переход в production

В `.env.public` изменить `SADOHOD_ENV=production` только после полного
теста. Оставить `DEMO_SEED=0`, убрать тестовые записи из отдельной тестовой
базы корректными административными операциями (не удаляя реальные данные).
Стабильно закрепить серверные версии, хранить секреты вне Git, обеспечить
мониторинг 5xx/диска/памяти и регулярные резервные копии.

**Не использовать `docker compose down -v`** — это уничтожает тома с базой,
фотографиями и настройками. Не выполнять миграции на локальной базе владельца
при подготовке VPS.
