'use strict';
const $=id=>document.getElementById(id);
const BASE='/api/v1/admin/moderators';
let adminKey='',once='';
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=String(text);return n;}
function announce(message,error=false){$('teamNotice').textContent=message;$('teamNotice').hidden=false;$('teamNotice').style.color=error?'#a42124':'';}
async function req(path='',method='GET',body){
  const r=await fetch(BASE+path,{method,cache:'no-store',
    headers:{'Authorization':'Bearer '+adminKey,'Content-Type':'application/json'},
    body:body===undefined?undefined:JSON.stringify(body)});
  const data=await r.json().catch(()=>({}));
  if(!r.ok)throw Error(typeof data.detail==='string'?data.detail:'Ошибка '+r.status);
  return data;
}
async function refresh(){
  const data=await req();const box=$('staffList');box.replaceChildren();
  $('staffCount').textContent='('+data.items.length+')';
  if(!data.items.length){box.appendChild(el('p','subtle','Модераторов ещё нет. Создайте первый доступ выше.'));return;}
  for(const staff of data.items){
    const row=el('div','team-row');const who=el('div','team-person');
    who.appendChild(el('strong','',staff.display_name));
    who.appendChild(el('small','',staff.username+' · '+new Date(staff.created_at*1000).toLocaleDateString('ru-RU')));
    const state=el('span','team-state'+(staff.enabled?'':' off'),staff.enabled?'Работает':'Доступ закрыт');
    const actions=el('div','team-actions');
    const flip=el('button','secondary',staff.enabled?'Отключить':'Включить');flip.type='button';
    flip.onclick=async()=>{
      if(!confirm(staff.enabled?'Отключить доступ '+staff.display_name+'? Все его сеансы будут завершены.':'Включить доступ '+staff.display_name+'?'))return;
      flip.disabled=true;
      try{await req('/'+encodeURIComponent(staff.id),'PUT',{enabled:!staff.enabled});await refresh();announce('Статус сотрудника изменён.');}
      catch(e){announce(e.message,true);}finally{flip.disabled=false;}
    };
    const reset=el('button','secondary','Новый пароль');reset.type='button';
    reset.onclick=async()=>{
      if(!confirm('Сбросить пароль '+staff.display_name+'? Старый пароль и действующие сессии будут отключены.'))return;
      reset.disabled=true;
      try{const data=await req('/'+encodeURIComponent(staff.id)+'/reset-password','POST');showPassword(data.one_time_password);announce('Новый пароль создан. Передайте его сотруднику.');}
      catch(e){announce(e.message,true);}finally{reset.disabled=false;}
    };
    actions.append(flip,reset);row.append(who,state,actions);box.appendChild(row);
  }
}
function showPassword(password){
  once=password;$('passwordValue').textContent=password;$('newPassword').hidden=false;
  $('newPassword').scrollIntoView({behavior:'smooth',block:'center'});
}
$('hidePassword').onclick=()=>{once='';$('passwordValue').textContent='';$('newPassword').hidden=true;};
$('copyPassword').onclick=async()=>{
  if(!once)return;
  try{await navigator.clipboard.writeText(once);announce('Пароль скопирован.');}
  catch{announce('Браузер не разрешил копирование. Выделите пароль вручную.',true);}
};
$('adminAccess').addEventListener('submit',async e=>{
  e.preventDefault();adminKey=$('adminSecret').value;
  $('teamError').hidden=true;
  try{
    await refresh();$('teamContent').hidden=false;$('adminAccess').hidden=true;
    $('adminSecret').value='';announce('Доступ администратора подтверждён.');
  }catch(err){adminKey='';$('teamError').textContent=err.message;$('teamError').hidden=false;}
});
$('newStaff').addEventListener('submit',async e=>{
  e.preventDefault();
  const body={username:$('username').value.trim(),display_name:$('displayName').value.trim()};
  const button=e.target.querySelector('button[type=submit]');button.disabled=true;
  try{
    const result=await req('', 'POST',body);
    e.target.reset();await refresh();showPassword(result.one_time_password);
    announce('Модератор создан. Пароль будет показан только один раз.');
  }catch(err){announce(err.message,true);}
  finally{button.disabled=false;}
});
$('reloadStaff').onclick=()=>refresh().catch(e=>announce(e.message,true));
if(!window.isSecureContext&&location.hostname!=='localhost'&&location.hostname!=='127.0.0.1'){
  $('adminAccess').hidden=true;$('teamError').textContent='Используйте localhost или HTTPS для ввода главного кода.';
  $('teamError').hidden=false;
}
