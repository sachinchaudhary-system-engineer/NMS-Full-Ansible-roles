#!/usr/bin/env python3
# Builds harbor.yml from the template that ships in the Harbor installer.
import os
import sys
import yaml

src, dst = sys.argv[1], sys.argv[2]
cfg = yaml.safe_load(open(src))
env = os.environ

cfg['hostname'] = env['HARBOR_HOSTNAME']
cfg['http'] = {'port': int(env['HARBOR_HTTP_PORT'])}
if env.get('HARBOR_CERT'):
    cfg['https'] = {
        'port': int(env['HARBOR_HTTPS_PORT']),
        'certificate': env['HARBOR_CERT'],
        'private_key': env['HARBOR_KEY'],
    }
else:
    cfg.pop('https', None)
cfg['harbor_admin_password'] = env['HARBOR_ADMIN_PASSWORD']
cfg['database']['password'] = env['HARBOR_DB_PASSWORD']
cfg['data_volume'] = env['HARBOR_DATA_DIR']

with open(dst, 'w') as f:
    yaml.safe_dump(cfg, f, default_flow_style=False, sort_keys=False)
os.chmod(dst, 0o600)
