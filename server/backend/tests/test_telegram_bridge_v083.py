"""Telegram bridge uses only in-memory DB and mocked Telegram Bot API."""
from sqlalchemy import select

from backend.tests.test_account import setup, login
from backend.app import telegram_bridge as tg
from backend.app import buyer_extras as extras
from backend.app import account


def test_durable_delivery_topics_and_inbound_reply(setup, monkeypatch):
    client, codes, sessions = setup
    alice = login(client, codes, 'alice@example.com')
    bob = login(client, codes, 'bob@example.com')
    assert client.post('/api/v1/account/profile', headers=alice,
        json={'name':'Анна Иванова'}).status_code == 200
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    actions = []
    def mock_api(method, args, **kwargs):
        actions.append((method, args))
        if method == 'createForumTopic':
            return {'message_thread_id': 500 + len([m for m,a in actions if m == method])}
        if method == 'sendMessage':
            return {'message_id': 70 + len(actions)}
        raise AssertionError(method)
    monkeypatch.setattr(tg, 'tg_api', mock_api)
    # Unauthenticated callers are still rejected.
    assert client.post('/api/v1/account/messages', json={
        'kind':'support','text':'hello','auto_ack':True}).status_code == 401
    assert client.post('/api/v1/account/messages', headers=alice, json={
        'kind':'support', 'text':'Проблема с товаром', 'auto_ack':True}).status_code == 200
    assert client.post('/api/v1/account/messages', headers=alice, json={
        'kind':'support', 'text':'Ещё вопрос', 'auto_ack':True}).status_code == 200
    assert client.post('/api/v1/account/messages', headers=alice, json={
        'kind':'cooperation', 'text':'Поставки', 'auto_ack':True}).status_code == 200
    assert client.post('/api/v1/account/messages', headers=bob, json={
        'kind':'support', 'text':'Другой клиент', 'auto_ack':True}).status_code == 200
    with sessions() as db:
        outbox = db.scalars(select(tg.TelegramOutbox)).all()
        assert len(outbox) == 4
        assert not any(o.delivered for o in outbox)
    assert tg.send_pending() == 4
    assert tg.send_pending() == 0
    assert len([m for m,a in actions if m == 'createForumTopic']) == 3
    topics = [a for m,a in actions if m == 'createForumTopic']
    assert any('Анна Иванова' in a['name'] for a in topics)
    assert all('@' not in a['name'] for a in topics)
    sent = [a for m,a in actions if m == 'sendMessage']
    assert len(sent) == 4
    assert all(a['chat_id'] == '-100999' for a in sent)
    assert 'Имя: Анна Иванова' in sent[0]['text']
    assert 'Email: alice@example.com' in sent[0]['text']
    assert 'Проблема с товаром' in sent[0]['text']
    assert 'Не указано' in sent[-1]['text']
    with sessions() as db:
        buyer_a = db.scalar(select(account.Buyer).where(account.Buyer.email == 'alice@example.com'))
        buyer_b = db.scalar(select(account.Buyer).where(account.Buyer.email == 'bob@example.com'))
        topic_a = db.get(tg.TelegramTopic, (buyer_a.id, 'support'))
        topic_b = db.get(tg.TelegramTopic, (buyer_b.id, 'support'))
        assert topic_a.thread_id != topic_b.thread_id
    incoming = {'message':{'chat':{'id':-100999,'type':'supergroup'},'message_id':90,
        'message_thread_id': topic_a.thread_id, 'text':'Здравствуйте, помогу',
        'from':{'id':42, 'is_bot':False}}}
    assert tg.process_inbound(incoming) is True
    assert tg.process_inbound(incoming) is False  # idempotent
    history = client.get('/api/v1/account/messages?kind=support', headers=alice).json()['items']
    assert history[-1]['text'] == 'Здравствуйте, помогу' and history[-1]['staff'] is True
    assert sum('запрос передан' in m['text'] for m in history) == 1
    assert len(client.get('/api/v1/account/messages?kind=support', headers=bob).json()['items']) == 2


def test_invalid_chat_and_bot_messages_ignored(setup, monkeypatch):
    c, codes, sessions = setup
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    user = login(c, codes, 'user@example.com')
    assert c.post('/api/v1/account/messages',headers=user,
        json={'kind':'support','text':'Test'}).status_code == 200
    with sessions() as db:
        b = db.scalar(select(account.Buyer).where(account.Buyer.email=='user@example.com'))
        db.add(tg.TelegramTopic(buyer=b.id,kind='support',chat_id='-100999',thread_id=66))
        db.commit()
    def event(chat_id=-100999, thread=66, from_bot=False, text='Answer'):
        return {'message':{'chat':{'id':chat_id,'type':'supergroup'},'message_id':18,
            'message_thread_id':thread,'text':text,'from':{'is_bot':from_bot}}}
    assert not tg.process_inbound(event(chat_id=-1001))
    assert not tg.process_inbound(event(thread=999))
    assert not tg.process_inbound(event(from_bot=True))
    assert not tg.process_inbound(event(text='/start'))
    assert tg.process_inbound(event())
    assert c.delete('/api/v1/account',headers=user).status_code == 200
    with sessions() as db:
        assert db.scalars(select(tg.TelegramTopic)).all() == []
        assert db.scalars(select(tg.TelegramOutbox)).all() == []


def test_retry_if_telegram_is_unreachable(setup, monkeypatch):
    c, codes, sessions = setup
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    user=login(c,codes,'user@example.com')
    c.post('/api/v1/account/messages', headers=user, json={'kind':'support','text':'Do not lose me'})
    def offline(method, args, **kwargs):
        raise RuntimeError('Offline')
    monkeypatch.setattr(tg,'tg_api',offline)
    assert tg.send_pending()==0
    with sessions() as db:
        rows=db.scalars(select(tg.TelegramOutbox)).all()
        assert len(rows)==1 and rows[0].attempts == 1 and rows[0].delivered is False
        assert rows[0].retry_after > rows[0].sent


def test_photo_document_uploads_and_private_access(setup, monkeypatch):
    import base64
    import io
    from PIL import Image
    client, codes, sessions = setup
    alice = login(client, codes, 'alice@example.com')
    bob = login(client, codes, 'bob@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    image = Image.new('RGB', (50, 50), (230, 125, 12))
    buf = io.BytesIO(); image.save(buf, format='PNG')
    r = client.post('/api/v1/account/messages/attachment', headers=alice,
        json={'kind':'support', 'filename':'sample.png',
              'data':base64.b64encode(buf.getvalue()).decode('ascii'), 'auto_ack':True})
    assert r.status_code == 200, r.text
    messages = client.get('/api/v1/account/messages?kind=support', headers=alice).json()['items']
    att = [m['attachment'] for m in messages if 'attachment' in m][0]
    assert att['mime'] == 'image/jpeg'
    assert base64.b64decode(att['preview']).startswith(b'\xff\xd8')
    ident = att['id']
    assert client.get('/api/v1/account/messages/attachment/'+ident).status_code == 401
    assert client.get('/api/v1/account/messages/attachment/'+ident, headers=bob).status_code == 404
    assert client.get('/api/v1/account/messages/attachment/'+ident, headers=alice).content.startswith(b'\xff\xd8')
    assert client.post('/api/v1/account/messages/attachment', headers=alice, json={
        'kind':'support','filename':'evil.exe','data':base64.b64encode(b'MZ').decode(),
    }).status_code == 422
    called=[]
    monkeypatch.setattr(tg, 'tg_api', lambda method,args,**kw: {'message_thread_id':122} if method=='createForumTopic' else called.append((method,args)))
    monkeypatch.setattr(tg, 'tg_upload', lambda method,fields,raw,name,mime: called.append((method,fields,name,mime)))
    assert tg.send_pending() == 1
    assert called[0][0] == 'sendMessage'
    assert 'Email: alice@example.com' in called[0][1]['text']
    assert called[1][0] == 'sendPhoto'
    assert called[1][3] == 'image/jpeg'
    assert 'caption' not in called[1][1]
    assert client.delete('/api/v1/account', headers=alice).status_code == 200
    with sessions() as db:
        assert db.scalars(select(extras.BuyerChatAttachment)).all() == []


def test_manager_photo_is_returned_as_private_preview(setup, monkeypatch):
    import base64
    import io
    from PIL import Image
    client, codes, sessions = setup
    alice = login(client, codes, 'alice@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    with sessions() as db:
        buyer = db.scalar(select(account.Buyer).where(account.Buyer.email=='alice@example.com'))
        db.add(tg.TelegramTopic(buyer=buyer.id,kind='cooperation',chat_id='-100999',thread_id=78))
        db.commit()
    f=io.BytesIO();Image.new('RGB',(30,30),(3,4,5)).save(f,format='JPEG')
    monkeypatch.setattr(tg,'tg_api',lambda method,args,**kwargs:{'file_path':'photos/file.jpg'})
    monkeypatch.setattr(tg,'tg_download',lambda file_id,size:f.getvalue())
    evt={'message':{'chat':{'id':-100999,'type':'supergroup'},'message_id':15,
        'message_thread_id':78,'photo':[{'file_id':'abc','file_size':len(f.getvalue())}],
        'from':{'is_bot':False}}}
    assert tg.process_inbound(evt) is True
    history=client.get('/api/v1/account/messages?kind=cooperation',headers=alice).json()['items']
    assert history[0]['staff'] is True
    assert history[0]['attachment']['preview']
    assert tg.process_inbound(evt) is False


def test_greeting_and_ack_once_each_for_two_chats(setup):
    c, codes, _ = setup
    headers = login(c, codes, 'buyer@example.com')
    for kind in ['support','cooperation']:
        url=f'/api/v1/account/messages?kind={kind}&with_greeting=true'
        one=c.get(url,headers=headers).json()['items']
        two=c.get(url,headers=headers).json()['items']
        assert len(one)==len(two)==1
        assert one[0]['id']==two[0]['id']
        assert one[0]['text']=='привет, что тебя беспокоит?'
        c.post('/api/v1/account/messages',headers=headers,json={
            'kind':kind,'text':'First message','auto_ack':True})
        c.post('/api/v1/account/messages',headers=headers,json={
            'kind':kind,'text':'Second message','auto_ack':True})
        data=c.get(url,headers=headers).json()['items']
        assert len(data)==4
        assert data[0]['text']=='привет, что тебя беспокоит?'
        assert len([m for m in data if 'запрос передан' in m['text']]) == 1
        assert [m['text'] for m in data if m['staff'] is False]==['First message','Second message']


def test_anonymous_manager_reply_from_approved_group_is_accepted(setup, monkeypatch):
    """Telegram allows anonymous admins to post as the private supergroup."""
    client, codes, sessions = setup
    alice = login(client, codes, 'alice@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    client.post('/api/v1/account/messages', headers=alice,
                json={'kind':'support', 'text':'Нужна помощь', 'auto_ack':True})
    with sessions() as db:
        buyer = db.scalar(select(account.Buyer).where(account.Buyer.email == 'alice@example.com'))
        db.add(tg.TelegramTopic(buyer=buyer.id,kind='support',chat_id='-100999',thread_id=101))
        db.commit()
    evt = {'message': {'chat': {'id':-100999, 'type':'supergroup'},
                       'message_id': 707, 'message_thread_id': 101, 'text': 'Отвечаю вам',
                       'from': {'is_bot':True},
                       'sender_chat': {'id':-100999, 'type':'supergroup'}}}
    assert tg.process_inbound(evt) is True
    assert tg.process_inbound(evt) is False
    history = client.get('/api/v1/account/messages?kind=support', headers=alice).json()['items']
    assert history[-1]['staff'] is True and history[-1]['text'] == 'Отвечаю вам'
    # An anonymous admin of some *other* chat is never authorized.
    evt2 = {'message':dict(evt['message'],message_id=708,
                            sender_chat={'id':-1001, 'type':'supergroup'})}
    assert tg.process_inbound(evt2) is False


def test_manager_reply_can_inherit_topic_from_replied_message(setup, monkeypatch):
    client, codes, sessions = setup
    headers = login(client, codes, 'buyer@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    with sessions() as db:
        buyer = db.scalar(select(account.Buyer).where(account.Buyer.email=='buyer@example.com'))
        db.add(tg.TelegramTopic(buyer=buyer.id,kind='cooperation',chat_id='-100999',thread_id=102))
        db.commit()
    evt = {'message': {'chat':{'id':-100999,'type':'supergroup'},
                       'message_id':801, 'text':'Получили заявку',
                       'reply_to_message': {'message_thread_id':102},
                       'from':{'is_bot':False}}}
    assert tg.process_inbound(evt) is True
    history = client.get('/api/v1/account/messages?kind=cooperation',headers=headers).json()['items']
    assert history[-1]['text'] == 'Получили заявку'


def test_private_topic_diagnostic_command_reports_mapping(setup, monkeypatch):
    client, codes, sessions = setup
    token = login(client, codes, 'operator@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg,'SessionLocal', sessions)
    client.post('/api/v1/account/messages', headers=token,
        json={'kind':'support','text':'test','auto_ack':True})
    with sessions() as db:
        b = db.scalar(select(account.Buyer).where(account.Buyer.email=='operator@example.com'))
        db.add(tg.TelegramTopic(buyer=b.id,kind='support',chat_id='-100999',thread_id=333))
        db.commit()
    delivered=[]
    monkeypatch.setattr(tg,'tg_api',lambda method, payload, **kwargs: delivered.append((method,payload)))
    incoming={'message':{'chat':{'id':-100999,'type':'supergroup'},
        'message_id':999,'message_thread_id':333,'from':{'is_bot':False},
        'text':'/sadohod_test@sadohod_support_bot'}}
    assert tg.process_inbound(incoming) is False
    assert delivered[0][0]=='sendMessage'
    assert 'да' in delivered[0][1]['text']
    assert delivered[0][1]['message_thread_id']==333
    assert all(x['text']!='/sadohod_test@sadohod_support_bot' for x in
        client.get('/api/v1/account/messages?kind=support',headers=token).json()['items'])


def test_poll_loop_ingests_manager_reply_and_advances_checkpoint(setup, monkeypatch):
    """Verify the real polling route, not just process_inbound() in isolation."""
    client, codes, sessions = setup
    token = login(client, codes, 'poll@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    client.post('/api/v1/account/messages', headers=token,
                json={'kind':'support','text':'Помогите','auto_ack':True})
    with sessions() as db:
        buyer = db.scalar(select(account.Buyer).where(account.Buyer.email=='poll@example.com'))
        db.add(tg.TelegramTopic(buyer=buyer.id,kind='support',chat_id='-100999',thread_id=545))
        db.commit()
    event = {'update_id':20234, 'message': {
        'chat':{'id':-100999,'type':'supergroup'}, 'message_id':1234,
        'message_thread_id':545, 'from':{'is_bot':False},
        'text':'Менеджер отвечает через тему Telegram'}}
    offsets=[]
    def fake_api(method, payload, **kw):
        assert method=='getUpdates'
        offsets.append(payload['offset'])
        return [event] if payload['offset']<=event['update_id'] else []
    monkeypatch.setattr(tg,'tg_api',fake_api)
    assert tg.poll_once()==1
    assert tg.poll_once()==0
    assert offsets==[0,20235]
    history=client.get('/api/v1/account/messages?kind=support',headers=token).json()['items']
    assert [x['text'] for x in history].count('Менеджер отвечает через тему Telegram')==1
    with sessions() as db:
        health=db.get(tg.TelegramBridgeHealth,'worker')
        assert health is not None and health.poll_count==2 and health.last_reply_at>0


def test_document_upload_has_no_caption_and_still_shows_author(setup, monkeypatch):
    import base64
    c, codes, sessions = setup
    auth = login(c, codes, 'doc@example.com')
    assert c.post('/api/v1/account/profile',headers=auth,
        json={'name':'Поставщик\nПоддержка'}).status_code == 200
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg, 'SessionLocal', sessions)
    payload = {'kind':'cooperation','filename':'contract.pdf',
      'data':base64.b64encode(b'%PDF-1.4\n%%EOF').decode(),
      'text':'Эта подпись не должна оказаться у документа', 'auto_ack':True}
    assert c.post('/api/v1/account/messages/attachment', headers=auth,
       json=payload).status_code == 200
    actions=[]
    def api(method, data, **kw):
        actions.append((method,data))
        return {'message_thread_id':700} if method=='createForumTopic' else {'message_id':77}
    def upload(method, fields, body, name, mime):
        actions.append((method,fields,name,mime))
        assert body.startswith(b'%PDF-')
    monkeypatch.setattr(tg,'tg_api',api)
    monkeypatch.setattr(tg,'tg_upload',upload)
    assert tg.send_pending()==1
    txt = next(item[1]['text'] for item in actions if item[0]=='sendMessage')
    assert txt=='Имя: Поставщик Поддержка\nEmail: doc@example.com'
    doc = next(item for item in actions if item[0]=='sendDocument')
    assert doc[2]=='contract.pdf'
    assert 'caption' not in doc[1]
    assert not any('Эта подпись' in str(a) for a in actions)


def test_user_header_uses_current_profile_data_on_next_message(setup, monkeypatch):
    c,codes,sessions=setup
    headers=login(c,codes,'email@example.com')
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', '1:FAKE_FOR_TEST')
    monkeypatch.setenv('TELEGRAM_GROUP_ID', '-100999')
    monkeypatch.setattr(tg,'SessionLocal',sessions)
    events=[]
    def api(method,payload,**kw):
        events.append((method,payload))
        return {'message_thread_id':50} if method=='createForumTopic' else {'message_id':100}
    monkeypatch.setattr(tg,'tg_api',api)
    c.post('/api/v1/account/messages',headers=headers,
        json={'kind':'support','text':'сначала'})
    tg.send_pending()
    assert 'Не указано' in events[-1][1]['text']
    assert c.post('/api/v1/account/profile',headers=headers,
        json={'name':'Новое имя'}).status_code == 200
    c.post('/api/v1/account/messages',headers=headers,
        json={'kind':'support','text':'потом'})
    tg.send_pending()
    assert 'Имя: Новое имя' in events[-1][1]['text']
    assert 'Email: email@example.com' in events[-1][1]['text']
