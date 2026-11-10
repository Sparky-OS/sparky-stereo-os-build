#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from catalogue import dropped, load
from preferences import disabled_savers, save_disabled

KINDS = {'executable-differs': 12, 'executable-missing': 13, 'library-missing': 13, 'settings-missing': 13,
         'settings-differs': 14, 'library-differs': 15, 'proof': 16}

def reason_text(reason, text):
    """The sentence the person reads for one reason catalogue.diagnose gave, in their language."""
    template = text[KINDS.get(reason['kind'], 17)]
    if reason['kind'] in ('proof',) or reason['kind'] not in KINDS:
        return template
    if reason['kind'].endswith('-missing'):
        return template % (reason['path'], reason['expected'])
    return template % (reason['path'], reason['expected'], reason['found'])

def main(share=Path('/usr/share/gl-stereo')):
    languages=json.loads(Path(__file__).with_name('strings.json').read_text())
    locale=os.environ.get('LC_ALL') or os.environ.get('LC_MESSAGES') or os.environ.get('LANG','en')
    locale=locale.split('.')[0].split('@')[0]
    text=languages.get(locale,languages.get(locale.split('_')[0],languages['en']))
    inventory=json.loads((share/'savers.json').read_text())
    qualified={entry['id'] for entry in load(share/'catalogue.json')}
    # a saver the package ships a receipt for that cannot be offered here is named with the reason, never just left out
    gone={name: ' '.join(reason_text(reason, text) for reason in reasons)
          for name, reasons in dropped(json.loads((share/'catalogue.json').read_text()))}
    excluded=disabled_savers()
    root=tk.Tk(); root.title(text[0])
    frame=ttk.Frame(root,padding=16); frame.pack(fill='both',expand=True)
    ttk.Label(frame,text=text[1]).pack(anchor='w',pady=(0,8))
    if gone:
        shipped=len([entry for entry in inventory if entry.get('kind','hack')=='hack'])
        ttk.Label(frame,text=text[11]%dict(dropped=len(gone),shipped=shipped)).pack(anchor='w',pady=(0,8))
    area=ttk.Frame(frame); area.pack(fill='both',expand=True)
    tree=ttk.Treeview(area,columns=('status','authors','why'),show='tree headings',selectmode='none',height=20)
    tree.heading('#0',text=text[2]); tree.column('#0',width=260)
    tree.heading('status',text=text[3]); tree.column('status',width=170)
    tree.heading('authors',text=text[4]); tree.column('authors',width=380)
    tree.heading('why',text=text[10]); tree.column('why',width=520)
    bar=ttk.Scrollbar(area,orient='vertical',command=tree.yview); tree.configure(yscrollcommand=bar.set)
    tree.pack(side='left',fill='both',expand=True); bar.pack(side='right',fill='y')
    entries={entry['id']:entry for entry in inventory if entry.get('kind','hack')=='hack'}
    def label(name):
        mark='☑' if name in qualified and name not in excluded else '☐'
        return mark+' '+entries[name].get('title',name)
    for name in sorted(entries,key=lambda key:entries[key].get('title',key).casefold()):
        entry=entries[name]
        state=text[5] if name in qualified else text[9] if name in gone else text[6]
        tree.insert('','end',iid=name,text=label(name),values=(state,', '.join(entry.get('authors',[])),gone.get(name,'')))
    def toggle(event=None):
        name=tree.identify_row(event.y) if event and event.type==tk.EventType.ButtonPress else tree.focus()
        if name not in qualified: return
        if name in excluded: excluded.remove(name)
        else: excluded.add(name)
        tree.item(name,text=label(name))
    tree.bind('<Button-1>',toggle); tree.bind('<space>',toggle)
    ttk.Label(frame,text=text[7]).pack(anchor='w',pady=8)
    def save(): save_disabled(excluded); root.destroy()
    ttk.Button(frame,text=text[8],command=save).pack(anchor='e')
    root.mainloop()

if __name__=='__main__': main()
