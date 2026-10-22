#!/usr/bin/env python3
"""Audit source coverage of staged candidates without publishing or copying them."""
from pathlib import Path
import json,subprocess,sys,hashlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
n=cfg.path('SPARKY_RUN_RECORD');b=cfg.path('SPARKY_MIGRATION_WORK');repo=cfg.path('SPARKY_REPO_DIR')
sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas
progress=json.loads((n/'migration-progress.json').read_text());archives={Path(r['archive']) for r in progress['archives']}
initial=json.loads((n/'current-packages.json').read_text())
for row in initial:
 if row.get('Sparky-Lean-Code','').startswith('lc1 '):archives.add(repo/row['Filename'])
descriptors={};collisions=[]
paths=set(repo.joinpath('source').glob('*.dsc'))
for archive in archives:paths.update(archive.parent.glob('*.dsc'))
for path in sorted(paths):
 text=path.read_text()
 if text.startswith('-----BEGIN PGP SIGNED MESSAGE-----'):
  text=text.split('\n\n',1)[1].split('\n-----BEGIN PGP SIGNATURE-----',1)[0];text='\n'.join(l[2:] if l.startswith('- ') else l for l in text.splitlines())
 rows=list(stanzas(text));f=next((x for x in rows if 'source' in x and 'version' in x),None)
 if f is None:continue
 key=(f['source'],f['version']);digest=hashlib.sha256(path.read_bytes()).hexdigest()
 old=descriptors.get(key)
 if old and old['sha256']!=digest:collisions.append({'source':key,'descriptors':[old['path'],str(path)]})
 else:descriptors[key]={'path':str(path),'sha256':digest,'fields':f}
missing={};covered={}
for archive in sorted(archives):
 f=next(stanzas(subprocess.check_output(['dpkg-deb','-f',str(archive)],text=True)))
 source=f.get('source',f['package']);name=source.split()[0];version=source.split('(',1)[1].rstrip(')') if '(' in source else f['version'];key=(name,version)
 dest=covered if key in descriptors else missing
 dest.setdefault(key,[]).append({'package':f['package'],'architecture':f['architecture'],'archive':str(archive)})
report={'scope':'source identity coverage of candidates, not full archive or dependency qualification','archives':len(archives),'covered_source_groups':len(covered),'missing':[{'source':k[0],'version':k[1],'binaries':v} for k,v in sorted(missing.items())],'descriptor_collisions':collisions,'matched':[{'source':k[0],'version':k[1],'descriptor':descriptors[k]['path'],'binary_count':len(v)} for k,v in sorted(covered.items())]}
(n/'candidate-source-coverage.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='matched'},indent=2))
