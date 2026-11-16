"""Private Telegram forum bridge for buyer support/cooperation.

The API never exposes the bot token. The bridge runs only when both token and
an explicitly approved private forum-group ID are configured. It uses
getUpdates long polling: no public webhook or reverse proxy is needed.

All message content remains authoritative in PostgreSQL. Buyer -> Telegram
uses a durable outbox; Telegram -> buyer uses a unique inbound update marker.
"""
from __future__ import annotations

import asyncio
import json
import mimetypes
import logging
import os
import secrets
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import Float, ForeignKey, Integer, String, Text, UniqueConstraint, select
from sqlalchemy.orm import Mapped, Session, mapped_column

from .database import Base, SessionLocal

log = logging.getLogger(__name__)


class TelegramTopic(Base):
    __tablename__ = 'telegram_buyer_topics_v083'
    __table_args__ = (UniqueConstraint('chat_id', 'thread_id', name='uq_v083_telegram_thread'),)
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id'), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), primary_key=True)
    chat_id: Mapped[str] = mapped_column(String(24), nullable=False)
    thread_id: Mapped[int] = mapped_column(Integer, nullable=False)
    created: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)


class TelegramOutbox(Base):
    __tablename__ = 'telegram_buyer_outbox_v083'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id'), index=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    message_id: Mapped[str] = mapped_column(String(32), nullable=False)
    sent: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)
    delivered: Mapped[bool] = mapped_column(default=False, nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    retry_after: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)


class TelegramInbound(Base):
    __tablename__ = 'telegram_buyer_inbound_v083'
    chat_id: Mapped[str] = mapped_column(String(24), primary_key=True)
    message_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    created: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)


class TelegramBridgeHealth(Base):
    """Sanitized on-disk state for troubleshooting without exposing messages."""
    __tablename__ = 'telegram_buyer_bridge_health_v0832'
    key: Mapped[str] = mapped_column(String(24), primary_key=True)
    last_poll_at: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    last_update_at: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    last_reply_at: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    poll_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    ignored_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    error_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_ignored_reason: Mapped[str] = mapped_column(String(60), default='', nullable=False)
    last_error: Mapped[str] = mapped_column(String(100), default='', nullable=False)


def record_bridge_health(**changes: Any) -> None:
    with SessionLocal() as db:
        state = db.get(TelegramBridgeHealth, 'worker')
        if state is None:
            state = TelegramBridgeHealth(key='worker')
            db.add(state)
        for key, value in changes.items():
            if key in {'poll_count','ignored_count','error_count'}:
                value = (getattr(state, key, None) or 0) + int(value)
            setattr(state, key, value)
        db.commit()


def inbound_ignore_reason(update: dict) -> str:
    """Safe reason codes only; never capture message text, people or IDs."""
    message = update.get('message') or {}
    if not message:
        return 'no_message'
    chat = message.get('chat') or {}
    if str(chat.get('id','')) != group_id():
        return 'different_group'
    if chat.get('type') != 'supergroup':
        return 'not_supergroup'
    sender_chat = message.get('sender_chat')
    if sender_chat and (str(sender_chat.get('id','')) != group_id() or sender_chat.get('type') != 'supergroup'):
        return 'another_sender_chat'
    if not sender_chat and (message.get('from') or {}).get('is_bot'):
        return 'bot_message'
    tid = message.get('message_thread_id') or (message.get('reply_to_message') or {}).get('message_thread_id')
    if not isinstance(tid, int):
        return 'missing_topic_id'
    text = (message.get('text') or message.get('caption') or '').strip()
    if text.startswith('/'):
        return 'command'
    if not text and not (message.get('photo') or message.get('document')):
        return 'non_text_service_message'
    with SessionLocal() as db:
        topic = db.scalar(select(TelegramTopic.thread_id).where(TelegramTopic.chat_id == group_id(), TelegramTopic.thread_id == tid))
        if topic is None:
            return 'unmapped_topic'
    return 'duplicate_or_filtered'


class TelegramOffset(Base):
    __tablename__ = 'telegram_buyer_offset_v083'
    key: Mapped[str] = mapped_column(String(32), primary_key=True)
    value: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


def bot_token() -> str:
    return os.getenv('TELEGRAM_BOT_TOKEN', '').strip()


def group_id() -> str:
    return os.getenv('TELEGRAM_GROUP_ID', '').strip()


def configured() -> bool:
    return bool(bot_token() and group_id())


def tg_api(method: str, payload: dict[str, Any], *, timeout: float = 15) -> Any:
    token = bot_token()
    if not token:
        raise RuntimeError('Telegram bot token is not configured')
    body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{token}/{method}', data=body,
        headers={'Content-Type': 'application/json; charset=utf-8'}, method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        # Do not log URLs: Telegram's bot token is part of them.
        raise RuntimeError(f'Telegram returned HTTP {exc.code} for {method}') from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError(f'Telegram transport error for {method}') from None
    if not result.get('ok'):
        raise RuntimeError(f'Telegram API rejected {method}: {str(result.get("description", "error"))[:160]}')
    return result.get('result')


def tg_upload(method: str, fields: dict[str, str | int], payload: bytes,
              filename: str, mime: str) -> Any:
    """Send a bounded attachment to the official Bot API over HTTPS."""
    import uuid
    boundary = 'sadohod' + uuid.uuid4().hex
    sections = []
    for name, val in fields.items():
        sections.append((f'--{boundary}\r\nContent-Disposition: form-data; '
            f'name="{name}"\r\n\r\n{val}\r\n').encode('utf-8'))
    name = 'photo' if method == 'sendPhoto' else 'document'
    safe_filename = filename.replace('"','').replace('\r','').replace('\n','')
    sections.append((f'--{boundary}\r\nContent-Disposition: form-data; '
        f'name="{name}"; filename="{safe_filename}"\r\n'
        f'Content-Type: {mime}\r\n\r\n').encode('utf-8'))
    sections.extend([payload, f'\r\n--{boundary}--\r\n'.encode()])
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{bot_token()}/{method}', data=b''.join(sections),
        headers={'Content-Type': f'multipart/form-data; boundary={boundary}'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            parsed = json.load(resp)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f'Telegram upload failed with HTTP {exc.code}') from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError('Telegram upload transport error') from None
    if not parsed.get('ok'):
        raise RuntimeError('Telegram rejected media upload')
    return parsed.get('result')


def tg_download(file_id: str, size: int) -> bytes:
    if not size or size > 3_000_000:
        raise ValueError('Telegram attachment is too large')
    meta = tg_api('getFile', {'file_id': file_id})
    path = str(meta.get('file_path',''))
    if not path or '..' in path or path.startswith('/'):
        raise ValueError('Invalid Telegram file path')
    req = urllib.request.Request(f'https://api.telegram.org/file/bot{bot_token()}/{path}')
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read(3_000_001)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError('Telegram file download failed') from None
    if len(data) > 3_000_000:
        raise ValueError('Telegram attachment is too large')
    return data


def make_outbox(db: Session, message: 'BuyerMessage') -> None:
    """Call before committing a new user message. No Telegram network I/O here."""
    db.add(TelegramOutbox(id=secrets.token_hex(16), buyer=message.buyer,
        kind=message.kind, message_id=message.id, sent=message.sent))


def delivered_message_ids(db: Session, buyer: str, kind: str, records: list) -> set[str]:
    """Return only this user's outgoing messages confirmed sent to Telegram.

    This is *delivery*, not manager read status. The outbox remains the
    authoritative source; no new status column or migration is needed.
    """
    ids = [m.id for m in records if not m.staff]
    if not ids:
        return set()
    return set(db.scalars(select(TelegramOutbox.message_id).where(
        TelegramOutbox.buyer == buyer,
        TelegramOutbox.kind == kind,
        TelegramOutbox.delivered.is_(True),
        TelegramOutbox.message_id.in_(ids),
    )).all())


def manager_author_header(buyer: 'Buyer') -> str:
    """Account data for the private Telegram manager group only.

    Never use Telegram-supplied names or emails as the source of truth.
    Newlines are stripped so user-provided profile names cannot spoof fields.
    """
    clean_name = ' '.join((buyer.name or '').split()).strip()[:80] or 'Не указано'
    return f'Имя: {clean_name}\nEmail: {buyer.email}'


def ensure_topic(db: Session, buyer: str, kind: str, chat: str, name: str = '') -> TelegramTopic:
    row = db.get(TelegramTopic, (buyer, kind))
    if row is not None:
        if row.chat_id != chat:
            raise RuntimeError('Topic belongs to another Telegram group')
        return row
    # User's chosen display name in private manager topic; never put email
    # in the topic list. Existing topics keep their stable thread IDs/titles.
    clean_name = ' '.join((name or '').split())[:45]
    title = {'support': 'Поддержка', 'cooperation': 'Сотрудничество',
             'm_support': 'Продавец · Поддержка', 'm_cooperation': 'Продавец · Сотрудничество'}.get(kind, 'Обращение')
    if clean_name:
        title += f' · {clean_name}'
    title += f' · #{buyer[:8]}'
    created = tg_api('createForumTopic', {'chat_id': chat, 'name': title})
    thread_id = int(created['message_thread_id'])
    row = TelegramTopic(buyer=buyer, kind=kind, chat_id=chat, thread_id=thread_id)
    db.add(row)
    db.commit()
    return row


def send_pending() -> int:
    """Drain bounded messages. Failures are retried; the user's post stays saved."""
    if not configured():
        return 0
    from .account import Buyer
    from .buyer_extras import BuyerMessage, BuyerChatAttachment
    count = 0
    now = time.time()
    with SessionLocal() as db:
        pending = db.scalars(select(TelegramOutbox).where(
            TelegramOutbox.delivered.is_(False), TelegramOutbox.retry_after <= now,
        ).order_by(TelegramOutbox.sent).limit(20)).all()
        for row in pending:
            buyer_record = db.get(Buyer, row.buyer)
            if buyer_record is None:
                db.delete(row)
                db.commit()
                continue
            msg = db.get(BuyerMessage, row.message_id)
            if msg is None or msg.staff:
                db.delete(row)
                db.commit()
                continue
            try:
                topic = ensure_topic(db, row.buyer, row.kind, group_id(), buyer_record.name)
                author = ('Продавец\n' if row.kind.startswith('m_') else '') + manager_author_header(buyer_record)
                attachment = db.scalar(select(BuyerChatAttachment).where(
                    BuyerChatAttachment.message_id == msg.id))
                if attachment is not None:
                    # The identity is a separate Telegram text message. Media
                    # have NO caption field, including the automatic labels
                    # ("Фото", "Файл: ...") persisted by legacy app builds.
                    # If an upload temporarily fails, the outbox retries it.
                    tg_api('sendMessage', {
                        'chat_id': topic.chat_id,
                        'message_thread_id': topic.thread_id,
                        'text': author,
                        'disable_web_page_preview': True,
                    })
                    is_image = attachment.mime.startswith('image/')
                    tg_upload('sendPhoto' if is_image else 'sendDocument', {
                        'chat_id': topic.chat_id,
                        'message_thread_id': topic.thread_id,
                    }, attachment.raw, attachment.filename, attachment.mime)
                else:
                    tg_api('sendMessage', {
                        'chat_id': topic.chat_id,
                        'message_thread_id': topic.thread_id,
                        'text': f'{author}\n\n{msg.text}',
                        'disable_web_page_preview': True,
                    })
                row.delivered = True
                count += 1
            except Exception as exc:
                row.attempts += 1
                row.retry_after = time.time() + min(300, 5 * 2**min(row.attempts, 6))
                log.warning('Telegram outbound delivery deferred: %s', exc)
            db.commit()
    return count


def process_inbound(update: dict) -> bool:
    """Accept only messages written by a human manager in a mapped topic."""
    if not configured():
        return False
    message = update.get('message') or {}
    chat = message.get('chat') or {}
    if str(chat.get('id', '')) != group_id():
        return False
    if chat.get('type') != 'supergroup':
        return False
    sender_chat = message.get('sender_chat')
    if sender_chat:
        # Accept anonymous managers only when they speak as THIS group.
        # Other channels/groups are never authorized.
        if (str(sender_chat.get('id', '')) != group_id()
                or sender_chat.get('type') != 'supergroup'):
            return False
    elif (message.get('from') or {}).get('is_bot'):
        return False
    mid = message.get('message_id')
    tid = message.get('message_thread_id')
    if not isinstance(tid, int):
        parent = message.get('reply_to_message') or {}
        if isinstance(parent, dict):
            tid = parent.get('message_thread_id')
    raw_text = message.get('text') or message.get('caption') or ''
    if not (isinstance(mid, int) and isinstance(tid, int) and isinstance(raw_text, str)):
        return False
    has_media = bool(message.get('photo') or message.get('document'))
    text = raw_text.strip()
    if not text and not has_media:
        return False
    if text.split(' ', 1)[0].split('@', 1)[0] == '/sadohod_test':
        # Bot commands are delivered even if group privacy is enabled. This
        # checks real inbound polling and whether the current topic is mapped.
        with SessionLocal() as db:
            mapped = db.scalar(select(TelegramTopic.thread_id).where(
                TelegramTopic.chat_id == group_id(), TelegramTopic.thread_id == tid)) is not None
        tg_api('sendMessage', {
            'chat_id': group_id(), 'message_thread_id': tid,
            'text': ('Садоход: бот получает сообщения. Тема связана с приложением: '
                     + ('да' if mapped else 'нет')),
        })
        return False
    if text.startswith('/'):
        return False
    with SessionLocal() as db:
        if db.get(TelegramInbound, (group_id(), mid)):
            return False
        topic = db.scalar(select(TelegramTopic).where(
            TelegramTopic.chat_id == group_id(), TelegramTopic.thread_id == tid))
        if topic is None:
            return False
        from .buyer_extras import BuyerMessage, BuyerChatAttachment, attachment_bytes
        from .account import Buyer
        if not db.get(Buyer, topic.buyer):
            return False
        attachment = None
        if message.get('photo'):
            photo = message['photo'][-1]
            buf = tg_download(photo['file_id'], int(photo.get('file_size') or 0))
            import base64
            raw, mime, name, preview = attachment_bytes('photo.jpg', base64.b64encode(buf).decode())
            attachment = (raw, mime, name, preview)
        elif message.get('document'):
            doc = message['document']
            buf = tg_download(doc['file_id'], int(doc.get('file_size') or 0))
            import base64
            raw, mime, name, preview = attachment_bytes(
                str(doc.get('file_name') or 'file.txt'), base64.b64encode(buf).decode())
            attachment = (raw, mime, name, preview)
        msg = BuyerMessage(id=secrets.token_hex(16), buyer=topic.buyer,
            kind=topic.kind, text=(text or ('Фото' if message.get('photo') else 'Файл'))[:2000],
            sent=time.time(), staff=True)
        db.add(TelegramInbound(chat_id=group_id(), message_id=mid))
        db.add(msg)
        if attachment:
            raw, mime, name, preview = attachment
            db.add(BuyerChatAttachment(id=secrets.token_hex(16), buyer=topic.buyer,
                message_id=msg.id, filename=name, mime=mime, raw=raw, preview=preview))
        db.commit()
        log.info('Telegram manager reply stored for %s', topic.kind)
        return True


def _load_offset(db: Session) -> int:
    row = db.get(TelegramOffset, 'update_id')
    return row.value if row else 0


def _save_offset(db: Session, next_offset: int) -> None:
    row = db.get(TelegramOffset, 'update_id')
    if row:
        row.value = next_offset
    else:
        db.add(TelegramOffset(key='update_id', value=next_offset))
    db.commit()


def poll_once() -> int:
    if not configured():
        return 0
    with SessionLocal() as db:
        offset = _load_offset(db)
    try:
        items = tg_api('getUpdates', {
            'offset': offset, 'timeout': 3, 'limit': 40,
            'allowed_updates': ['message'],
        }, timeout=12)
    except Exception as exc:
        # Never log token-bearing URLs, chat IDs or message contents.
        record_bridge_health(error_count=1, last_error='getUpdates: ' + type(exc).__name__)
        raise
    record_bridge_health(last_poll_at=time.time(), poll_count=1, last_error='')
    processed = 0
    for update in items:
        try:
            accepted = process_inbound(update)
            processed += int(accepted)
            if accepted:
                record_bridge_health(last_update_at=time.time(), last_reply_at=time.time())
            else:
                reason = inbound_ignore_reason(update)
                record_bridge_health(last_update_at=time.time(),
                                     ignored_count=1, last_ignored_reason=reason)
                # Make a wrong topic distinguishable from a network failure.
                if reason in {'unmapped_topic', 'missing_topic_id', 'another_sender_chat'}:
                    log.warning('Telegram inbound skipped: %s', reason)
        except Exception as exc:
            # No offset advance for failed processing (no message loss).
            record_bridge_health(error_count=1,
                                 last_error='inbound: ' + type(exc).__name__)
            log.warning('Telegram inbound processing deferred: %s', type(exc).__name__)
            break
        with SessionLocal() as db:
            _save_offset(db, int(update['update_id'])+1)
    return processed


async def run_bridge() -> None:
    if not configured():
        log.info('Telegram integration disabled; configure bot token and group ID to enable')
        return
    log.info('Telegram bridge started for a private forum group')
    while True:
        try:
            await asyncio.to_thread(send_pending)
            await asyncio.to_thread(poll_once)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.warning('Telegram bridge retrying: %s', exc)
            await asyncio.sleep(4)


def test_setup() -> None:
    """One-time CLI group discovery; prints group IDs, never prints the token."""
    if not bot_token():
        print('TELEGRAM_BOT_TOKEN is missing from your private .env')
        raise SystemExit(2)
    me = tg_api('getMe', {})
    print('Authenticated as @'+str(me.get('username', 'unknown')))
    if me.get('username', '').lower() != 'sadohod_support_bot':
        print('Warning: this is not the expected @sadohod_support_bot')
    updates = tg_api('getUpdates', {'timeout': 1, 'limit': 100, 'allowed_updates': ['message']}, timeout=12)
    matches = {}
    for update in updates:
        message = update.get('message') or {}
        chat = message.get('chat') or {}
        if chat.get('type') == 'supergroup' and chat.get('is_forum'):
            matches[str(chat['id'])] = chat.get('title', 'Untitled')
    if not matches:
        print('No forum group was found. Send /start@sadohod_support_bot in its General topic and rerun this command.')
        raise SystemExit(3)
    for chat_id, title in matches.items():
        print(f'Forum group: {title}; TELEGRAM_GROUP_ID={chat_id}')
    print('Add the ID of YOUR intended private manager group to .env; other groups are never accepted.')


if __name__ == '__main__':
    test_setup()
