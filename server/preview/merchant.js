'use strict';
const $ = id => document.getElementById(id);
const state = {token: null, email: '', shop: null, pavilions: [], products: []};
const isSecure = window.isSecureContext || ['127.0.0.1','localhost'].includes(location.hostname);
function node(tag, cls='', content='') {const e=document.createElement(tag);if(cls)e.className=cls;if(content!==undefined)e.textContent=String(content);return e;}
function append(parent,...children){for(const child of children)parent.appendChild(child);return parent;}
function note(message, bad=false){const p=$('message');p.hidden=false;p.className='notice'+(bad?' error':'');p.textContent=message;}
function clearNote(){$('message').hidden=true;}
function parseForm(form){return Object.fromEntries(new FormData(form));}
function parts(s){return String(s||'').split(',').map(x=>x.trim()).filter(Boolean);}
async function request(path, method='GET', data=null){
  let headers={};if(state.token)headers.Authorization='Bearer '+state.token;
  if(data && !(data instanceof FormData))headers['Content-Type']='application/json';
  const response=await fetch('/api/v1/'+path,{method,headers,body:data?(data instanceof FormData?data:JSON.stringify(data)):undefined,cache:'no-store'});
  let result={};try{result=await response.json();}catch{};
  if(!response.ok)throw Error(typeof result.detail==='string'?result.detail:'Ошибка сервера ('+response.status+')');
  return result;
}
function safe(fn){return async (...args)=>{clearNote();try{await fn(...args);}catch(e){note(e.message||'Ошибка соединения',true);}};}
function reset(){state.token=null;state.shop=null;$('exit').hidden=true;$('auth').hidden=false;$('application').hidden=true;$('cabinet').hidden=true;}
$('exit').onclick=()=>{reset();note('Вы вышли из кабинета.');};
$('refreshStatus').onclick=safe(load);
$('emailForm').addEventListener('submit',safe(async e=>{
 e.preventDefault();if(!isSecure)throw Error('Для входа с телефона требуется HTTPS. На компьютере можно открыть http://127.0.0.1:8000/preview/merchant.html');
 const values=parseForm(e.target);state.email=String(values.email).trim().toLowerCase();await request('auth/code','POST',{email:state.email});
 $('emailForm').hidden=true;$('codeForm').hidden=false;note('Код отправлен на '+state.email);
}));
$('codeForm').addEventListener('submit',safe(async e=>{
 e.preventDefault();const {code}=parseForm(e.target);const result=await request('auth/verify','POST',{email:state.email,code});
 state.token=result.token;$('auth').hidden=true;$('exit').hidden=false;await load();note('Вход выполнен.');
}));
async function load(){
 const profile=await request('merchant/me');state.shop=profile.shop;
 if(!state.shop){$('cabinet').hidden=true;$('application').hidden=false;const box=$('pendingApplication');box.replaceChildren();
  for(const item of profile.applications||[])append(box,node('div','notice',`Заявка «${item.shop_name}»: ${item.status}. ${item.note||''}`));
  return;
 }
 $('application').hidden=true;$('cabinet').hidden=false;$('shopName').textContent=state.shop.name;
 $('shopForm').elements.namedItem('name').value=state.shop.name;
 $('shopForm').elements.namedItem('contact').value=state.shop.contact||'';
 await refreshPavilions();await refreshProducts();
}
$('applyForm').addEventListener('submit',safe(async e=>{e.preventDefault();await request('merchant/applications','POST',parseForm(e.target));note('Заявка отправлена на проверку.');await load();}));
$('inviteForm').addEventListener('submit',safe(async e=>{e.preventDefault();await request('merchant/invitations/accept','POST',parseForm(e.target));note('Приглашение принято.');await load();}));
$('shopForm').addEventListener('submit',safe(async e=>{e.preventDefault();await request('merchant/shop','PUT',parseForm(e.target));note('Данные магазина сохранены.');await load();}));
$('pavilionForm').addEventListener('submit',safe(async e=>{e.preventDefault();await request('merchant/pavilions','POST',parseForm(e.target));e.target.reset();note('Павильон отправлен на проверку.');await refreshPavilions();}));
async function refreshPavilions(){
 const data=await request('merchant/pavilions');state.pavilions=data.items;
 const box=$('pavilionsList');box.replaceChildren();
 for(const p of data.items)append(box,append(node('div','item'),node('div','item-title',p.zone+' · '+p.code),node('div','minor','Подтверждён')));
 for(const p of data.requests)append(box,append(node('div','item'),node('div','item-title',p.zone+' · '+p.code),node('div','minor',p.status+(p.note?' · '+p.note:''))));
 if(!data.items.length&&!data.requests.length)append(box,node('p','muted','Павильонов пока нет.'));
}
$('toggleProductForm').onclick=()=>{$('productForm').hidden=!$('productForm').hidden;};
$('productForm').addEventListener('submit',safe(async e=>{
 e.preventDefault();const f=parseForm(e.target);
 await request('merchant/products','POST',{title:f.title,category:f.category,description:f.description,colors:parts(f.colors),sizes:parts(f.sizes)});
 e.target.reset();$('productForm').hidden=true;note('Черновик товара создан. Добавьте фотографии и предложения.');await refreshProducts();
}));
function action(label, handler, secondary=false){const b=node('button',secondary?'secondary':'',label);b.type='button';b.onclick=safe(handler);return b;}
async function refreshProducts(){
 const result=await request('merchant/products');state.products=result.items;
 const box=$('productsList');box.replaceChildren();
 if(!result.items.length){box.appendChild(node('p','muted','Пока нет товаров. Добавьте первый товар.'));return;}
 for(const p of result.items){
   const card=node('article','item');const top=node('div','item-top');append(top,node('div','item-title',p.title),node('span','tag',p.status));card.appendChild(top);
   append(card,node('div','minor',p.category+(p.note?' · '+p.note:'')));
   const media=node('div','media');for(const src of p.images){const img=document.createElement('img');img.src=src;img.alt=p.title;media.appendChild(img);}card.appendChild(media);
   const list=node('div');for(const l of p.listings){
     const line=node('div','listing');append(line,node('div','minor',(l.pavilion?l.pavilion.zone+' · '+l.pavilion.code:'Павильон')+' · '+l.price+' ₽ · '+l.status+' · '+l.sale_modes.map(x=>x==='retail'?'розница':'опт').join(', ')));
     const actions=node('div','actions');
     if(l.status!=='pending' && l.status!=='paused')actions.appendChild(action('Изменить цену',async()=>{
       if(line.querySelector('form'))return;
       const form=node('form','actions');
       const price=node('input');price.type='number';price.min='0';price.required=true;price.value=String(l.price);price.style.maxWidth='120px';
       const w=node('input');w.type='checkbox';w.checked=l.sale_modes.includes('wholesale');
       const r=node('input');r.type='checkbox';r.checked=l.sale_modes.includes('retail');
       const wlab=append(node('label'),node('span','','Опт'),w),rlab=append(node('label'),node('span','','Розница'),r);
       const save=node('button','','На проверку');save.type='submit';append(form,price,wlab,rlab,save);
       form.addEventListener('submit',safe(async e=>{e.preventDefault();const modes=[];if(w.checked)modes.push('wholesale');if(r.checked)modes.push('retail');
         await request('merchant/listings/'+l.id,'PUT',{pavilion_id:l.pavilion_id,price:Number(price.value),sale_modes:modes});
         note('Изменение отправлено на проверку.');await refreshProducts();}));line.appendChild(form);
     },true));
     if(l.status==='approved'||l.status==='pending')actions.appendChild(action('Снять с продажи',async()=>{await request('merchant/listings/'+l.id+'/pause','POST');await refreshProducts();},true));
     if(l.status==='paused')actions.appendChild(action('Вернуть на модерацию',async()=>{await request('merchant/listings/'+l.id+'/resume','POST');await refreshProducts();},true));
     line.appendChild(actions);list.appendChild(line);
   }card.appendChild(list);
   const actions=node('div','actions');
   if(['draft','rejected'].includes(p.status)){
     const upload=node('input');upload.type='file';upload.accept='image/jpeg,image/png,image/webp';upload.multiple=true;upload.style.maxWidth='235px';
     upload.onchange=safe(async()=>{const fd=new FormData();for(const file of upload.files)fd.append('files',file);await request('merchant/products/'+p.id+'/images','POST',fd);note('Фотографии добавлены.');await refreshProducts();});actions.appendChild(upload);
   }
   const availablePavilions=state.pavilions.filter(v=>!p.listings.some(l=>l.pavilion_id===v.id));
   if(p.status!=='pending' && availablePavilions.length){
     const form=node('form','actions');const select=node('select');select.name='pavilion_id';select.style.maxWidth='175px';
     for(const v of availablePavilions){const option=node('option','',''+v.zone+' · '+v.code);option.value=v.id;select.appendChild(option);}const price=node('input');price.type='number';price.name='price';price.min='0';price.required=true;price.placeholder='Цена, ₽';price.style.maxWidth='115px';
     const wholesale=node('input');wholesale.type='checkbox';wholesale.checked=true;const retail=node('input');retail.type='checkbox';retail.checked=true;
     const modes=append(node('label'),node('span','','Опт'),wholesale);const rmodes=append(node('label'),node('span','','Розница'),retail);
     const submit=node('button','','Распределить');submit.type='submit';append(form,select,price,modes,rmodes,submit);
     form.addEventListener('submit',safe(async e=>{e.preventDefault();const sale_modes=[];if(wholesale.checked)sale_modes.push('wholesale');if(retail.checked)sale_modes.push('retail');await request('merchant/products/'+p.id+'/listings','POST',{pavilion_id:select.value,price:Number(price.value),sale_modes});note('Предложение добавлено.');await refreshProducts();}));
     actions.appendChild(form);
   }
   if(['draft','rejected'].includes(p.status))actions.appendChild(action('Отправить на модерацию',async()=>{await request('merchant/products/'+p.id+'/submit','POST');note('Товар отправлен на проверку.');await refreshProducts();}));
   card.appendChild(actions);box.appendChild(card);
 }
}
for(const button of document.querySelectorAll('[data-tab]'))button.addEventListener('click',()=>{
 document.querySelectorAll('[data-tab]').forEach(b=>b.classList.toggle('active',b===button));
 for(const name of ['products','pavilions','shop'])$(name+'Tab').hidden=button.dataset.tab!==name;
});
if(!isSecure)note('Вход по email доступен только по HTTPS или на localhost компьютера. Не запрашивайте коды по локальному HTTP.',true);
