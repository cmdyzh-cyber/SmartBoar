"""Development-only catalog preparation. No Python runtime is installed."""
import hashlib, json, shutil, sys
from pathlib import Path
source, root = map(Path, sys.argv[1:])
catalog = json.loads(source.read_text())
for module_id, module in catalog['modules'].items():
    paths = {module['filter']}
    paths.update(p['ppd'] for p in catalog['profiles'] if p.get('module') == module_id)
    module['assets'] = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sorted(paths)}
(root / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
scripts = source.parent.parent / 'build/package-scripts'
scripts.mkdir(parents=True, exist_ok=True)
shutil.copy2(source.parent.parent / 'scripts/postinstall', scripts / 'postinstall')
(scripts / 'postinstall').chmod(0o755)
