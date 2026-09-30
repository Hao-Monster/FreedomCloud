/// Python 3 supplies bounded ZIP/JSON/filesystem handling; OpenSSL performs CMS
/// verification. macOS additionally requires Developer ID codesign + Gatekeeper.
const unixSignedUpdater = r'''
import os, sys, json, hashlib, pathlib, subprocess, tempfile, zipfile, stat, time, shutil, re, fcntl
P = pathlib.Path
job = json.loads(P(sys.argv[1]).read_text())
root = P(job['root']).absolute()

def run(args, **kwargs):
    value = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, **kwargs)
    if value.returncode:
        raise RuntimeError(value.stderr.decode(errors='replace').strip() or 'Command failed: '+args[0])
    return value.stdout

def digest(path):
    result=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(65536),b''): result.update(block)
    return result.hexdigest()

def no_links(path):
    path=P(path).absolute()
    for part in [path,*path.parents]:
        if part.is_symlink(): raise RuntimeError('Symlink in updater-owned path')

def atomic(path,value):
    fd,tmp=tempfile.mkstemp(prefix='.state-',dir=root)
    try:
        with os.fdopen(fd,'w') as stream:
            json.dump(value,stream); stream.flush(); os.fsync(stream.fileno())
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def relative(value):
    if not isinstance(value,str) or not value or chr(92) in value or chr(0) in value or value.startswith('/'):
        raise RuntimeError('Invalid manifest path')
    if any(part in ('','.','..') for part in value.split('/')): raise RuntimeError('Unsafe manifest path')
    return value

def manifest(path):
    with tempfile.TemporaryDirectory(prefix='cms-',dir=root) as temporary:
        data=P(temporary)/'content'; signer=P(temporary)/'signer.pem'
        run(['openssl','cms','-verify','-binary','-inform','DER','-in',str(path),'-noverify','-out',str(data),'-signer',str(signer)])
        pem=signer.read_text()
        if pem.count('-----BEGIN CERTIFICATE-----')!=1: raise RuntimeError('Exactly one publisher signer required')
        der=run(['openssl','x509','-in',str(signer),'-outform','DER'])
        if hashlib.sha256(der).hexdigest().upper()!=job['pin']: raise RuntimeError('Release publisher does not match compiled pin')
        details=run(['openssl','cms','-cmsout','-print','-inform','DER','-in',str(path)]).decode()
        algorithms=re.findall(r'digestAlgorithm[s]?:\s*(?:algorithm:\s*)?(sha[0-9]+)',details)
        if not algorithms or any(a not in ('sha256','sha384','sha512') for a in algorithms): raise RuntimeError('Unsupported CMS digest')
        m=json.loads(data.read_text())
    expected='macos-app-zip' if sys.platform=='darwin' else 'portable-zip'
    if m.get('schema')!=1 or m.get('format')!=expected or not re.fullmatch(r'[a-fA-F0-9]{64}',m.get('sha256','')):
        raise RuntimeError('Incompatible signed manifest')
    relative(m['entry'])
    return m

def mac_verify(directory,m):
    bundle=directory if directory.suffix=='.app' else directory/'FlClashX.app'
    team=job.get('macTeam','')
    if not re.fullmatch(r'[A-Z0-9]{10}',team): raise RuntimeError('FCX_MACOS_TEAM_ID is required')
    requirement='anchor apple generic and certificate leaf[subject.OU] = "'+team+'" and identifier "com.follow.clash"'
    run(['/usr/bin/codesign','--verify','--deep','--strict','-R',requirement,str(bundle)])
    run(['/usr/sbin/spctl','--assess','--type','execute','--verbose=2',str(bundle)])
    core=bundle/'Contents/MacOS/FlClashCore'
    run(['/usr/bin/codesign','--verify','--strict','-R','anchor apple generic and certificate leaf[subject.OU] = "'+team+'"',str(core)])

def inventory(directory):
    result={}
    for parent,dirs,files in os.walk(directory,followlinks=False):
        for name in list(dirs)+files:
            file=P(parent)/name
            if file.is_dir() and not file.is_symlink(): continue
            key=file.relative_to(directory).as_posix()
            if file.is_symlink():
                target=os.readlink(file)
                result[key]={'type':'symlink','target':target,'sha256':hashlib.sha256(target.encode()).hexdigest(),'size':len(target.encode()),'mode':0o777}
            else:
                if not file.is_file(): raise RuntimeError('Special file in application package')
                result[key]={'type':'file','sha256':digest(file),'size':file.stat().st_size,'mode':stat.S_IMODE(file.stat().st_mode)}
    return result

def verify_release(directory):
    no_links(directory)
    m=manifest(directory/'release.p7m')
    records={relative(r['path']):r for r in m['files']}
    actual=inventory(directory); actual.pop('release.p7m',None)
    if set(records)!=set(actual): raise RuntimeError('Application inventory changed')
    for name,record in records.items():
        item=actual[name]
        for key in ('type','sha256','size','mode'):
            if item[key]!=record[key]: raise RuntimeError('Application file differs from signed inventory: '+name)
        if item['type']=='symlink':
            if item['target']!=record['target']: raise RuntimeError('Symlink differs from manifest')
            resolved=(directory/name).resolve()
            if not resolved.is_relative_to(directory.resolve()): raise RuntimeError('Symlink escapes application')
    if sys.platform=='darwin': mac_verify(directory,m)
    return directory/relative(m['entry'])

def pointer(value):
    directory=P(value['directory']).absolute(); no_links(directory); directory=directory.resolve()
    if value['kind']=='release':
        if not directory.is_relative_to((root/'versions').resolve()): raise RuntimeError('Release pointer outside cache')
        return verify_release(directory)
    if value['kind']!='baseline': raise RuntimeError('Unknown version pointer')
    if inventory(directory)!=value['files']: raise RuntimeError('Original installation changed; rollback refused')
    if sys.platform=='darwin': mac_verify(directory,{})
    return directory/relative(value['entry'])

def preflight():
    no_links(root)
    if sys.version_info<(3,9): raise RuntimeError('Python 3.9 or newer is required for safe updater filesystem handling')
    run(['openssl','cms','-help'])
    if sys.platform=='darwin' and not re.fullmatch(r'[A-Z0-9]{10}',job.get('macTeam','')): raise RuntimeError('FCX_MACOS_TEAM_ID must be compiled into the client')

def stage():
    preflight(); m=manifest(P(job['manifest']))
    package=P(job['archive'])
    if package.stat().st_size!=m['size'] or digest(package)!=m['sha256'].lower(): raise RuntimeError('Package integrity mismatch')
    if not 1<=len(m['files'])<=20000: raise RuntimeError('Invalid inventory length')
    records={}; total=0
    for record in m['files']:
        name=relative(record['path'])
        if name=='release.p7m' or name.casefold() in records: raise RuntimeError('Duplicate/reserved path')
        if record['type'] not in ('file','symlink') or not re.fullmatch(r'[a-f0-9]{64}',record['sha256']): raise RuntimeError('Invalid file descriptor')
        if not 0<=record['size']<=1073741824: raise RuntimeError('Expanded file too large')
        if record['mode'] not in (0o644,0o755,0o777) or (record['type']=='file' and record['mode']==0o777): raise RuntimeError('Unsafe file permissions')
        total+=record['size']
        if total>8589934592: raise RuntimeError('Expanded archive too large')
        records[name.casefold()]=record
    required=['FlClashX.app/Contents/MacOS/FlClashX','FlClashX.app/Contents/MacOS/FlClashCore'] if sys.platform=='darwin' else ['FlClashX','FlClashCore','FlClashAgent']
    if any(name.casefold() not in records for name in required) or m['entry']!=required[0]: raise RuntimeError('Incomplete application distribution')
    versions=root/'versions'; versions.mkdir(exist_ok=True); no_links(versions)
    destination=versions/m['sha256'].lower()
    if destination.exists(): verify_release(destination); return
    working=P(tempfile.mkdtemp(prefix='.staging-',dir=versions)); seen=set(); links=[]
    with zipfile.ZipFile(package) as archive:
        for entry in archive.infolist():
            if entry.is_dir(): continue
            name=relative(entry.filename); record=records.get(name.casefold())
            if record is None or record['path']!=name or name.casefold() in seen or entry.file_size!=record['size']: raise RuntimeError('ZIP differs from signed inventory')
            seen.add(name.casefold())
            target=working/name
            target.parent.mkdir(parents=True,exist_ok=True)
            if record['type']=='symlink':
                raw=archive.read(entry)
                link=raw.decode('utf-8')
                if link!=record['target'] or hashlib.sha256(raw).hexdigest()!=record['sha256'] or os.path.isabs(link): raise RuntimeError('Invalid archive symlink')
                resolved=(target.parent/link).resolve()
                if not resolved.is_relative_to(working.resolve()): raise RuntimeError('Symlink escapes package')
                links.append((target,link)); continue
            with archive.open(entry) as source,open(target,'xb') as output:
                written=0
                while True:
                    block=source.read(65536)
                    if not block: break
                    written+=len(block)
                    if written>record['size']: raise RuntimeError('ZIP expansion exceeds signed size')
                    output.write(block)
            if written!=record['size'] or digest(target)!=record['sha256']: raise RuntimeError('Extracted file integrity failure')
            os.chmod(target,record['mode'])
    if len(seen)!=len(records): raise RuntimeError('Missing ZIP files')
    for target,link in links: os.symlink(link,target)
    shutil.copyfile(job['manifest'],working/'release.p7m')
    verify_release(working); os.rename(working,destination)

def start(executable):
    if sys.platform=='darwin': args=['/usr/bin/open','-W','-n',str(executable.parents[2])]
    else: args=[str(executable)]
    return subprocess.Popen(args,cwd=executable.parent,start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def apply():
    preflight()
    with open(root/'transaction.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        current=root/'current.json'; previous=root/'previous.json'
        if job['action']=='launch': start(pointer(json.loads(current.read_text()))); return
        if current.exists(): old=json.loads(current.read_text())
        else:
            exe=P(job['currentExe']).absolute()
            directory=exe.parents[2] if sys.platform=='darwin' else exe.parent
            old={'kind':'baseline','directory':str(directory),'entry':str(exe.relative_to(directory)),'files':inventory(directory)}
        if job['action']=='rollback': new=json.loads(previous.read_text())
        else:
            m=manifest(P(job['manifest'])); new={'kind':'release','directory':str(root/'versions'/m['sha256'].lower())}
        target=pointer(new); pointer(old)
        deadline=time.monotonic()+60
        while True:
            try: os.kill(job['parentPid'],0)
            except ProcessLookupError: break
            if time.monotonic()>deadline: raise RuntimeError('Application did not exit; update not applied')
            time.sleep(.2)
        atomic(previous,old); atomic(current,new)
        try:
            child=start(target)
            try: child.wait(timeout=8)
            except subprocess.TimeoutExpired: pass
            else: raise RuntimeError('Updated app exited during startup')
        except Exception:
            atomic(current,old); start(pointer(old)); raise
        shutil.copyfile(__file__,root/'launch.py')
        atomic(root/'launch.json',{'action':'launch','root':str(root),'pin':job['pin'],'macTeam':job.get('macTeam','')})
        if sys.platform=='darwin':
            launcher=root/'FreedomCloud Updated.command'
            import shlex
            launcher.write_text('#!/bin/sh\nexec '+shlex.quote(sys.executable)+' '+shlex.quote(str(root/'launch.py'))+' '+shlex.quote(str(root/'launch.json'))+'\n')
            launcher.chmod(0o755)
        else:
            desktop=P.home()/'.local/share/applications'; desktop.mkdir(parents=True,exist_ok=True)
            def quote(value): return chr(34)+str(value).replace(chr(92),chr(92)*2).replace(chr(34),chr(92)+chr(34)).replace(chr(96),chr(92)+chr(96)).replace(chr(36),chr(92)+chr(36)).replace(chr(37),chr(37)*2)+chr(34)
            (desktop/'freedomcloud-updated.desktop').write_text('[Desktop Entry]\nType=Application\nName=FreedomCloud Updated\nExec='+quote(sys.executable)+' '+quote(root/'launch.py')+' '+quote(root/'launch.json')+'\nTerminal=false\n')
        atomic(root/'last-result.json',{'state':'launched-awaiting-user-acceptance'})

try:
    action=job['action']
    if action=='preflight': preflight()
    elif action=='manifest': print(json.dumps(manifest(P(job['manifest']))))
    elif action=='stage': stage()
    elif action=='checkRollback': pointer(json.loads((root/'previous.json').read_text()))
    elif action in ('apply','rollback','launch'): apply()
    else: raise RuntimeError('Unknown updater action')
except Exception as error:
    atomic(root/'last-result.json',{'state':'failed','reason':str(error)})
    print(str(error),file=sys.stderr); sys.exit(1)
''';
