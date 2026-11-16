# Происхождение объединения (15 ноября 2026)

- Полный сервер, клиент покупателя, Compose и статика: `Sadohod_v0.8.3_TELEGRAM_FULL_SOURCE(1).zip`.
- Последняя доступная ветка чата покупателя: `Sadohod_v0.8.3.3_TELEGRAM_NAME_NO_CAPTION_FIGMA_PATCH(1).zip` (`mobile/` и read-only диагностика).
- Полный Figma-клиент продавца: `Sadohod_Seller_V3_Checkpoint_2026-11-13(2).zip`.
- Накопительный серверный Patch 22: `Sadohod_Seller_V3_Cumulative_Patch_22.zip` (`backend/app` + тесты + assets + chat).
- Последняя доступная версия формы и локальных черновиков без самодельных экранов: `Sadohod_Draft_Recovery_Patch_19_CHECKPOINT(1).zip`, файл `seller_app/lib/seller_v3.dart`.

Уточнения объединения:

1. Серверный `main.py` собран из накопительного Patch 22, который содержит маршруты merchant_operations и merchant_chat. При этом версия сохранена v0.8.3.3 от покупательского патча.
2. `telegram_bridge.py` из Patch 22 содержит разделение buyer/seller Telegram тем и логику отправителя из v0.8.3.3. Более ранний файл патча покупателя нельзя без потерь подменять вместо него.
3. Во **всех четырёх** блокировках `Seller` в `merchant.py`/`merchant_operations.py` добавлен `of=Seller`: предотвращение PostgreSQL `FOR UPDATE` с eager `LEFT OUTER JOIN pavilions`.
4. Никакие дизайнерские экраны не генерировались. Временные экраны Patch 20 не перенесены; чат из Patch 21 подключён через навигацию.
5. Вынесен общий Flutter API base URL resolver; отдельные модели и UI не объединялись, поскольку у них разные сценарии.
6. Запуск, живая база и браузерная отрисовка не проверены на этой машине.
