# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
from urllib.parse import parse_qs
import base64,subprocess,json,sys
p=Path('/scratch');data=parse_qs((p/('callback-'+(sys.argv[1] if len(sys.argv)>1 else '0')+'.body')).read_text())
(p/'login-signature.bin').write_bytes(base64.b64decode(data['assinatura'][0]))
(p/'login-chain.der').write_bytes(base64.b64decode(data['cadeiaCertificado'][0]))
(p/'login-challenge').write_bytes(b'SYNTHETIC CHALLENGE')
(p/'wrong-challenge').write_bytes(b'ALTERED CHALLENGE')
def run(a):
 r=subprocess.run(a,capture_output=True,text=True);print(' '.join(a),r.returncode,r.stdout,r.stderr);return r
raw=(p/'login-chain.der').read_bytes()
def tlv(buf,pos):
 start=pos;tag=buf[pos];pos+=1;n=buf[pos];pos+=1
 if n & 128:
  count=n&127;assert 0<count<5;n=int.from_bytes(buf[pos:pos+count],'big');pos+=count
 end=pos+n;assert end<=len(buf);return tag,pos,end,start
_,start,end,_=tlv(raw,0);assert end==len(raw)
certs=[];pos=start
while pos<end:
 tag,body,nextpos,first=tlv(raw,pos);assert tag==48
 dest=p/('login-cert-'+str(len(certs))+'.der');dest.write_bytes(raw[first:nextpos])
 pem=dest.with_suffix('.pem')
 assert run(['openssl','x509','-inform','DER','-in',str(dest),'-out',str(pem)]).returncode==0
 certs.append(pem);pos=nextpos
assert len(certs)==(int(sys.argv[2]) if len(sys.argv)>2 else 2)
print('PkiPath certificates='+str(len(certs)))
leaf=None
for cert in certs:
 subject=run(['openssl','x509','-in',str(cert),'-noout','-subject']).stdout
 if 'SIGNER TEST ONLY' in subject:leaf=cert
assert leaf is not None
assert run(['openssl','verify','-CAfile','/scratch/identity/root.pem',str(leaf)]).returncode==0
(p/'login-chain.pem').write_bytes(leaf.read_bytes())
r=run(['openssl','x509','-in','/scratch/login-chain.pem','-pubkey','-noout']);(p/'login-public.pem').write_text(r.stdout)
assert run(['openssl','dgst','-sha256','-verify','/scratch/login-public.pem','-signature','/scratch/login-signature.bin','/scratch/login-challenge']).returncode==0
assert run(['openssl','dgst','-sha256','-verify','/scratch/login-public.pem','-signature','/scratch/login-signature.bin','/scratch/wrong-challenge']).returncode!=0
print('PASS: application login signature, chain and altered-challenge control; raw login signature has no CMS signed attributes.')
