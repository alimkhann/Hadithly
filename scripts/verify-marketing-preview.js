// Run with playwright-cli -s=hadithly-d run-code --filename scripts/verify-marketing-preview.js.
// The named Chrome session must already be open to the local preview.
async (page) => {
  const base = 'http://127.0.0.1:8787';
  const paths = ['/', '/privacy/', '/terms/', '/support/', '/delete-account/', '/status/', '/hadith/'];
  const results = [];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  // All external services remain disconnected during local rendering checks.
  await page.route('https://**/*', route => route.abort());
  await page.route('**/operations-config.js', route => route.fulfill({contentType: 'application/javascript', body: 'window.HADITHLY_OPERATIONS={enabled:false};'}));
  for (const width of [1440, 768, 390, 320]) {
    await page.setViewportSize({width, height: 1000});
    for (const path of paths) {
      const response = await page.goto(base + path);
      if (!response.ok()) throw new Error(`${path}: HTTP ${response.status()}`);
      await page.locator('main').waitFor();
      const faults = await page.evaluate(() => {
        const issues = [];
        if (document.documentElement.scrollWidth > innerWidth) issues.push('horizontal overflow');
        if (document.querySelectorAll('main').length !== 1) issues.push('main landmark');
        if ([...document.querySelectorAll('h1')].filter(heading => heading.getClientRects().length).length !== 1) issues.push('page heading');
        for (const img of document.images) if (!img.hasAttribute('alt')) issues.push('missing image alternative');
        for (const field of document.querySelectorAll('input:not([type=hidden]),textarea,select')) {
          if (field.closest('[hidden],[aria-hidden=true]')) continue;
          if (!field.labels?.length && !field.getAttribute('aria-label')) issues.push('unlabelled input');
        }
        for (const link of document.querySelectorAll('a[href^="#"]')) {
          if (!link.getClientRects().length) continue;
          if (!document.getElementById(link.hash.slice(1))) issues.push('missing anchor ' + link.hash);
        }
        return issues;
      });
      if (faults.length) throw new Error(`${width} ${path}: ${faults.join(', ')}`);
      results.push({width, path, result:'passed'});
      if (width === 1440 || width === 390) {
        // Loading each page's images before capture also catches bad local asset paths.
        await page.locator('img').evaluateAll(async images => {
          await Promise.all(images.map(async image => {
            image.loading = 'eager';
            await image.decode();
          }));
        });
        await page.screenshot({path: `output/playwright/hadithly-d/${path === '/' ? 'home' : path.split('/')[1]}-${width}.png`, fullPage:true});
      }
    }
  }
  await page.setViewportSize({width:390, height:844});
  await page.goto(base + '/');
  await page.keyboard.press('Tab');
  if (await page.locator(':focus').innerText() !== 'Skip to content') throw new Error('Skip link is not first in keyboard order');
  await page.keyboard.press('Enter');
  if (await page.locator(':focus').getAttribute('id') !== 'main') throw new Error('Skip link did not move focus to main');
  await page.getByRole('link', {name:'Explore Hadithly', exact:true}).click();
  if (new URL(page.url()).hash !== '#collections') throw new Error('Feature navigation');
  await page.getByRole('link', {name:'App availability', exact:false}).first().click();
  if (new URL(page.url()).hash !== '#availability') throw new Error('Availability navigation');
  if (!await page.getByText('Hadithly is in development.', {exact:false}).isVisible()) throw new Error('Availability disclosure');
  await page.goto(base + '/privacy/');
  const consent = page.getByRole('checkbox', {name:'Send page error reports'});
  await consent.check();
  if (!await consent.isChecked()) throw new Error('Consent control did not check');
  await consent.uncheck();
  if (await consent.isChecked()) throw new Error('Consent control did not clear');
  await page.emulateMedia({reducedMotion:'reduce'});
  if (await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior) !== 'auto') throw new Error('Reduced motion');
  for (const path of paths) {
    await page.goto(base + path);
    await page.evaluate(() => {document.documentElement.style.fontSize = '200%';});
    if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) throw new Error('Text scaling overflow: ' + path);
  }
  await page.goto(base + '/');
  if (errors.length) throw new Error(errors.join('\n'));
  return {results, keyboard:'passed', navigation:'passed', consentControl:'passed', reducedMotion:'passed', textScaling:'passed', pageErrors:errors};
}
