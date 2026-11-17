'use strict';
/* Single-page moderation console: no framework, no external CDNs, no innerHTML
   with untrusted data. All moderation happens through authenticated API calls. */
const $=id=>document.getElementById(id);
const API='/api/v1/moderation';
const kinds=['applications','pavilions','products','listings','reviews','reports','product_reports'];
const names={all:'Все заявки',applications:'Заявки продавцов',pavilions:'Павильоны',
  products:'Товары',listings:'Предложения',reviews:'Отзывы',reports:'Жалобы',
  product_reports:'Жалобы на товары',
  chats:'Обращения',history:'История решений'};
const typeName={applications:'ПРОДАВЕЦ',pavilions:'ПАВИЛЬОН',products:'ТОВАР',
  listings:'ПРЕДЛОЖЕНИЕ',reviews:'ОТЗЫВ',reports:'ЖАЛОБА',
  product_reports:'ЖАЛОБА НА ТОВАР'};
const state={token:sessionStorage.getItem('sadohod-moderator')||'',staff:null,
  section:'all',queue:{},history:[],chats:[],items:[],selected:null,
  activeThread:null,busy:false,confirm:null};
let noticeTimer=0;
function node(tag,cls,txt){const n=document.createElement(tag);if(cls)n.className=cls;if(txt!==undefined)n.textContent=String(txt);return n;}
function append(parent,...children){for(const c of children)if(c!==null&&c!==undefined)parent.appendChild(c);return parent;}
function fmt(t){if(!t)return 'Без даты';return new Date(Number(t)*1000).toLocaleString('ru-RU',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'});}
function short(t,max=120){t=String(t??'').trim();return t.length>max?t.slice(0,max)+'…':t;}
function toast(message,bad=false){const t=$('toast');t.textContent=message;t.classList.toggle('error',bad);t.hidden=false;clearTimeout(noticeTimer);noticeTimer=setTimeout(()=>t.hidden=true,4300);}
async function api(path,method='GET',body){
  const response=await fetch(API+path,{method,headers:{'Authorization':'Bearer '+state.token,
      'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),
    cache:'no-store',credentials:'same-origin'});
  let data={};try{data=await response.json();}catch{}
  if(!response.ok){if(response.status===401&&path!=='/login')signedOut('Сессия завершена. Войдите снова.');
    const info=data.detail;throw Error(typeof info==='string'?info:'Ошибка сервера '+response.status);}
  return data;
}
function signedOut(message=''){
  state.token='';state.staff=null;sessionStorage.removeItem('sadohod-moderator');
  $('workspace').hidden=true;$('loginScreen').hidden=false;
  $('loginPassword').value='';$('loginError').textContent=message;$('loginError').hidden=!message;
}
function signedIn(user){
  state.staff=user;$('staffName').textContent=user.display_name||user.username;
  $('staffInitial').textContent=(user.display_name||'М')[0].toUpperCase();
  $('loginScreen').hidden=true;$('workspace').hidden=false;
}
function identify(row,kind){return kind+':'+row.id;}
function label(row,kind){
  if(kind==='applications')return row.shop_name||'Новый продавец';
  if(kind==='pavilions')return (row.zone||'Сектор')+' · '+(row.code||'Павильон');
  if(kind==='products')return row.title||'Товар без названия';
  if(kind==='listings')return 'Предложение · '+(row.price??'—')+' ₽';
  if(kind==='reviews')return (row.seller_name||'Продавец')+' · '+row.rating+'/5';
  if(kind==='reports')return 'Жалоба на отзыв';
  if(kind==='product_reports')return row.title||'Жалоба на товар';
  if(kind==='chats')return (row.name||row.email||'Пользователь')+' · '+chatName(row.kind);
  return 'Заявка';
}
function supporting(row,kind){
  if(kind==='applications')return [row.email,row.zone,row.code].filter(Boolean).join(' · ');
  if(kind==='pavilions')return 'Продавец '+short(row.seller_id,18);
  if(kind==='products')return [row.category,short(row.description,60)].filter(Boolean).join(' · ');
  if(kind==='listings')return [row.pavilion?.zone,row.pavilion?.code,short(row.product_id,12)].filter(Boolean).join(' · ');
  if(kind==='reviews')return short(row.text||'Без текста',90);
  if(kind==='reports')return short(row.reason,90);
  if(kind==='product_reports')return short(row.reason,90);
  if(kind==='chats')return short(row.last_message,90);
  return '';
}
function chatName(kind){return ({support:'Поддержка',cooperation:'Сотрудничество',
  m_support:'Продавец · поддержка',m_cooperation:'Продавец · сотрудничество'})[kind]||kind;}
function allRows(){
  const rows=[];for(const kind of kinds)for(const row of(state.queue[kind]||[])){
    rows.push({...row,_kind:kind,_key:identify(row,kind)});
  }
  return rows.sort((a,b)=>(b.created_at||b.sent||0)-(a.created_at||a.sent||0));
}
function count(kind){return (state.queue[kind]||[]).length;}
function renderCounts(){
  const total=kinds.reduce((n,k)=>n+count(k),0);
  for(const el of document.querySelectorAll('[data-count]')){
    el.textContent=el.dataset.count==='all'?total:el.dataset.count==='chats'?state.chats.length:count(el.dataset.count);
  }
  $('metricAll').textContent=total;
  $('metricSellers').textContent=count('applications')+count('pavilions');
  $('metricProducts').textContent=count('products')+count('listings');
  $('metricReviews').textContent=count('reviews')+count('reports')+count('product_reports');
}
function refreshHead(){
  const section=state.section;
  $('pageTitle').textContent=names[section]||'Заявки';
  $('pageDescription').textContent=section==='history'?'Последние 100 решений с указанием сотрудника и причины.'
    :section==='chats'?'Диалоги покупателей и продавцов. Ответы пока остаются в Telegram.'
    :'Выберите заявку, проверьте детали и примите решение.';
  document.querySelectorAll('[data-section]').forEach(el=>el.classList.toggle('active',el.dataset.section===section));
  $('metrics').hidden=section==='history'||section==='chats';
  $('search').placeholder=section==='chats'?'Поиск по имени, почте или сообщению'
    :section==='history'?'Поиск по решению, модератору или ID'
    :'Поиск по названию, ID, продавцу или адресу';
}
function visibleRows(){
  let rows=state.section==='all'?allRows():state.section==='chats'
    ?state.chats.map(r=>({...r,_kind:'chats',_key:'chats:'+r.buyer_id+':'+r.kind,
        id:r.buyer_id,created_at:r.sent}))
    :state.section==='history'?state.history.map(r=>({...r,_kind:'history',_key:'history:'+r.id}))
    :(state.queue[state.section]||[]).map(r=>({...r,_kind:state.section,
       _key:identify(r,state.section)}));
  const q=$('search').value.trim().toLocaleLowerCase('ru');
  if(q)rows=rows.filter(row=>{
    const kind=row._kind;
    const index=[row.id,row.target_id,row.username,row.moderator,row.email,row.name,
      label(row,kind),supporting(row,kind),row.zone,row.code,row.seller_id,row.product_id,
      row.review_id,row.note,row.decision].filter(v=>v!==undefined&&v!==null).join(' ').toLocaleLowerCase('ru');
    return index.includes(q);
  });
  return rows;
}
function renderList(){
  refreshHead();renderCounts();const rows=visibleRows();state.items=rows;
  $('resultCount').textContent=rows.length+(state.section==='history'?' записей':state.section==='chats'?' диалогов':' заявок');
  const box=$('items');box.replaceChildren();
  $('empty').hidden=!!rows.length;
  if(!rows.length){state.selected=null;showEmptyDetail();return;}
  if(!rows.some(x=>x._key===state.selected))state.selected=rows[0]._key;
  for(const r of rows){
    if(r._kind==='history'){box.appendChild(historyCard(r));continue;}
    const card=node('button','queue-card'+(r._key===state.selected?' selected':''));card.type='button';
    const top=node('div','queue-top');
    append(top,node('span','type-pill',typeName[r._kind]||'ДИАЛОГ'),node('span','queue-time',fmt(r.created_at||r.sent)));
    append(card,top,node('div','queue-title',label(r,r._kind)),node('div','queue-meta',supporting(r,r._kind)));
    const foot=node('div','queue-foot');
    append(foot,node('span','',short(r.id,18)),node('strong','',r._kind==='chats'?'ПЕРЕПИСКА':'НА ПРОВЕРКЕ'));
    card.appendChild(foot);
    card.addEventListener('click',()=>{
      state.selected=r._key;renderList();
      if(matchMedia('(max-width:850px)').matches)$('details').scrollIntoView({behavior:'smooth',block:'start'});
    });
    box.appendChild(card);
  }
  renderDetail();
}
function historyCard(row){
  const card=node('button','history-card'+(row._key===state.selected?' selected':''));
  card.type='button';card.setAttribute('aria-label','История решения '+row.target_id);
  const line=node('div','queue-top');
  append(line,node('b','',row.moderator||'Модератор'),node('span','queue-time',fmt(row.created_at)));
  const decisionText=({approved:'Одобрено',rejected:'Отклонено',hide:'Скрыто',takedown:'Товар снят',dismiss:'Жалоба отклонена'})[row.decision]||row.decision;
  append(card,line,node('p','',(typeName[row.kind]||'ЗАПИСЬ')+' · '+decisionText+' · '+short(row.target_id,18)));
  if(row.note)card.appendChild(node('div','minor',row.note));
  card.addEventListener('click',()=>{state.selected=row._key;renderList();});
  return card;
}
function showEmptyDetail(){
  const d=$('details');d.replaceChildren();
  const box=node('div','detail-placeholder');
  append(box,node('span','placeholder-art','✓'),node('h3','','Очередь пуста'),
    node('p','','Когда появятся новые заявки, они будут здесь.'));
  d.appendChild(box);
}
function dl(container,pairs){
  const list=node('dl','detail-grid');for(const [key,val] of pairs){
    if(val===null||val===undefined||String(val).trim()==='')continue;
    append(list,node('dt','',key),node('dd','',val));
  }container.appendChild(list);
}
function section(parent,title){
  const s=node('div','detail-section');s.appendChild(node('h4','',title));parent.appendChild(s);return s;
}
function addPictures(parent,pictures){
  const safe=pictures.map(source=>{
    if(/^\/media\/products\/(?:uploads\/)?[a-zA-Z0-9_-]+\.(?:jpg|jpeg|png|webp)$/i.test(source))return source;
    if(/^[A-Za-z0-9+/=]{40,650000}$/.test(source))return 'data:image/jpeg;base64,'+source;
    return null;
  }).filter(Boolean);
  if(!safe.length)return;
  const s=section(parent,'Фотографии');
  const grid=node('div','photo-grid');
  for(const src of safe.slice(0,12)){
    const a=node('a','');a.href=src;a.target='_blank';a.rel='noopener noreferrer';
    const img=node('img','');img.src=src;img.alt='Фотография для проверки';img.loading='lazy';
    a.appendChild(img);grid.appendChild(a);
  }s.appendChild(grid);
}
function loadReviewPhotos(body,row){
  const path=row._kind==='reviews'?'/reviews/'+encodeURIComponent(row.id):
    '/reports/'+encodeURIComponent(row.id);
  api(path).then(data=>{
    if(state.selected!==row._key||!body.isConnected)return;
    addPictures(body,data.item?.photos||[]);
  }).catch(e=>{if(body.isConnected)
    body.appendChild(node('p','error-line','Не удалось загрузить фото: '+e.message));});
}
function renderDetail(){
  const r=state.items.find(x=>x._key===state.selected);
  if(!r){showEmptyDetail();return;}
  const d=$('details');d.replaceChildren();
  const body=node('div','detail-inner');
  const header=node('div','detail-eyebrow');
  append(header,node('span','',typeName[r._kind]||'ДИАЛОГ'),node('span','',fmt(r.created_at||r.sent)));
  body.appendChild(header);body.appendChild(node('h2','detail-title',label(r,r._kind)));
  const info=section(body,'Основная информация');
  if(r._kind==='applications')dl(info,[['Email',r.email],['Магазин / имя',r.shop_name],
    ['Сектор',r.zone],['Павильон',r.code],['Контакт',r.contact],['ID',r.id]]);
  if(r._kind==='pavilions')dl(info,[['Сектор',r.zone],['Павильон',r.code],
    ['Продавец',r.seller_id],['ID заявки',r.id]]);
  if(r._kind==='products'){
    dl(info,[['Название',r.title||'Не указано'],['Категория',r.category||'Без категории'],
      ['Статус',r.status],['ID',r.id]]);
    if(r.description)section(body,'Описание').appendChild(node('p','detail-text',r.description));
    addPictures(body,r.images||[]);
    if(r.listings?.length){const box=section(body,'Павильоны и цены');
      for(const l of r.listings)box.appendChild(node('div','detail-listing',
        (l.pavilion?.zone||'')+' · '+(l.pavilion?.code||'')+'  /  '+(l.price??'—')+' ₽  /  '+(l.sale_modes||[]).join(', ')));
    }
  }
  if(r._kind==='listings')dl(info,[['Павильон',(r.pavilion?.zone||'')+' '+(r.pavilion?.code||'')],
    ['Цена',String(r.price??'—')+' ₽'],['Режимы',r.sale_modes?.join(', ')||'—'],
    ['Товар',r.product_id],['ID',r.id]]);
  if(r._kind==='reviews'){
    dl(info,[['Продавец',r.seller_name],['Рейтинг',r.rating+' из 5'],
      ['Автор',r.name],['ID',r.id]]);
    section(body,'Текст отзыва').appendChild(node('div','detail-text',r.text||'Отзыв без текста'));
    if(r.photo_count)loadReviewPhotos(body,r);
  }
  if(r._kind==='reports'){
    dl(info,[['Продавец',r.seller_name],['Отзыв',r.review_id],['ID жалобы',r.id]]);
    section(body,'Причина жалобы').appendChild(node('div','detail-text',r.reason));
    if(r.review){const s=section(body,'Отзыв, на который пожаловались');
      dl(s,[['Оценка',r.review.rating+' из 5'],['Автор',r.review.name],
        ['Статус',r.review.moderation_status]]);
      s.appendChild(node('div','detail-text',r.review.text||'Без текста'));
      if(r.review.photo_count)loadReviewPhotos(body,r);
    }
  }
  if(r._kind==='product_reports'){
    dl(info,[['Товар',r.title],['ID товара',r.product_id],['ID жалобы',r.id]]);
    section(body,'Причина жалобы').appendChild(node('div','detail-text',r.reason));
    addPictures(body,r.images||[]);
  }
  if(r._kind==='history'){
    dl(info,[['Модератор',r.moderator],['Тип',typeName[r.kind]||r.kind],
      ['Действие',r.decision],['ID заявки',r.target_id]]);
    if(r.note)section(body,'Комментарий').appendChild(node('p','detail-text',r.note));
  }
  if(r._kind==='chats'){
    dl(info,[['Email',r.email],['Имя',r.name||'Не указано'],['Раздел',chatName(r.kind)]]);
    const s=section(body,'Последние сообщения');
    const lines=node('div','chat-messages');s.appendChild(lines);
    lines.appendChild(node('div','subtle','Загрузка диалога…'));
    api('/chats/'+encodeURIComponent(r.buyer_id)+'/'+encodeURIComponent(r.kind)).then(data=>{
      if(state.selected!==r._key)return;lines.replaceChildren();
      for(const m of data.items||[]){const b=node('div','chat-line'+(m.staff?' staff':''));
        append(b,node('div','',m.text||'Вложение'),node('small','',fmt(m.sent)));
        lines.appendChild(b);
      }
      if(!lines.children.length)lines.appendChild(node('p','subtle','Сообщений нет'));
    }).catch(e=>{lines.replaceChildren(node('p','error-line',e.message));});
    body.appendChild(node('p','chat-info','Ответы менеджеров продолжают отправляться через Telegram. В этой панели переписка доступна для просмотра.'));
  }
  d.appendChild(body);
  if(kinds.includes(r._kind)){
    const actions=node('div','detail-actions');
    if(r._kind==='reports'){
      append(actions,decisionButton('Скрыть отзыв','primary',()=>confirmDecision(r,'hide')),
        decisionButton('Отклонить жалобу','secondary',()=>confirmDecision(r,'dismiss')));
    }else if(r._kind==='product_reports'){
      append(actions,decisionButton('Снять товар','primary',()=>confirmDecision(r,'hide')),
        decisionButton('Отклонить жалобу','secondary',()=>confirmDecision(r,'dismiss')));
    }else{
      append(actions,decisionButton('Одобрить','primary',()=>confirmDecision(r,'approved')),
        decisionButton('Отклонить','secondary',()=>confirmDecision(r,'rejected')));
    }
    d.appendChild(actions);d.appendChild(node('div','detail-note',
      ['reports','product_reports'].includes(r._kind)?'Жалоба будет закрыта. Действие записывается в историю.'
      :'Действие применяется к существующим данным и записывается в историю модерации.'));
  }
}
function decisionButton(text,cls,fn){const b=node('button',cls,text);b.type='button';b.onclick=fn;return b;}
function confirmDecision(row,action){
  state.confirm={row,action};
  const reject=action==='rejected',productReport=row._kind==='product_reports';
  const report=row._kind==='reports'||productReport;
  $('confirmKicker').textContent=report?'РАССМОТРЕНИЕ ЖАЛОБЫ':'РЕШЕНИЕ ПО ЗАЯВКЕ';
  $('confirmTitle').textContent=productReport?(action==='hide'?'Снять товар с публикации?':'Отклонить жалобу?')
    :report?(action==='hide'?'Скрыть отзыв?':'Отклонить жалобу?')
    :reject?'Отклонить заявку?':'Одобрить заявку?';
  $('confirmDescription').textContent=productReport&&action==='hide'?'Товар исчезнет из каталога. Продавец получит уведомление с причиной.'
    :report?'Решение сохранится в истории модерации.'
    :reject?'Укажите, что именно нужно исправить. Причину увидит заявитель.'
    :'Проверьте сведения перед подтверждением. Решение изменит статус заявки.';
  $('reasonWrap').hidden=!(reject||(productReport&&action==='hide'));
  $('categoryWrap').hidden=!(row._kind==='products'&&!reject);
  $('categoryInput').value=row.category&&row.category!=='Без категории'?row.category:'';
  $('reason').value='';$('confirmError').hidden=true;
  $('submitConfirm').textContent=productReport?(action==='hide'?'Снять с публикации':'Закрыть жалобу')
    :report?(action==='hide'?'Скрыть':'Закрыть жалобу')
    :reject?'Отклонить заявку':'Одобрить заявку';
  $('confirmOverlay').hidden=false;
  if(reject||(productReport&&action==='hide'))$('reason').focus();else $('submitConfirm').focus();
}
function closeDialog(){state.confirm=null;$('confirmOverlay').hidden=true;}
async function submitDecision(){
  if(state.busy||!state.confirm)return;
  const {row,action}=state.confirm;
  const note=$('reason').value.trim();
  if(action==='rejected'&&note.length<3){
    $('confirmError').textContent='Напишите причину отклонения (не менее 3 символов).';
    $('confirmError').hidden=false;$('reason').focus();return;
  }
  if(row._kind==='product_reports'&&action==='hide'&&note.length<5){
    $('confirmError').textContent='Напишите причину снятия товара (не менее 5 символов).';
    $('confirmError').hidden=false;$('reason').focus();return;
  }
  if(row._kind==='products'&&action==='approved'&&!$('categoryInput').value.trim()){
    $('confirmError').textContent='Укажите категорию товара.';
    $('confirmError').hidden=false;$('categoryInput').focus();return;
  }
  state.busy=true;$('submitConfirm').disabled=true;
  try{
    if(row._kind==='reports')await api('/reports/'+encodeURIComponent(row.id)+'/resolve','POST',
      {decision:action,note});
    else if(row._kind==='product_reports')await api('/product-reports/'+encodeURIComponent(row.id)+'/resolve','POST',
      {decision:action,note});
    else await api('/'+row._kind+'/'+encodeURIComponent(row.id)+'/decision','POST',
      {decision:action,note,category:row._kind==='products'&&action==='approved'?
        $('categoryInput').value.trim():null});
    closeDialog();state.selected=null;
    await reload();toast('Решение сохранено.');
  }catch(e){$('confirmError').textContent=e.message;$('confirmError').hidden=false;}
  finally{state.busy=false;$('submitConfirm').disabled=false;}
}
async function reload(){
  const result=await Promise.all([api('/queue'),api('/chats')]);
  state.queue=result[0];state.chats=result[1].items||[];
  if(state.section==='history')state.history=(await api('/history')).items||[];
  $('updatedAt').textContent='Обновлено '+new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'});
  $('liveState').classList.remove('is-error');
  renderList();
}
async function navigate(section){
  state.section=section;state.selected=null;$('search').value='';
  try{if(section==='history')state.history=(await api('/history')).items||[];renderList();}
  catch(e){toast(e.message,true);}
}
$('loginForm').addEventListener('submit',async event=>{
  event.preventDefault();const btn=$('loginButton');btn.disabled=true;
  $('loginError').hidden=true;
  try{
    const r=await fetch(API+'/login',{method:'POST',
      headers:{'Content-Type':'application/json'},cache:'no-store',
      body:JSON.stringify({username:$('loginUser').value,password:$('loginPassword').value})});
    const data=await r.json();
    if(!r.ok)throw Error(typeof data.detail==='string'?data.detail:'Ошибка входа');
    state.token=data.token;sessionStorage.setItem('sadohod-moderator',state.token);
    $('loginPassword').value='';signedIn(data.user);await reload();
  }catch(e){$('loginError').textContent=e.message;$('loginError').hidden=false;}
  finally{btn.disabled=false;}
});
$('logout').onclick=async()=>{try{await api('/logout','POST');}catch{}signedOut();};
$('navigation').addEventListener('click',event=>{
  const btn=event.target.closest('[data-section]');if(btn)navigate(btn.dataset.section);
});
document.querySelectorAll('.side-group [data-section]').forEach(btn=>{
  if(btn.parentElement.id!=='navigation')btn.addEventListener('click',()=>navigate(btn.dataset.section));
});
$('search').addEventListener('input',renderList);
$('refresh').addEventListener('click',()=>reload().then(()=>toast('Очередь обновлена.')).catch(e=>toast(e.message,true)));
$('closeConfirm').onclick=closeDialog;$('cancelConfirm').onclick=closeDialog;
$('submitConfirm').onclick=submitDecision;
$('confirmOverlay').addEventListener('click',e=>{if(e.target===$('confirmOverlay'))closeDialog();});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('confirmOverlay').hidden)closeDialog();});
setInterval(()=>{if(state.token&&!document.hidden&&$('confirmOverlay').hidden)
  reload().catch(()=>{$('liveState').classList.add('is-error');});},45000);
if(state.token){api('/me').then(data=>{signedIn(data.user);return reload();})
  .catch(()=>signedOut('Нужно войти повторно.'));}
