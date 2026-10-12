import json
import urllib.error
import urllib.request
from pathlib import Path

base = 'http://127.0.0.1:11235'
env = dict(line.split('=', 1) for line in Path('.secrets.env').read_text().splitlines() if '=' in line)
token = env['CRAWL4AI_API_TOKEN']

def request(path, body=None, auth=False):
    headers = {'Content-Type': 'application/json'}
    if auth:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=180) as response:
        return response.status, json.load(response)

status, health = request('/health')
assert status == 200 and health['status'] == 'ok'
print('HEALTH_OK version=' + health['version'])
body = {'urls': ['https://example.com']}
try:
    request('/crawl', body)
    raise AssertionError('Unauthenticated crawl accepted')
except urllib.error.HTTPError as error:
    assert error.code in (401, 403), error.code
    print('AUTH_REQUIRED status=' + str(error.code))
status, result = request('/crawl', body, auth=True)
assert status == 200, status
results = result.get('results', [])
assert results and results[0].get('success'), json.dumps(result)[:1000]
markdown = results[0].get('markdown', {})
if isinstance(markdown, dict):
    markdown = markdown.get('raw_markdown', '')
assert 'documentation examples' in markdown.lower(), str(markdown)[:500]
print('CRAWL_OK url=https://example.com markdown_chars=' + str(len(markdown)))
