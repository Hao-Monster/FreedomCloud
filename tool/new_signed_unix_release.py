#!/usr/bin/env python3
"""Publish a complete Unix desktop ZIP and attached CMS manifest.

No network upload is performed. --certificate and --key name local PEM files;
FCX_SIGNING_KEY_PASSWORD may provide an encrypted-key password to OpenSSL.
macOS input must be a Developer ID signed/notarized FlClashX.app. The client
independently enforces its compiled FCX_MACOS_TEAM_ID and Gatekeeper policy.
"""
import argparse, datetime, hashlib, json, os, pathlib, re, stat, subprocess, tempfile, zipfile
P=pathlib.Path
parser=argparse.ArgumentParser()
for name in ('bundle','output','version','target','url','certificate','key'): parser.add_argument('--'+name,required=True)
args=parser.parse_args()
if not re.fullmatch(r'(linux|macos)-(x64|arm64)',args.target): parser.error('target must be linux/macos x64/arm64')
if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?',args.version): parser.error('SemVer version required')
from urllib.parse import urlparse
url=urlparse(args.url)
if url.scheme!='https' or not url.hostname or url.username: parser.error('direct HTTPS artifact URL required')
bundle=P(args.bundle).resolve(); output=P(args.output).resolve()
if output==bundle or output.is_relative_to(bundle): parser.error('output must be outside bundle')
mac=args.target.startswith('macos')
if mac and bundle.name!='FlClashX.app': parser.error('macOS bundle must be named FlClashX.app')
output.mkdir(parents=True,exist_ok=True)
archive=output/('FreedomCloud-'+args.version+'-'+args.target+'.zip')
envelope=archive.with_suffix('.p7m')
if archive.exists() or envelope.exists(): parser.error('refusing to overwrite release')

def run(command):
    result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    return result.stdout

def digest(file):
    result=hashlib.sha256()
    with open(file,'rb') as stream:
        for block in iter(lambda:stream.read(65536),b''): result.update(block)
    return result.hexdigest()

if mac:
    run(['/usr/bin/codesign','--verify','--deep','--strict',str(bundle)])
    run(['/usr/sbin/spctl','--assess','--type','execute',str(bundle)])
records=[]; paths=[]
for parent,dirs,files in os.walk(bundle,followlinks=False):
    for name in sorted(list(dirs)+files):
        file=P(parent)/name
        if file.is_dir() and not file.is_symlink(): continue
        relative=file.relative_to(bundle).as_posix()
        if mac: relative='FlClashX.app/'+relative
        if relative=='release.p7m': parser.error('remove prior CMS envelope from input')
        if file.is_symlink():
            target=os.readlink(file)
            if os.path.isabs(target) or not file.resolve().is_relative_to(bundle): parser.error('symlink escapes bundle')
            raw=target.encode(); mode=0o777
            record={'path':relative,'type':'symlink','target':target,'size':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'mode':mode}
        else:
            if not file.is_file(): parser.error('special files are not supported')
            mode=0o755 if file.stat().st_mode & 0o111 else 0o644
            record={'path':relative,'type':'file','size':file.stat().st_size,'sha256':digest(file),'mode':mode}
        records.append(record); paths.append(file)
required=['FlClashX.app/Contents/MacOS/FlClashX','FlClashX.app/Contents/MacOS/FlClashCore'] if mac else ['FlClashX','FlClashCore','FlClashAgent']
if any(name not in {record['path'] for record in records} for name in required): parser.error('incomplete application distribution')
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as target:
    for record,file in zip(records,paths):
        info=zipfile.ZipInfo(record['path']); info.create_system=3
        info.external_attr=((stat.S_IFLNK if record['type']=='symlink' else stat.S_IFREG)|record['mode'])<<16
        info.compress_type=zipfile.ZIP_DEFLATED
        if record['type']=='symlink': target.writestr(info,record['target'].encode())
        else:
            with open(file,'rb') as source,target.open(info,'w') as destination:
                while True:
                    block=source.read(65536)
                    if not block: break
                    destination.write(block)
manifest={'schema':1,'version':args.version,'target':args.target,'format':'macos-app-zip' if mac else 'portable-zip',
          'entry':required[0],'url':args.url,'size':archive.stat().st_size,'sha256':digest(archive),'files':records,
          'expiresUtc':(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=7)).isoformat()}
with tempfile.TemporaryDirectory(prefix='fcx-release-') as temporary:
    payload=P(temporary)/'release.json'; payload.write_text(json.dumps(manifest,separators=(',',':')))
    command=['openssl','cms','-sign','-binary','-nodetach','-md','sha256','-in',str(payload),'-signer',args.certificate,'-inkey',args.key,'-outform','DER','-out',str(envelope)]
    if 'FCX_SIGNING_KEY_PASSWORD' in os.environ: command+=['-passin','env:FCX_SIGNING_KEY_PASSWORD']
    run(command)
der=run(['openssl','x509','-in',args.certificate,'-outform','DER'])
print('FCX_RELEASE_CERT_SHA256='+hashlib.sha256(der).hexdigest().upper())
print('Publish',archive,'at the declared artifact URL; publish',envelope,'as FCX_RELEASE_MANIFEST_URL.')
