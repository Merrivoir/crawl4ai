const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const output = process.argv[2];
const base = process.argv[3] || 'http://127.0.0.1:5180';
(async () => {
  const browser = await chromium.launch({headless:true,channel:'msedge'});
  const page = await browser.newPage({viewport:{width:1440,height:1000}});
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(base + '/services/crawl4ai/', {waitUntil:'networkidle'});
  await page.waitForURL('**/services/crawl4ai/');
  await page.screenshot({path:path.join(output,'crawl4ai-desktop.png'),fullPage:true});
  await page.locator('#page-url').fill('https://example.com');
  await page.locator('#submit-button').click();
  await page.locator('#request-status').filter({hasText:'Укажите ключ доступа'}).waitFor();
  await page.locator('#api-token').fill('qa-invalid-key');
  await page.route('**/services/crawl4ai/api/crawl', route => route.fulfill({status:401,contentType:'application/json',body:'{"detail":"Unauthorized"}'}));
  await page.locator('#submit-button').click();
  await page.locator('#request-status').filter({hasText:'Ключ доступа не принят'}).waitFor();
  await page.unroute('**/services/crawl4ai/api/crawl');
  await page.route('**/services/crawl4ai/api/crawl', async route => {
    const data = route.request().postDataJSON();
    assert.deepEqual(data.urls, ['https://example.com/']);
    await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({results:[{success:true,markdown:{raw_markdown:'# Страница\n\n<img src=x onerror=alert(1)>'},cleaned_html:'<h1>Страница</h1>'}]})});
  });
  await page.locator('#submit-button').click();
  await page.locator('#request-status').filter({hasText:'Готово:'}).waitFor();
  assert.ok((await page.locator('#result-content').innerText()).includes('<img'));
  assert.equal(await page.locator('#result-content img').count(),0);
  await page.locator('#tab-json').click();
  assert.ok((await page.locator('#result-content').innerText()).includes('"success": true'));
  const downloadWait = page.waitForEvent('download');
  await page.locator('#download-result').click();
  assert.equal((await downloadWait).suggestedFilename(),'crawl4ai-result.json');
  await page.locator('#clear-token').click();
  assert.equal(await page.locator('#api-token').inputValue(),'');
  for (const width of [320,390,768]) {
    await page.setViewportSize({width,height:844});
    for (const route of ['/services/crawl4ai/']) {
      await page.goto(base + route,{waitUntil:'networkidle'});
      const layout = await page.evaluate(() => ({scroll:document.documentElement.scrollWidth,viewport:window.innerWidth}));
      assert.ok(layout.scroll <= layout.viewport, JSON.stringify({width,route,...layout}));
      if (width === 390) await page.screenshot({path:path.join(output,route === '/' ? 'aryseller-mobile.png' : 'crawl4ai-mobile.png'),fullPage:true});
    }
  }
  assert.deepEqual(errors,[]);
  console.log('BROWSER_QA_OK: navigation, missing/invalid token, result tabs, safe text rendering, download, mobile widths 320/390/768; success response mocked.');
  await browser.close();
})().catch(error => {console.error(error); process.exitCode = 1;});
