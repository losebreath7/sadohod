// Only explicitly provided, recognized contact formats become actionable links.
function sellerAddress(s){return ['Садовод',s.zone,s.pavilion?'павильон '+s.pavilion:''].filter(Boolean).join(', ')}
function contactLinks(text){
 const links=[],seen=new Set();
 const add=(label,href)=>{if(!seen.has(href)){seen.add(href);links.push({label,href})}};
 const source=String(text||'');
 const withoutUrls=source.replace(/https?:\/\/[^\s;,<>]+/gi,raw=>{
  try{
   const u=new URL(raw.replace(/[.)]+$/,''));
   if(u.username||u.password||u.port)return ' ';
   if(['t.me','telegram.me'].includes(u.hostname)&&/^\/[a-zA-Z][\w]{4,31}\/?$/.test(u.pathname))add('Написать в Telegram','https://t.me/'+u.pathname.split('/')[1]);
   if(u.hostname==='wa.me'&&/^\/\d{10,15}\/?$/.test(u.pathname))add('Написать в WhatsApp','https://wa.me/'+u.pathname.split('/')[1]);
  }catch{}
  return ' ';
 });
 const remaining=withoutUrls.replace(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g,email=>{add('Написать на почту','mailto:'+email);return ' '});
 for(const m of remaining.matchAll(/(?:^|[\s;,])@([a-zA-Z][\w]{4,31})(?!\w)/g))add('Написать в Telegram','https://t.me/'+m[1]);
 for(const m of remaining.matchAll(/(?:^|[\s:;,])((?:\+\d|8)[\d ()-]{8,22}\d)(?!\d)/g)){
  let digits=m[1].replace(/\D/g,'');
  if(digits.length===11&&digits[0]==='8')digits='7'+digits.slice(1);
  if(digits.length>=10&&digits.length<=15&&(m[1].startsWith('+')||digits.length===11))add('Позвонить','tel:+'+digits);
 }
 return links;
}
function sellerActions(s){
 const links=contactLinks(s.contact);
 return `<div class="contact-actions">${links.map(l=>`<a class="outline" href="${esc(l.href)}" ${l.href.startsWith('https:')?'target="_blank" rel="noopener noreferrer"':''}>${esc(l.label)}</a>`).join('')}<button class="outline copy-address" data-copy-address="${esc(sellerAddress(s))}">Скопировать расположение</button><span class="copy-status" role="status" aria-live="polite"></span></div>`;
}
async function copyAddress(button){
 const text=button.dataset.copyAddress,container=button.parentElement,status=container.querySelector('.copy-status');
 let copied=false;
 try{if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(text);copied=true}}catch{}
 if(!copied){
  // LAN HTTP on a phone may not expose Clipboard API. Keep manual copy available.
  let field=container.querySelector('.address-fallback');
  if(!field){field=document.createElement('input');field.className='address-fallback';field.readOnly=true;field.setAttribute('aria-label','Расположение для копирования');container.appendChild(field)}
  field.value=text;field.focus();field.select();field.setSelectionRange(0,text.length);
  try{copied=document.execCommand('copy')}catch{}
  if(copied)field.remove();
 }
 status.textContent=copied?'Расположение скопировано':'Выдели адрес ниже и выбери «Копировать».';
}
