#!/usr/bin/python3
"""A frontend's explicit language list also selects the shared model notices."""
import importlib.util,os,tempfile
from pathlib import Path
from unittest.mock import patch
module=Path(__file__).resolve().parents[1]/'install-downloads/sparky_install_downloads.py'
spec=importlib.util.spec_from_file_location('reader',module);reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
with tempfile.TemporaryDirectory() as directory:
    for code in ['en','pl','pt_BR','fr','de','es','ja','ko','zh_CN','zh_TW']:(Path(directory)/(code+'.json')).write_text('{}')
    with patch.object(reader,'LANGDIR',directory):
        for code in ['en','pl','pt_BR','fr','de','es','ja','ko','zh_CN','zh_TW']:
            with patch.dict(os.environ,LANGUAGE=code,LC_ALL='C.UTF-8'):
                assert reader.language()==code,(code,reader.language())
        for preferred,expected in [('es_MX:en','es'),('zz_ZZ:pt_BR','pt_BR'),('zh_HK','zh_TW'),('pt_PT','pt_BR')]:
            with patch.dict(os.environ,LANGUAGE=preferred,LC_ALL='C.UTF-8'):
                assert reader.language()==expected,(preferred,reader.language())
print('PASS ten explicit frontend languages, bare Spanish and locale-list fallback')
