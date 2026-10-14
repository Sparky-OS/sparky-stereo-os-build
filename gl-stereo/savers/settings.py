#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from catalogue import load
from preferences import disabled_savers, save_disabled

def main(share=Path('/usr/share/gl-stereo')):
    languages=json.loads(Path(__file__).with_name('strings.json').read_text())
    locale=os.environ.get('LC_ALL') or os.environ.get('LC_MESSAGES') or os.environ.get('LANG','en')
    locale=locale.split('.')[0].split('@')[0]
    text=languages.get(locale,languages.get(locale.split('_')[0],languages['en']))
    inventory=json.loads((share/'savers.json').read_text())
    qualified={entry['id'] for entry in load(share/'catalogue.json')}
    excluded=disabled_savers()
    root=tk.Tk(); root.title(text[0])
    frame=ttk.Frame(root,padding=16); frame.pack(fill='both',expand=True)
    ttk.Label(frame,text=text[1]).pack(anchor='w',pady=(0,8))
    area=ttk.Frame(frame); area.pack(fill='both',expand=True)
    tree=ttk.Treeview(area,columns=('status','authors'),show='tree headings',selectmode='none',height=20)
    tree.heading('#0',text=text[2]); tree.column('#0',width=260)
    tree.heading('status',text=text[3]); tree.column('status',width=170)
    tree.heading('authors',text=text[4]); tree.column('authors',width=380)
    bar=ttk.Scrollbar(area,orient='vertical',command=tree.yview); tree.configure(yscrollcommand=bar.set)
    tree.pack(side='left',fill='both',expand=True); bar.pack(side='right',fill='y')
    entries={entry['id']:entry for entry in inventory if entry.get('kind','hack')=='hack'}
    def label(name):
        mark='☑' if name in qualified and name not in excluded else '☐'
        return mark+' '+entries[name].get('title',name)
    for name in sorted(entries,key=lambda key:entries[key].get('title',key).casefold()):
        entry=entries[name]
        state=text[5] if name in qualified else text[6]
        tree.insert('','end',iid=name,text=label(name),values=(state,', '.join(entry.get('authors',[]))))
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
