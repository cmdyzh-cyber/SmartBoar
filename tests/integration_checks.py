"""Native manager integration tests with isolated USB/CUPS/launchd fixtures.
No production queue, USB interface, launchd label or printer is modified.
"""
import copy, hashlib, json, plistlib, shutil, subprocess, sys
from pathlib import Path
project=Path(__file__).resolve().parent.parent
root=project/'build/fixtures-v2'
root.mkdir(parents=True,exist_ok=True)
shutil.copy2(project/'tests/mock_tools.py',root/'mock_tools.py')
for folder in ['Mocks','PPDs','Drivers/hp108a-splix-fixed']:(root/folder).mkdir(exist_ok=True,parents=True)
for name in ['legacyprint-usb','lpstat','launchctl','lpadmin','cupsdisable','cupsenable','cupsaccept','cupstestppd','cancel','lp']:
    p=root/'Mocks'/name
    p.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{root}/mock_tools.py" "$0" "$@"\n'); p.chmod(0o755)
catalog=json.loads((project/'resources/catalog.json').read_text())
module=catalog['modules']['hp108a-splix-fixed']
filterpath=root/module['filter']
shutil.copy2(project/'vendor/rastertoqpdl',filterpath)
ppdpath=root/catalog['profiles'][0]['ppd']
ppdpath.write_text((project/'resources/HP108a.ppd').read_text().replace('/Library/Printers/LegacyPrint/Core',str(root)))
module['assets']={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in [module['filter'],catalog['profiles'][0]['ppd']]}
shutil.copy2(project/'resources/test-page.txt',root/'test-page.txt')
ctl=root/'fixture-control'
subprocess.run(['xcrun','clang','-arch','arm64','-mmacosx-version-min=14.0','-O2','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations','-DLP_TEST_MODE=1',f'-DLP_BASE=@"{root}"',f'-DLP_STATE=@"{root}/State"',str(project/'src/Control.m'),'-framework','Foundation','-o',str(ctl)],check=True)
def run(*args):
    r=subprocess.run([str(ctl),*args],capture_output=True,text=True)
    return r.returncode,r.stdout,r.stderr
def ok(*args):
    r=run(*args); assert r[0]==0,r; return r[1]
def bad(*args):
    r=run(*args); assert r[0]!=0,r; return r[2]
def dev(serial='SNTEST001',vid=0x03f0,pid=0xe82a,product='HP Laser 108a',manufacturer='HP Inc.'):
    return {'serial':serial,'vid':vid,'pid':pid,'product':product,'manufacturer':manufacturer,'location':100}
def state():return json.loads((root/'mock-state.json').read_text())
def put(s):(root/'mock-state.json').write_text(json.dumps(s))
def reset(devs,existing=False,paused=False,pending=False):
    shutil.rmtree(root/'State',ignore_errors=True)
    (root/'catalog.json').write_text(json.dumps(catalog))
    (root/'inventory.plist').write_bytes(plistlib.dumps(devs))
    for f in (root/'PPDs').glob('*.ppd'):f.unlink()
    s={'queues':{'OTHER':{'uri':'usb://OTHER/Printer?serial=OTHER_SN','enabled':True,'pending':True}},'disabled':[],'loaded':[],'log':[]}
    (root/'PPDs/OTHER.ppd').write_text('OTHER-UNCHANGED')
    if existing:
        s['queues']['TARGET']={'uri':'usb://HP/HP%20Laser%20103%20107%20108?serial=SNTEST001','enabled':not paused,'pending':pending}
        (root/'PPDs/TARGET.ppd').write_text('*QPDL SpecialBandWidth: True\n*QPDL QPDLVersion: "3"\n*DefaultDuplex: DuplexNoTumble\n*cupsFilter: "application/vnd.cups-raster 0 /original-filter"\n')
    put(s)
def identity():return json.loads(ok('inventory'))['devices'][0]['id']
def untouched():
    assert state()['queues']['OTHER']=={'uri':'usb://OTHER/Printer?serial=OTHER_SN','enabled':True,'pending':True}
    assert (root/'PPDs/OTHER.ppd').read_text()=='OTHER-UNCHANGED'

reset([]); assert json.loads(ok('inventory'))['devices']==[]; bad('plan'); assert not state()['log']
reset([dev()]); ident=identity(); plan=json.loads(ok('plan')); assert plan['profile']=='hp-laser-108a' and not plan['sendsPrintData'] and not plan['existingQueue']; assert not state()['log']
report=ok('report'); assert 'SNTEST001' not in report and ident not in report and str(root) not in report
reset([dev(product='HP Laser 107a')]); row=json.loads(ok('inventory'))['devices'][0]; assert row['support']=='identity-mismatch' and not row['canConfigure']; bad('configure'); assert not state()['log']
reset([dev(vid=0x04e8,pid=1234,product='Samsung ML-2010',manufacturer='Samsung')]); assert json.loads(ok('inventory'))['devices'][0]['support']=='catalog-only'; bad('configure'); assert not state()['log']
reset([dev(vid=0x1234,pid=5678,product='Other Printer')]); assert json.loads(ok('inventory'))['devices'][0]['support']=='unknown'; bad('configure'); assert not state()['log']
reset([dev(serial='')]); assert not json.loads(ok('inventory'))['devices'][0]['canConfigure']; bad('plan')
reset([dev(serial='../../escape')]); bad('plan'); assert not state()['log']
reset([dev(),dev(serial='SNTEST002')]); bad('plan'); ident=identity(); assert json.loads(ok('plan',ident))['id']==ident
reset([dev(),dev()]); bad('plan'); assert not state()['log']
reset([dev()]); dup=copy.deepcopy(catalog['profiles'][0]); dup['id']='duplicate-model'; altered=copy.deepcopy(catalog); altered['profiles'].append(dup); (root/'catalog.json').write_text(json.dumps(altered)); assert json.loads(ok('inventory'))['devices'][0]['support']=='ambiguous'; bad('configure'); assert not state()['log']

reset([dev()],existing=True,pending=True); ident=identity(); bad('configure',ident); assert not state()['log']; untouched()
reset([dev()],existing=True); ident=identity(); original=(root/'PPDs/TARGET.ppd').read_bytes(); ok('configure',ident)
assert '*DefaultDuplex: DuplexNoTumble' in (root/'PPDs/TARGET.ppd').read_text(); assert str(filterpath) in (root/'PPDs/TARGET.ppd').read_text()
snap=root/'State'/ident/'snapshot.json'; snapbytes=snap.read_bytes(); assert snap.stat().st_mode&0o777==0o600
assert not any(v[0]=='lp' for v in state()['log']); untouched()
ok('configure',ident); assert snap.read_bytes()==snapbytes; untouched()
ok('test',ident); assert len([v for v in state()['log'] if v[0]=='lp'])==1
ok('rollback',ident); assert (root/'PPDs/TARGET.ppd').read_bytes()==original and state()['queues']['TARGET']['enabled']; assert not snap.exists(); assert not state()['disabled']; untouched()

reset([dev()],existing=True,paused=True); ident=identity(); ok('configure',ident); ok('rollback',ident); assert not state()['queues']['TARGET']['enabled']; untouched()
reset([dev()]); ident=identity(); ok('configure',ident); created=[q for q in state()['queues'] if q!='OTHER']; assert len(created)==1; assert state()['queues'][created[0]]['description']=='聪明的野猪 · HP Laser 108a'; ok('rollback',ident); assert list(state()['queues'])==['OTHER']; untouched()
reset([dev()],existing=True); ident=identity(); original=(root/'PPDs/TARGET.ppd').read_bytes(); s=state(); s['failOnce']='lpadmin'; put(s); bad('configure',ident); assert (root/'PPDs/TARGET.ppd').read_bytes()==original and state()['queues']['TARGET']['enabled'] and not state()['disabled']; untouched()
reset([dev()]); ident=identity(); s=state(); s['failOnce']='legacyprint-usb'; put(s); bad('configure',ident); assert list(state()['queues'])==['OTHER'] and not state()['disabled']; untouched()
reset([dev()],existing=True); ident=identity(); ok('configure',ident); s=state(); s['queues']['TARGET']['uri']='usb://OTHER/Printer?serial=OTHER_SN'; s['log']=[]; put(s); bad('rollback',ident); assert not state()['log']; untouched()
reset([dev()],existing=True,pending=True); ident=identity(); ok('clear-jobs',ident); assert not state()['queues']['TARGET']['enabled'] and not state()['queues']['TARGET']['pending']; untouched()
reset([dev()],existing=True); ident=identity(); s=state(); s['queues']['SECOND']=copy.deepcopy(s['queues']['TARGET']); put(s); bad('plan',ident); assert not state()['log']

# A future verified model/module can be added without changing native manager code.
reset([dev(vid=0x1234,pid=5678,product='Fixture Printer')]); expanded=copy.deepcopy(catalog); p=copy.deepcopy(expanded['profiles'][0]); p.update({'id':'fixture-printer','model':'Fixture Printer','queueSlug':'Fixture','usbAction':'none','uriTemplate':'usb://Fixture/Fixture%20Printer?serial={serial}','match':{'vendorIds':[0x1234],'usbIds':[{'vid':0x1234,'pid':5678}],'products':['Fixture Printer'],'requireUsbId':True}}); expanded['profiles'].append(p); (root/'catalog.json').write_text(json.dumps(expanded)); ident=identity(); ok('configure',ident); assert not any(v[0] in {'launchctl','legacyprint-usb'} for v in state()['log']); ok('rollback',ident); untouched()

reset([dev()]); altered=copy.deepcopy(catalog); altered['modules']['hp108a-splix-fixed']['assets'][module['filter']]='0'*64; (root/'catalog.json').write_text(json.dumps(altered)); bad('configure'); assert not state()['log']
reset([dev()]); altered=copy.deepcopy(catalog); altered['profiles'][0]['ppd']='../../outside'; (root/'catalog.json').write_text(json.dumps(altered)); bad('configure'); assert not state()['log']
print('PASS: discovery/matching, shared USB ID rejection, unknown/candidate blocking, duplicate identities, catalog ambiguity, pending jobs, module hashes, safe paths, first backup preservation, existing options, targeted setup, one-page submission, failure recovery, paused-state rollback, new-queue rollback, changed-URI protection, selected-queue cancellation, and extensible second-profile configuration.')
