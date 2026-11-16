// Run against a disposable server/database only: creates and edits test catalog entries.
// ADMIN_TEST_TOKEN must match that server; default URL http://127.0.0.1:8050.
const {chromium}=require(process.env.PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict'), path=require('node:path');
(async()=>{
 const token=process.env.ADMIN_TEST_TOKEN;if(!token)throw Error('Set ADMIN_TEST_TOKEN for a disposable test server');
 const base=process.env.TEST_BASE_URL||'http://127.0.0.1:8050';
 const browser=await chromium.launch({headless:true});
 try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto(base+'/preview/admin.html');await page.locator('#token').fill(token);await page.getByRole('button',{name:'Войти →'}).click();
 await page.locator('#workspace').waitFor({state:'visible'});
 await page.locator('#sellers-tab').click();await page.locator('#seller-name').fill('Проверка браузера');await page.locator('#contact').fill('+7 999 123-45-67; @example');await page.locator('#zone').fill('Сектор А · ряд 1');await page.locator('#pavilion').fill('99');await page.getByRole('button',{name:'Сохранить продавца'}).click();
 await page.waitForFunction(()=>document.getElementById('message').textContent.includes('Продавец сохранён'));
 const sid=await page.locator('#seller-id').inputValue();
 await page.locator('#products-tab').click();await page.locator('#title').fill('Проверочная куртка');await page.locator('#category').fill('Проверка браузера');await page.locator('#price').fill('3210');await page.locator('#seller').selectOption(sid);await page.locator('#sizes').fill('S, M');await page.locator('#colors').fill('Розовый');await page.locator('#photos').setInputFiles([path.resolve(__dirname,'../backend/media/products/p01.jpg'),path.resolve(__dirname,'../backend/media/products/p02.jpg')]);
 await page.locator('#save-product').click();await page.waitForFunction(()=>document.getElementById('image-list').querySelectorAll('img').length===2);
 const pid=await page.locator('#product-id').inputValue();await page.locator('#publish').click();await page.waitForFunction(()=>document.getElementById('visibility').textContent==='В каталоге');
 const shop=await browser.newPage({viewport:{width:390,height:844}});shop.on('pageerror',e=>errors.push(e.message));
 await shop.goto(base+'/preview/live.html');await shop.getByText('Загрузить фотографию',{exact:true}).click();await shop.locator('#file').setInputFiles(path.resolve(__dirname,'../backend/media/products/p01.jpg'));await shop.waitForFunction(()=>photoDimensions!==null);
 const box=await shop.locator('#crop-stage').boundingBox();await shop.mouse.move(box.x+box.width*.1,box.y+box.height*.1);await shop.mouse.down();await shop.mouse.move(box.x+box.width*.9,box.y+box.height*.9,{steps:8});await shop.mouse.up();
 await shop.locator('select').first().selectOption('Проверка браузера');
 const req=shop.waitForResponse(r=>r.url().includes('/search/image')&&r.request().method()==='POST');await shop.getByRole('button',{name:'Найти похожие товары'}).click();assert.equal((await (await req).json()).crop_applied,true);
 await shop.getByText('Ищем выделенную область',{exact:true}).waitFor();const before=await shop.evaluate(()=>({crop:JSON.stringify(cropArea),image,ids:results.map(p=>p.id),file:selectedFile.name}));
 await shop.locator('.card').first().click();await shop.getByText('Размеры: S, M').waitFor();assert.equal(await shop.locator('[data-photo]').count(),2);await shop.locator('[data-photo]').last().click();await shop.locator('.sellerbox').click();await shop.getByText('Контакты: +7 999 123-45-67; @example',{exact:true}).waitFor();
 assert.equal(await shop.getByRole('link',{name:'Позвонить'}).getAttribute('href'),'tel:+79991234567');
 assert.equal(await shop.getByRole('link',{name:'Написать в Telegram'}).getAttribute('href'),'https://t.me/example');
 await shop.getByRole('button',{name:'Скопировать расположение'}).click();
 await shop.waitForFunction(()=>document.querySelector('.copy-status').textContent.length>0);
 assert.equal(await shop.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 await shop.screenshot({path:'/tmp/sadohod-seller-v06.png',fullPage:true});
 await shop.locator('.back').click();await shop.waitForFunction(()=>route.startsWith('product:'));
 await shop.locator('.back').click();await shop.waitForFunction(()=>route==='results');
 assert.deepEqual(await shop.evaluate(()=>({crop:JSON.stringify(cropArea),image,ids:results.map(p=>p.id),file:selectedFile.name})),before);
 await shop.locator('.card').first().click();await shop.locator('.sellerbox').click();
 await shop.waitForFunction(()=>route.startsWith('seller:'));await shop.goBack();await shop.waitForFunction(()=>route.startsWith('product:'));
 await shop.goBack();await shop.waitForFunction(()=>route==='results');
 assert.deepEqual(await shop.evaluate(()=>({crop:JSON.stringify(cropArea),image,ids:results.map(p=>p.id),file:selectedFile.name})),before);
 
 await page.locator('#price').fill('3456');await page.locator('#save-product').click();await page.waitForFunction(()=>document.getElementById('message').textContent==='Изменения сохранены.');await page.locator('#publish').click();await page.waitForFunction(()=>document.getElementById('message').textContent.includes('Товар скрыт'));
 assert.equal((await shop.request.get(base+'/api/v1/products/'+pid)).status(),404);
 await page.screenshot({path:process.env.QA_SCREENSHOT||'/tmp/sadohod-admin-qa.png',fullPage:true});
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:'/tmp/sadohod-admin-mobile-qa.png',fullPage:true});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 assert.deepEqual(errors,[]);console.log('PASS: browser login, seller, product, two uploads, publish, crop request, search, gallery, sizes, contacts, edit, hide, mobile overflow');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
