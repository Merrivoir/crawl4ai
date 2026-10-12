import json
import urllib.error
import urllib.request
from pathlib import Path

base = 'https://aryseller.com'
for route in ('/', '/services/crawl4ai/', '/assets/site.css', '/assets/crawl4ai.js', '/robots.txt', '/sitemap.xml'):
    with urllib.request.urlopen(base + route, timeout=20) as response:
        assert response.status == 200
        if route == '/':
            html = response.read().decode()
            assert 'info@aryseller.com' in html and '/services/crawl4ai/' in html
            assert "script-src 'self'" in response.headers['Content-Security-Policy']
    print('HTTPS_OK ' + route)
with urllib.request.urlopen('http://aryseller.com/', timeout=20) as response:
    assert response.geturl() == base + '/'
    print('HTTP_TO_HTTPS_OK')
with urllib.request.urlopen('https://www.aryseller.com/', timeout=20) as response:
    assert response.geturl() == base + '/'
    print('WWW_CANONICAL_OK')
try:
    urllib.request.urlopen(base + '/not-a-page', timeout=20)
    raise AssertionError('Unknown page accepted')
except urllib.error.HTTPError as error:
    assert error.code == 404
    print('UNKNOWN_PAGE_404_OK')
token = dict(line.split('=', 1) for line in Path('/home/traen/crawl4ai/.secrets.env').read_text().splitlines() if '=' in line)['CRAWL4AI_API_TOKEN']
def crawl(auth):
    headers = {'Content-Type': 'application/json'}
    if auth:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(base + '/services/crawl4ai/api/crawl', data=json.dumps({'urls': ['https://example.com']}).encode(), headers=headers)
    return urllib.request.urlopen(request, timeout=180)
try:
    crawl(False)
    raise AssertionError('Unauthenticated crawl accepted')
except urllib.error.HTTPError as error:
    assert error.code == 401
    print('PUBLIC_API_AUTH_REQUIRED_401')
with crawl(True) as response:
    result = json.load(response)['results'][0]
    assert result['success']
    markdown = result['markdown']
    if isinstance(markdown, dict):
        markdown = markdown.get('raw_markdown', '')
    assert 'documentation examples' in markdown.lower()
    print('PUBLIC_API_CRAWL_OK markdown_chars=' + str(len(markdown)))
with urllib.request.urlopen('https://mail.aryseller.com/', timeout=20) as response:
    assert response.status == 200
    print('MAIL_HTTPS_OK')
