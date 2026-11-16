"""Read-only bridge diagnostics: prints counters, never the group ID or token."""
from sqlalchemy import func, select
from .database import SessionLocal
from .telegram_bridge import TelegramInbound, TelegramOffset, TelegramOutbox, TelegramTopic, TelegramBridgeHealth, configured, tg_api, group_id
from .buyer_extras import BuyerMessage

def run():
    print('Telegram enabled in API container:', 'yes' if configured() else 'NO')
    with SessionLocal() as db:
        for title, stmt in [
            ('Mapped topics', select(func.count()).select_from(TelegramTopic)),
            ('Telegram inbound updates stored', select(func.count()).select_from(TelegramInbound)),
            ('Pending outbound messages', select(func.count()).select_from(TelegramOutbox).where(TelegramOutbox.delivered.is_(False))),
            ('Delivered outbound messages', select(func.count()).select_from(TelegramOutbox).where(TelegramOutbox.delivered.is_(True))),
            ('Manager replies in app database', select(func.count()).select_from(BuyerMessage).where(BuyerMessage.staff.is_(True))),
        ]:
            print(title + ':', db.scalar(stmt))
        checkpoint = db.get(TelegramOffset, 'update_id')
        print('Telegram poll checkpoint stored:', 'yes' if checkpoint else 'no')
        state = db.get(TelegramBridgeHealth, 'worker')
        if state is None:
            print('Bridge polling status: not started (no runtime records)')
        else:
            import time
            age = lambda when: (str(int(time.time()-when))+'s ago') if when else 'never'
            print('Last successful Telegram poll:', age(state.last_poll_at))
            print('Last inbound group update:', age(state.last_update_at))
            print('Last manager reply saved:', age(state.last_reply_at))
            print('Polls / skipped updates / errors:',
                  state.poll_count, state.ignored_count, state.error_count)
            print('Last skipped reason:', state.last_ignored_reason or 'none')
            print('Last error category:', state.last_error or 'none')
    if configured():
        try:
            me = tg_api('getMe', {})
            print('Bot reports group-message visibility:',
                  'yes' if me.get('can_read_all_group_messages') else 'not confirmed')
            webhook = tg_api('getWebhookInfo', {})
            print('Conflicting Telegram webhook:', 'YES - getUpdates cannot work' if webhook.get('url') else 'no')
            own = tg_api('getChatMember', {'chat_id':group_id(),'user_id':me['id']})
            status = own.get('status', 'unknown')
            print('Bot group status:', status)
            if status not in ('administrator', 'creator'):
                print('ACTION: give the bot administrator rights in this private group.')
            print('MESSAGE TEST: in a user topic send /sadohod_test@sadohod_support_bot')
            print('The bot should answer: topic mapped to app yes/no.')
            print('Reply from the topic itself, not General, then open the app chat.')
        except Exception as exc:
            print('Live Telegram check:', type(exc).__name__)

if __name__ == '__main__':
    run()

