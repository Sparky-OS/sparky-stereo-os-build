import re,sys
cur=None; d={}; order=[]
for l in open(sys.argv[1]):
    if l.startswith('=='):
        cur=l.split()[1].rstrip(':'); order.append(cur)
        d[cur]={'decl':re.search(r'declarations=(\d+)',l).group(1),'caps':[]}
    elif ' frame=' in l and cur:
        m=re.search(r'(mono|stereo) frame=\[([^\]]*)\] colour=\[([^\]]*)\].*?(FRAMES-EQUAL|FRAMES-DIFFER)(?: outside_video_differ=(\d+) controls_differ=(-?\d+))?',l)
        d[cur]['caps'].append(m.groups())
for k in order:
    v=d[k]; c=v['caps']
    print('%-34s decl=%s caps=%d kind=%s colours=%s eq=%d/%d outside=%s controls=%s'%(k.split('-',1)[1],v['decl'],len(c),'/'.join(sorted({x[0] for x in c})),'|'.join(sorted({x[2] for x in c})),sum(x[3]=='FRAMES-EQUAL' for x in c),len(c),','.join(sorted({x[4] for x in c if x[4]})) or '-',','.join(sorted({x[5] for x in c if x[5]})) or '-'))
