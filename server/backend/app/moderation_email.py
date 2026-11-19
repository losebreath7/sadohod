"""Reliable moderator decision emails.

The action and email receipt are inserted into the same DB transaction. A
separate worker sends due messages; mail failure never rolls back a ban.
"""
import logging
import os
import secrets
import smtplib
import ssl
import time
from email.message import EmailMessage

from sqlalchemy import select, or_, and_

from .moderation_enforcement_models import ModerationEmail

log = logging.getLogger(__name__)


def queue_decision(db, recipient, subject, kind, label, reason):
    if not recipient:
        return
    body = (
        'Здравствуйте!\n\n'
        f'Решение модерации Садохода: {subject}.\n'
        f'Объект: {kind} «{label}».\n'
        f'Причина: {reason}.\n\n'
        'Если вы не согласны с решением, обратитесь в поддержку Садохода.\n'
        'Это автоматическое уведомление; отвечать на него не нужно.'
    )
    db.add(ModerationEmail(
        id=secrets.token_hex(16), recipient=recipient,
        subject=f'Садоход — {subject}', body=body,
        status='pending', attempts=0,
        next_attempt_at=time.time(), created_at=time.time()))


def send_message(item):
    from .account import smtp_config
    host, sender = smtp_config()
    message = EmailMessage()
    message['From'] = sender
    message['To'] = item.recipient
    message['Subject'] = item.subject
    message.set_content(item.body)
    port = int(os.getenv('SMTP_PORT', '465'))
    context = ssl.create_default_context()
    if port == 465:
        client = smtplib.SMTP_SSL(host, port, timeout=15, context=context)
    else:
        client = smtplib.SMTP(host, port, timeout=15)
    with client:
        if port != 465:
            client.starttls(context=context)
        if os.getenv('SMTP_USER'):
            client.login(os.environ['SMTP_USER'], os.getenv('SMTP_PASSWORD', ''))
        client.send_message(message)


def dispatch_due(session_factory, *, limit=20):
    """Single-worker claim using row locks (SKIP LOCKED on PostgreSQL).

    Retry after failure with exponential delay. A process crash during SMTP
    can cause a duplicate email; database state and moderation are unaffected.
    """
    count = 0
    for _ in range(limit):
        with session_factory() as db:
            q = select(ModerationEmail).where(
                or_(ModerationEmail.status == 'pending',
                    and_(ModerationEmail.status == 'sending',
                         ModerationEmail.next_attempt_at <= time.time())),
                ModerationEmail.next_attempt_at <= time.time()
            ).order_by(ModerationEmail.created_at).limit(1)
            if db.bind.dialect.name == 'postgresql':
                q = q.with_for_update(skip_locked=True)
            row = db.scalar(q)
            if row is None:
                break
            # Status is reserved before SMTP to avoid duplicate concurrent sends.
            row.status = 'sending'
            row.next_attempt_at = time.time() + 300  # Reclaim abandoned sends after 5m
            db.commit()
            rid = row.id
            recipient = row.recipient
            subject = row.subject
            body = row.body
        error = None
        try:
            send_message(type('Mail', (), {'recipient': recipient, 'subject': subject,
                                          'body': body})())
        except Exception as exc:
            error = exc
            log.warning('Moderation email delivery failed: %s', type(exc).__name__)
        with session_factory() as db:
            row = db.get(ModerationEmail, rid)
            if row is None:
                continue
            row.attempts += 1
            if error is None:
                row.status = 'sent'
                row.sent_at = time.time()
                count += 1
            elif row.attempts >= 8:
                row.status = 'failed'
            else:
                row.status = 'pending'
                row.next_attempt_at = time.time() + min(3600, 60 * (2 ** (row.attempts - 1)))
            db.commit()
    return count
