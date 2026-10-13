(() => {
  'use strict';
  const base = '/services/crawl4ai/api';
  const storageKey = 'aryseller.crawl4ai.token';
  const $ = id => document.getElementById(id);
  const form = $('crawl-form');
  const tokenInput = $('api-token');
  const status = $('request-status');
  let outputs = null;
  let selectedFormat = 'markdown';
  let busy = false;

  function savedToken() { try { return sessionStorage.getItem(storageKey) || ''; } catch { return ''; } }
  function saveToken(value) { try { value ? sessionStorage.setItem(storageKey, value) : sessionStorage.removeItem(storageKey); } catch { /* The form also works with storage disabled. */ } }
  function tokenState() { $('token-state').textContent = tokenInput.value.trim() ? 'указан' : 'не указан'; }
  function message(text, error = false) { status.textContent = text; status.classList.toggle('error', error); }
  tokenInput.value = savedToken();
  tokenState();
  if (tokenInput.value) $('token-details').open = false;
  tokenInput.addEventListener('input', () => { saveToken(tokenInput.value.trim()); tokenState(); });
  $('clear-token').addEventListener('click', () => { tokenInput.value = ''; saveToken(''); tokenState(); $('token-details').open = true; tokenInput.focus(); message('Сохранённый ключ удалён.'); });
  $('toggle-token').addEventListener('click', () => {
    const show = tokenInput.type === 'password';
    tokenInput.type = show ? 'text' : 'password';
    $('toggle-token').textContent = show ? 'Скрыть' : 'Показать';
    $('toggle-token').setAttribute('aria-label', show ? 'Скрыть ключ доступа' : 'Показать ключ доступа');
    $('toggle-token').setAttribute('aria-pressed', String(show));
  });

  function selectFormat(format) {
    selectedFormat = format;
    for (const tab of document.querySelectorAll('.result-tab')) {
      const active = tab.dataset.format === format;
      tab.classList.toggle('active', active);
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
    }
    $('output').setAttribute('aria-labelledby', 'tab-' + format);
    if (outputs) $('result-content').textContent = outputs[format];
  }
  const tabs = [...document.querySelectorAll('.result-tab')];
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectFormat(tab.dataset.format));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault(); tabs[next].focus(); selectFormat(tabs[next].dataset.format);
    });
  });

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (busy) return;
    const token = tokenInput.value.trim();
    if (!token) { $('token-details').open = true; tokenInput.focus(); message('Укажите ключ доступа к сервису.', true); return; }
    let url;
    try {
      url = new URL($('page-url').value.trim());
      if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password) throw new Error('Invalid URL');
    } catch { message('Укажите полный HTTP или HTTPS адрес страницы.', true); $('page-url').focus(); return; }
    saveToken(token);
    busy = true;
    $('submit-button').disabled = true;
    $('submit-button').classList.add('loading');
    $('submit-label').textContent = 'Обрабатываем…';
    $('output').setAttribute('aria-busy', 'true');
    message('Загружаем страницу и извлекаем содержимое…');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 180000);
    const started = performance.now();
    try {
      const response = await fetch(base + '/crawl', {
        method: 'POST', credentials: 'omit', signal: controller.signal,
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token},
        body: JSON.stringify({urls: [url.href]})
      });
      if (response.status === 401 || response.status === 403) throw new Error('Ключ доступа не принят. Проверьте его или обратитесь в компанию.');
      if (response.status === 429) throw new Error('Слишком много запросов. Попробуйте немного позже.');
      if (!response.ok) throw new Error('Не удалось обработать запрос (HTTP ' + response.status + '). Попробуйте позже.');
      const data = await response.json();
      const result = data.results && data.results[0];
      if (!result || !result.success) throw new Error('Не удалось получить содержимое этой страницы. Проверьте адрес и доступность сайта.');
      const markdown = typeof result.markdown === 'string' ? result.markdown : (result.markdown?.raw_markdown || result.markdown?.fit_markdown || '');
      outputs = {markdown, html: result.cleaned_html || result.html || '', json: JSON.stringify(data, null, 2)};
      $('empty-state').hidden = true;
      $('result-content').hidden = false;
      $('copy-result').disabled = false;
      $('download-result').disabled = false;
      selectFormat(selectedFormat);
      const elapsed = ((performance.now() - started) / 1000).toFixed(1);
      $('result-meta').textContent = elapsed + ' с · ' + markdown.length.toLocaleString('ru-RU') + ' символов';
      message('Готово: ' + url.hostname + '. Результат можно скопировать или скачать.');
    } catch (error) {
      message(error.name === 'AbortError' ? 'Время ожидания истекло. Попробуйте повторить запрос.' : (error instanceof TypeError ? 'Нет соединения с сервисом. Проверьте интернет и повторите запрос.' : error.message), true);
    } finally {
      clearTimeout(timeout); busy = false;
      $('submit-button').disabled = false;
      $('submit-button').classList.remove('loading');
      $('submit-label').textContent = 'Обработать страницу';
      $('output').setAttribute('aria-busy', 'false');
    }
  });

  $('copy-result').addEventListener('click', async () => {
    if (!outputs) return;
    try { await navigator.clipboard.writeText(outputs[selectedFormat]); message('Результат скопирован.'); }
    catch { message('Не удалось скопировать. Используйте кнопку «Скачать».', true); }
  });
  $('download-result').addEventListener('click', () => {
    if (!outputs) return;
    const types = {markdown: ['md', 'text/markdown;charset=utf-8'], html: ['html', 'text/html;charset=utf-8'], json: ['json', 'application/json;charset=utf-8']};
    const [extension, type] = types[selectedFormat];
    const href = URL.createObjectURL(new Blob([outputs[selectedFormat]], {type}));
    const link = document.createElement('a'); link.href = href; link.download = 'crawl4ai-result.' + extension;
    document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(href), 1000);
  });

  const healthController = new AbortController();
  const healthTimeout = setTimeout(() => healthController.abort(), 10000);
  fetch(base + '/health', {credentials: 'omit', signal: healthController.signal})
    .then(response => { if (!response.ok) throw new Error(); return response.json(); })
    .then(data => { if (data.status !== 'ok') throw new Error(); $('availability-text').textContent = 'Сервис доступен'; })
    .catch(() => { $('availability').classList.add('offline'); $('availability-text').textContent = 'Сервис временно недоступен'; })
    .finally(() => clearTimeout(healthTimeout));
})();
