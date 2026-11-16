// Execute the real request handler: guards against the v0.3 state reset regression.
const vm=require('node:vm'), fs=require('node:fs'), assert=require('node:assert/strict');
const sent=[];
const context=vm.createContext({console,URLSearchParams, history:{replaceState(){}}, window:{addEventListener(){}},
 document:{getElementById:()=>({addEventListener(){},style:{}})},
 FormData:class {constructor(){this.fields={}} append(k,v){this.fields[k]=v}},
 fetch:async(url,options)=>{sent.push({url,fields:options.body.fields});return {ok:true,json:async()=>({items:[],notice:'ok',method:'openclip_image_embedding'})}}
});
let code=fs.readFileSync(__dirname+'/live_script.js','utf8').replace("view.innerHTML='<div class=\"content\">Загружаем каталог…</div>';bootstrap();",'');
vm.runInContext(code,context);
(async()=>{
 vm.runInContext("go=()=>{};render=()=>{};selectedFile={name:'test.jpg'};searchBackend='clip';photoDimensions={w:800,h:600};cropArea={x:.1,y:.2,w:.5,h:.4};searchCategory='Платья';searchThreshold='0.3'",context);
 await vm.runInContext('runSearch()',context);
 assert.equal(sent[0].fields.crop,'0.100000,0.200000,0.500000,0.400000');
 assert.equal(new URLSearchParams(sent[0].url.split('?')[1]).get('category'),'Платья');
 assert.equal(vm.runInContext('searchBackend',context),'clip');
 assert.equal(vm.runInContext('photoDimensions.w',context),800);
 await vm.runInContext('runSearch()',context);
 assert.equal(sent[1].fields.crop,sent[0].fields.crop);
 vm.runInContext('resetCrop()',context);
 await vm.runInContext('runSearch()',context);
 assert.equal(sent[2].fields.crop,undefined);
 console.log('PASS: crop, model, dimensions, filters, repeat search and crop reset');
})().catch(e=>{console.error(e);process.exitCode=1});
