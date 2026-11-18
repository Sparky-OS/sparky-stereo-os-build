# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import json,urllib.request,sys,urllib.error
kind=sys.argv[1]
if kind=='login': taskid='cnj.autenticador';task={'enviarPara':'/login','mensagem':'SYNTHETIC CHALLENGE','algoritmoAssinatura':'SHA256withRSA'}
else: taskid='cnj.assinador';task={'modo':'DEFINIDO','enviarPara':'samefolder','padraoAssinatura':'CADES','tipoAssinatura':'ATTACHED','algoritmoHash':'SHA256withRSA','arquivos':[{'url':'/scratch/identity/document.pdf','nome':'document.pdf','terAtributosAssinados':True}]}
payload={'sessao':'SYNTHETIC','aplicacao':'TESTONLY','servidor':'http://127.0.0.1:18818/pje','codigoSeguranca':'bypass','tarefaId':taskid,'tarefa':json.dumps(task)}
req=urllib.request.Request('http://127.0.0.1:8800/pjeOffice/requisicao/?u=18',data=json.dumps(payload).encode(),method='PUT',headers={'Content-Type':'application/json','Force-Preflight':'true','Origin':'http://127.0.0.1:18818'})
try:
 with urllib.request.urlopen(req,timeout=120) as r: result={'status':r.status,'body':r.read().decode()}
except Exception as e:result={'error':str(e)}
Path('/scratch/request-'+kind+'-result.json').write_text(json.dumps(result,indent=2)+'\n')
