"""Read-only release/package validation. Does not install the package."""
import hashlib, json, plistlib, subprocess
from pathlib import Path
project=Path(__file__).resolve().parent.parent
payload=project/'build/release-expanded/LegacyPrint-component.pkg/Payload'
core=payload/'Library/Printers/LegacyPrint/Core'
catalog=json.loads((core/'catalog.json').read_text())
assert len(catalog['profiles'])==11
assert sum(p['support']=='verified' for p in catalog['profiles'])==1
assert not catalog['networkDownloads']
for module in catalog['modules'].values():
    for path,expected in module['assets'].items():assert hashlib.sha256((core/path).read_bytes()).hexdigest()==expected
for p in [core/'legacyprintctl',core/'legacyprint-usb',core/'Drivers/hp108a-splix-fixed/rastertoqpdl']:
    assert b'/Mocks' not in p.read_bytes() and b'/fixtures-v2' not in p.read_bytes()
    assert subprocess.check_output(['lipo','-archs',str(p)],text=True).strip()=='arm64'
    subprocess.run(['codesign','--verify','--strict',str(p)],check=True)
app=payload/'Applications/聪明的野猪.app'
assert subprocess.check_output(['lipo','-archs',str(app/'Contents/MacOS/LegacyPrint')],text=True).strip()=='arm64'
assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='0.2.0'
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
bom=subprocess.check_output(['lsbom','-p','fUGM',str(project/'build/release-expanded/LegacyPrint-component.pkg/Bom')],text=True)
for line in bom.splitlines():
    path,owner,group,mode=line.split('\t')
    assert owner=='root' and group=='wheel',(path,owner,group)
    assert mode[5]!='w' and mode[8]!='w',(path,mode)
    assert not path.startswith('./Library/Printers/HP108a_SpliX')
scripts=project/'build/release-expanded/LegacyPrint-component.pkg/Scripts'
assert {p.name for p in scripts.iterdir()}=={'postinstall'}
assert (core/'licenses/SpliX-fixed-source.tar.gz').is_file()
assert (core/'licenses/COPYING-SpliX.txt').is_file()
print('PASS: installer expansion, 11 catalog entries with one enabled profile, module hashes, ARM64 executables/ad-hoc signatures, app version, root ownership, non-writable payload, no fixture runtime, scoped postinstall, and GPL corresponding source.')
