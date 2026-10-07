#!/usr/bin/env python3
# usage: summ.py <matrix file>: per video id one line: captures, kind(s), colour of the eyes, frames equal, declarations
import sys, re, collections
cur=None; d=collections.OrderedDict()
for l in open(sys.argv[1]):
    if l.startswith('=='):
        cur=l.split()[1].rstrip(':'); d[cur]={'decl':re.search(r'declarations=(\d+)',l).group(1),'caps':[]}
    elif ' video=' in l and cur:
        m=re.search(r'(mono|stereo) video=\[([^\]]*)\] colour=\[([^\]]*)\].*?(FRAMES-EQUAL|FRAMES-DIFFER)(?: eyes_differ_bbox=(.+?) outside=(\d+))?\s*$',l)
        d[cur]['caps'].append(m.groups())
for k,v in d.items():
    c=v['caps']; kinds=set(x[0] for x in c); cols=set(x[2] for x in c); eq=sum(1 for x in c if x[3]=='FRAMES-EQUAL'); out=set(x[5] for x in c if x[5] is not None)
    print('%-12s captures=%d kind=%s eye colours=%s frames-equal=%d/%d outside-differ=%s declarations=%s'%(k,len(c),'/'.join(sorted(kinds)),'|'.join(sorted(cols)),eq,len(c),','.join(sorted(out)) or '-',v['decl']))
