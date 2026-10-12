"""Keep Caddy's crawler network in the mail stack's default Compose file."""
from pathlib import Path

path = Path('/home/traen/aryseller-mail-server/compose.yaml')
source = path.read_text()
marker = '\nnetworks:\n  crawler:\n    external: true\n    name: crawl4ai_default\n'
if marker in source:
    assert '    networks:\n      default: {}\n      crawler: {}\n' in source.split('  caddy:\n', 1)[1]
    print('DEFAULT_COMPOSE_WEB_NETWORK_ALREADY_CONFIGURED')
else:
    assert '\nnetworks:' not in source, 'Existing top-level networks require a manual merge'
    prefix, caddy = source.split('  caddy:\n', 1)
    anchor = '    depends_on:\n      - roundcube\n'
    assert caddy.count(anchor) == 1
    assert '    networks:' not in caddy
    caddy = caddy.replace(anchor, '    networks:\n      default: {}\n      crawler: {}\n' + anchor)
    path.write_text(prefix + '  caddy:\n' + caddy.rstrip() + '\n' + marker)
    print('DEFAULT_COMPOSE_WEB_NETWORK_CONFIGURED')
