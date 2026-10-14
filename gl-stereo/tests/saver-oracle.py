# SPDX-License-Identifier: GPL-2.0-or-later
"""Dim geometry qualifies; empty, uniform and reversed eyes never do."""
import importlib.util
from pathlib import Path
import shutil
import sys
import numpy as np
from PIL import Image
spec=importlib.util.spec_from_file_location('oracle',Path(__file__).resolve().parent.parent/'measure-hack.py')
oracle=importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
source=sorted(Path(sys.argv[1]).glob('frame-*.ppm'))[-1]
root=Path(sys.argv[2]); root.mkdir(parents=True,exist_ok=True)
original=np.array(Image.open(source)); width=original.shape[1]//2
for mode in ('control','empty','uniform','reversed'):
    directory=root/mode; directory.mkdir(exist_ok=True)
    target=directory/'frame-1.ppm'
    image=original.copy()
    if mode=='empty': image[:,:width]=0
    elif mode=='uniform': image[:,:width]=[255,0,0]
    elif mode=='reversed': image=np.concatenate((image[:,width:],image[:,:width]),axis=1)
    Image.fromarray(image).save(target)
    for suffix in ('.depth','.txt'): shutil.copyfile(source.with_suffix(suffix),target.with_suffix(suffix))
    try:
        oracle.check(target)
    except AssertionError as error:
        assert mode!='control',error
        if mode in ('empty','uniform'): assert str(error)=='uniform eye',error
        print(mode,'rejected:',error)
    else: assert mode=='control',f'{mode} falsely passed'
print('PASS: dim reference and empty/uniform/reversed negative controls')
