
// This is an API-connected preview. No fabricated search results.
let products=[], sellers={}, cats=['Все'], route='home', activeCategory='Все', q='', image=null, selectedFile=null, results=[], searchBusy=false, searchError='', searchNotice='', searchMethod='visual_descriptor', searchBackend='classic', photoDimensions=null, cropArea=null;
let searchCategory='Все', searchThreshold='', serverVersion='0.7.0';
const view=document.getElementById('view'),nav=document.getElementById('nav');
const money=n=>new Intl.NumberFormat('ru-RU').format(n)+' ₽';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pimage=p=>p.image;
const head=()=>`<header class="header"><button class="brand" onclick="go('home')">садоход.</button><span class="tag">v${esc(serverVersion)}</span></header>`;
const notice=(s='Каталог содержит учебные карточки и добавленные товары. Проверяйте цену и наличие у продавца.')=>`<div class="notice"><span>ⓘ</span><span>${esc(s)}</span></div>`;
const card=p=>`<div class="card" role="button" tabindex="0" onclick="go('product:${esc(p.id)}')"><img src="${esc(pimage(p))}" alt="Демонстрационное изображение"><div class="price">${money(p.price)}</div><div class="name">${esc(p.title)}</div><div class="category">${esc(p.category)}</div></div>`;
const grid=ps=>ps.length?`<div class="products">${ps.map(card).join('')}</div>`:`<div class="empty">Ничего не нашлось.<br>Попробуйте другой запрос.</div>`;
const chips=mode=>`<div class="chips">${cats.slice(mode==='home'?1:0).map(c=>`<button class="chip ${activeCategory===c&&mode!=='home'?'active':''}" onclick="selectCategory(decodeURIComponent('${encodeURIComponent(c)}'))">${esc(c)}</button>`).join('')}</div>`;
const toolbar=title=>`<div class="topbar"><button class="back" onclick="historyBack()">←</button><span>${esc(title)}</span></div>`;
// Keep navigation separate from photo/search state. Browser Back and the UI arrow agree.
let navIndex=0;
const pageScroll=new Map();
function rememberScroll(){pageScroll.set(navIndex,view.scrollTop)}
function restoreRoute(next,index){route=next;navIndex=index;render();view.scrollTop=pageScroll.get(index)||0}
function go(next){
 if(route===next)return;
 rememberScroll();navIndex++;pageScroll.delete(navIndex);
 history.pushState({sadohod:true,route:next,index:navIndex},'', '#'+encodeURIComponent(next));
 restoreRoute(next,navIndex);
}
function historyBack(){if(navIndex>0)history.back();else go('home')}
window.addEventListener('popstate',e=>{
 rememberScroll();const state=e.state;
 if(state?.sadohod){restoreRoute(state.route,state.index)}
});
history.replaceState({sadohod:true,route:'home',index:0},'', '#home');
function selectCategory(c){activeCategory=c;if(route==='home')go('catalog');else render()}
function filter(){q=document.getElementById('query')?.value||'';const caret=document.getElementById('query')?.selectionStart;render();document.getElementById('query')?.focus();document.getElementById('query')?.setSelectionRange(caret,caret)}
function navbar(){const visible=['home','catalog'].includes(route);nav.style.display=visible?'grid':'none';nav.innerHTML=visible?`<button class="${route==='home'?'active':''}" onclick="go('home')"><span>⌗</span>Поиск</button><button class="${route==='catalog'?'active':''}" onclick="go('catalog')"><span>▦</span>Каталог</button>`:''}
async function apiJson(path){const r=await fetch(path);if(!r.ok)throw new Error('Ошибка сервера '+r.status);return r.json()}
async function loadCatalog(){let items=[];for(let offset=0;;offset+=500){const page=await apiJson('/api/v1/products?limit=500&offset='+offset);items.push(...page.items);if(page.items.length<500)return {items}}}
async function bootstrap(){
  try {
    const [catalog, categories, health] = await Promise.all([loadCatalog(),apiJson('/api/v1/categories'),apiJson('/health')]);
    const previousScroll=view.scrollTop;products=catalog.items.sort((a,b)=>Number(b.id.startsWith('photo-'))-Number(a.id.startsWith('photo-')));cats=categories.items;searchBackend=health.search_backend;serverVersion=health.version;render();view.scrollTop=previousScroll;
  } catch(e) {
    view.innerHTML=head()+`<div class="content"><h1 class="pagehead">Нет связи с API.</h1><p class="sub">${esc(e.message)}</p><p class="sub">Запусти сервер командой <code>docker compose up --build</code>, затем открой страницу по адресу <code>http://127.0.0.1:8000/preview/live.html</code>.</p><button class="primary" onclick="bootstrap()">Повторить попытку →</button></div>`;
  }
}
async function runSearch(){
 if(!selectedFile || searchBusy)return;
 searchBusy=true;searchError='';results=[];searchNotice='';go('results');
 try {
  const form=new FormData();form.append('file',selectedFile,selectedFile.name);
  if(cropArea){const c=cropArea;form.append('crop',[c.x,c.y,c.w,c.h].map(n=>n.toFixed(6)).join(','));}
  const params=new URLSearchParams();
  if(searchCategory!=='Все')params.set('category',searchCategory);
  if(searchThreshold!=='')params.set('min_score',searchThreshold);
  const r=await fetch('/api/v1/search/image?'+params,{method:'POST',body:form});
  const d=await r.json();
  if(!r.ok) throw new Error(typeof d.detail==='string'?d.detail:'Ошибка поиска '+r.status);
  results=d.items.map(i=>i.product);
  for(const p of results){const n=products.findIndex(x=>x.id===p.id);if(n<0)products.push(p);else products[n]=p;}
  searchNotice=d.notice;searchMethod=d.method;searchBackend=d.method==='openclip_image_embedding'?'clip':'classic';
 }catch(e){searchError=e.message||'Ошибка поиска'}
 finally{searchBusy=false;render()}
}
async function openSeller(id){
 try { const origin=route;const s=await apiJson('/api/v1/sellers/'+encodeURIComponent(id));sellers[id]=s;if(route===origin)go('seller:'+id); }
 catch(e){alert('Не удалось открыть продавца: '+e.message)}
}
function resetCrop(){cropArea=null;render()}
function cropStageMarkup(){
 if(!image)return '<div class="upload"><svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="5" y="10" width="38" height="30" rx="3"/><circle cx="17" cy="20" r="4"/><path d="M6 34l11-10 8 7 7-8 11 12"/></svg>Здесь появится твоя фотография</div>';
 const dim=photoDimensions||{w:1,h:1};const ratio=dim.w/dim.h;
 const rect=cropArea?`<div class="crop-highlight" style="left:${cropArea.x*100}%;top:${cropArea.y*100}%;width:${cropArea.w*100}%;height:${cropArea.h*100}%"></div>`:'';
 return `<div class="upload"><div class="crop-stage" id="crop-stage" style="aspect-ratio:${dim.w}/${dim.h};width:min(100%,${Math.min(300*ratio,2000)}px)"><img src="${image}" alt="Выбранная фотография">${rect}</div></div><div class="crop-actions"><span>Выдели вещь: проведи пальцем или мышью по фото</span><button type="button" onclick="resetCrop()">Сбросить</button></div>`;
}
function installCropHandlers(){
 const stage=document.getElementById('crop-stage');if(!stage)return;
 let start=null;
 const coords=e=>{const r=stage.getBoundingClientRect();return {x:Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(e.clientY-r.top)/r.height))}};
 stage.addEventListener('pointerdown',e=>{start=coords(e);stage.setPointerCapture(e.pointerId);});
 stage.addEventListener('pointermove',e=>{if(!start)return;const end=coords(e);const x=Math.min(start.x,end.x),y=Math.min(start.y,end.y),w=Math.abs(start.x-end.x),h=Math.abs(start.y-end.y);
  const rect=stage.querySelector('.crop-highlight')||stage.appendChild(Object.assign(document.createElement('div'),{className:'crop-highlight'}));
  Object.assign(rect.style,{left:(x*100)+'%',top:(y*100)+'%',width:(w*100)+'%',height:(h*100)+'%'});
 });
 stage.addEventListener('pointerup',e=>{if(!start)return;const end=coords(e),x=Math.min(start.x,end.x),y=Math.min(start.y,end.y),w=Math.abs(start.x-end.x),h=Math.abs(start.y-end.y);start=null;cropArea=w>=.05&&h>=.05?{x,y,w,h}:null;render();});
 stage.addEventListener('pointercancel',()=>{start=null;render();});
}
function render(){navbar();let html='';
if(route==='home') html=head()+`<div class="content"><div class="over">ТВОЙ ПОИСК / МОСКВА</div><h1 class="pagehead">Нашёл вещь?<br>Найди её<br>на Садоводе.</h1><p class="sub">Покажи фотографию — узнавай, в каком павильоне искать похожий товар.</p><button class="feature" onclick="go('search')"><div class="featuretop"><span>⌗</span><span>↗</span></div><div><small>ПОИСК ПО ИЗОБРАЖЕНИЮ</small><strong>Загрузить фотографию</strong></div></button><div class="section"><div class="over">ПОСМОТРЕТЬ КАТАЛОГ</div><button class="link" onclick="activeCategory='Все';go('catalog')">Все товары ↗</button></div>${chips('home')}<div class="section"><div class="over">ПОДБОРКА / ДЕМО</div></div>${grid(products.slice(0,4))}${notice()}</div>`;
else if(route==='catalog'){const ps=products.filter(p=>(activeCategory==='Все'||p.category===activeCategory)&&(!q||p.title.toLowerCase().includes(q.toLowerCase())||p.category.toLowerCase().includes(q.toLowerCase())));html=head()+`<div class="content"><div class="over">САДОВОД / КАТАЛОГ</div><h1 class="pagehead">Каталог</h1><input class="searchinput" id="query" value="${esc(q)}" oninput="filter()" placeholder="Найти по названию"><div style="height:19px"></div>${chips('catalog')}<div class="section"><span class="count">Товаров: ${ps.length}</span><button class="link" onclick="go('search')">⌗ По фото</button></div>${grid(ps)}${notice()}</div>`}
else if(route==='search')html=toolbar('Поиск по фото')+`<div class="content" style="padding-top:18px"><div class="over">ШАГ 01 / ИЗОБРАЖЕНИЕ</div><h1 class="pagehead" style="font-size:36px">Что ищем?</h1><p class="sub">Загрузи фото и при необходимости обведи нужную вещь. ${searchBackend==='clip'?'OpenCLIP сравнит изображения по нейросетевым признакам.':'Сейчас включён базовый поиск по цветам и контурам.'}</p>${cropStageMarkup()}<label class="smallhint">Категория вещи<select class="searchinput" onchange="searchCategory=this.value">${cats.map(c=>`<option value="${esc(c)}" ${searchCategory===c?'selected':''}>${esc(c)}</option>`).join('')}</select></label><label class="smallhint">Минимальное сходство<select class="searchinput" onchange="searchThreshold=this.value"><option value="" ${searchThreshold===''?'selected':''}>Без порога</option>${['0.2','0.3','0.4','0.5'].map(v=>`<option value="${v}" ${searchThreshold===v?'selected':''}>${v} — экспериментальный порог</option>`).join('')}</select></label><p class="smallhint">Порог — коэффициент сходства, не вероятность. Его значения ещё не откалиброваны.</p><div class="uploadbtns"><button class="outline" onclick="document.getElementById('file').click()">▧ &nbsp; Из галереи</button><button class="outline" onclick="document.getElementById('file').click()">◎ &nbsp; Камера / файл</button></div><div style="height:25px"></div><button class="primary" ${image?'':'disabled'} onclick="runSearch()">Найти похожие товары <span>→</span></button>${notice(searchBackend==='clip'?'Режим OpenCLIP включён. Сходство не означает точное совпадение.':'Базовый режим: цвет, композиция и контуры.')}</div>`;
else if(route==='results')html=toolbar('Результаты')+`<div class="content" style="padding-top:17px"><div class="over">ШАГ 02 / ВЫДАЧА</div><h1 class="pagehead" style="font-size:36px">Похожие товары.</h1><div class="selected"><img src="${image||''}" alt="Запрос"><div><span class="over">ТВОЙ ЗАПРОС</span><p>${cropArea?'Ищем выделенную область':'Ищем по всему фото'}</p></div><button class="link" onclick="go('search')" style="margin-left:auto;font-size:24px">↻</button></div>${searchBusy?`<div class="notice">Анализируем фотографию и сравниваем с каталогом…</div>`:searchError?`<div class="notice">${esc(searchError)} <button class="link" onclick="runSearch()">Повторить</button></div>`:notice(searchNotice||'Результаты ранжированы по визуальной близости, это не гарантия идентичности товара.')+`<div class="section"><div class="over">ПОХОЖИЕ ТОВАРЫ</div><span class="count">${results.length} шт.</span></div>${grid(results)}`}</div>`;
else if(route.startsWith('product:')){const p=products.find(x=>x.id===route.split(':')[1]);if(!p)return go('catalog');const o=p.offers?.[0],s=o?.seller;html=toolbar('Товар')+`<img id="product-photo" class="imageFull" src="${esc(pimage(p))}" alt="${esc(p.title)}"><div class="content" style="padding-top:24px">${p.images?.length>1?`<div style="display:flex;gap:8px;overflow:auto;margin-bottom:20px">${p.images.map(url=>`<button class="outline" data-photo="${esc(url)}" style="padding:3px;min-width:70px"><img src="${esc(url)}" alt="Другой ракурс" style="width:64px;height:80px;object-fit:cover"></button>`).join('')}</div>`:''}<div class="over">${esc(p.category.toUpperCase())}</div><h1 class="pagehead" style="font-size:30px;line-height:1.1">${esc(p.title)}</h1><div style="font-weight:750;font-size:27px">${money(p.price)}</div><div class="divider"></div><div class="over">О ТОВАРЕ</div><p class="sub" style="color:var(--ink);margin-top:13px">${esc(p.description)}</p>${p.sizes?.length?`<p>Размеры: ${esc(p.sizes.join(', '))}</p>`:''}${p.colors?.length?`<p>Цвета: ${esc(p.colors.join(', '))}</p>`:''}<div class="section"><span class="over">ГДЕ НАЙТИ</span></div>${s?`<button class="sellerbox" data-seller-id="${esc(s.id)}"><span style="font-size:26px">▤</span><span style="flex:1"><strong>${esc(s.name)}</strong><br><span class="smallhint">${esc(sellerAddress(s))}</span></span><span>→</span></button>${sellerActions(s)}`:''}${notice(p.demo?'Учебная карточка: цена и продавец вымышлены.':'Товар добавлен через админку. Уточняйте наличие у продавца.')}</div>`}
else if(route.startsWith('seller:')){const id=route.slice(7),s=sellers[id];if(!s)return go('catalog');html=toolbar('Продавец')+`<div class="content seller-page"><div class="over">${s.demo?'УЧЕБНАЯ ТОРГОВАЯ ТОЧКА':'ТОРГОВАЯ ТОЧКА'}</div><h1 class="pagehead" style="font-size:36px">${esc(s.name)}</h1><div class="location"><strong>${esc(sellerAddress(s))}</strong></div>${s.contact?`<p class="sub contact-text">Контакты: ${esc(s.contact)}</p>`:'<p class="sub">Продавец пока не добавил контакты.</p>'}${sellerActions(s)}${s.demo?notice('Учебная карточка продавца: расположение и контакты могут быть вымышленными.'):notice('Уточните наличие и цену перед поездкой.')}<div class="section"><div class="over">ТОВАРЫ ПРОДАВЦА</div><span class="count">${s.products.length} шт.</span></div>${s.products.length?grid(s.products):'<div class="empty">У продавца пока нет опубликованных товаров.</div>'}</div>`}

view.innerHTML=html;
view.querySelectorAll('[data-seller-id]').forEach(b=>b.addEventListener('click',()=>openSeller(b.dataset.sellerId)));
view.querySelectorAll('[data-copy-address]').forEach(b=>b.addEventListener('click',()=>copyAddress(b)));
view.querySelectorAll('.card').forEach(b=>b.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();b.click()}}));
view.querySelectorAll('[data-photo]').forEach(button=>button.addEventListener('click',()=>{document.getElementById('product-photo').src=button.dataset.photo}));
if(route==='search')installCropHandlers();
}
document.getElementById('file').addEventListener('change',e=>{const file=e.target.files?.[0];if(!file)return;if(!['image/jpeg','image/png','image/webp'].includes(file.type)){alert('Выберите JPEG, PNG или WebP');return}if(file.size>8*1024*1024){alert('Файл должен быть меньше 8 МБ');return}if(image)URL.revokeObjectURL(image);selectedFile=file;image=URL.createObjectURL(file);cropArea=null;photoDimensions=null;const im=new Image();im.onload=()=>{photoDimensions={w:im.naturalWidth,h:im.naturalHeight};render()};im.src=image;render();e.target.value='' });
view.innerHTML='<div class="content">Загружаем каталог…</div>';bootstrap();


window.addEventListener('focus',()=>{if(!searchBusy)bootstrap()});
