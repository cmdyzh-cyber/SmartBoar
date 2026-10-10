"""Development fixture. All commands operate only inside the fixture directory."""
import json, plistlib, shutil, sys
from pathlib import Path
root=Path(__file__).resolve().parent
name=Path(sys.argv[1]).name
args=sys.argv[2:]
store=root/'mock-state.json'
s=json.loads(store.read_text())
mutates=name in {'lpadmin','cupsdisable','cupsenable','cupsaccept','cancel','lp'} or (name=='launchctl' and args[0] in {'disable','enable','bootout'}) or (name=='legacyprint-usb' and args)
def save(): store.write_text(json.dumps(s))
if mutates:
    s['log'].append([name,*args])
    if s.get('failOnce')==name:
        s['failOnce']=None; save(); print('Injected setup failure',file=sys.stderr); sys.exit(1)
    save()
if name=='legacyprint-usb':
    if not args: print((root/'inventory.plist').read_text())
elif name=='lpstat':
    if args==['-v']:
        if not s['queues']: print('lpstat: No destinations added.'); sys.exit(1)
        for q,v in s['queues'].items(): print(f"device for {q}: {v['uri']}")
    elif args[0]=='-p':
        q=args[-1]; print(f"printer {q} {'is idle.' if s['queues'][q]['enabled'] else 'disabled since never'}")
    elif args[0]=='-W' and s['queues'][args[-1]].get('pending'): print(args[-1]+'-1 user 1000')
elif name=='launchctl':
    op=args[0]
    if op=='print-disabled':
        for label in s['disabled']: print(f'"{label}" => true')
    elif op=='print':
        label=args[1][7:]
        if label not in s['loaded']: sys.exit(1)
        print(args[1]+' = {')
    else:
        label=args[1][7:]
        if op=='disable' and label not in s['disabled']: s['disabled'].append(label)
        if op=='enable' and label in s['disabled']: s['disabled'].remove(label)
        if op=='bootout' and label in s['loaded']: s['loaded'].remove(label)
elif name=='lpadmin':
    if args[0]=='-x':
        q=args[1]; s['queues'].pop(q,None); (root/'PPDs'/f'{q}.ppd').unlink(missing_ok=True)
    else:
        q=args[args.index('-p')+1]
        v=s['queues'].setdefault(q,{'enabled':False,'pending':False})
        v['uri']=args[args.index('-v')+1]
        shutil.copyfile(args[args.index('-P')+1],root/'PPDs'/f'{q}.ppd')
        if '-D' in args: v['description']=args[args.index('-D')+1]
elif name in {'cupsenable','cupsdisable','cupsaccept','cancel'}:
    q=args[-1]
    if name=='cupsenable': s['queues'][q]['enabled']=True
    if name=='cupsdisable': s['queues'][q]['enabled']=False
    if name=='cancel': s['queues'][q]['pending']=False
elif name=='cupstestppd':
    if not Path(args[-1]).is_file(): sys.exit(1)
elif name=='lp':
    assert args[args.index('-n')+1]=='1'
    assert s['queues'][args[args.index('-d')+1]]['enabled']
    print('request id is FIXTURE-1 (1 file(s))')
else: raise RuntimeError('Unhandled mock '+name)
save()
