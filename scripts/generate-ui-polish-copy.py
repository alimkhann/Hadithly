#!/usr/bin/env python3
"""Synchronize the scoped UI-polish copy while preserving unrelated catalog content."""
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape
ROOT=Path(__file__).resolve().parents[1]
check='--check' in sys.argv
source=json.loads((ROOT/'docs/ui-polish-copy.json').read_text())
keys=source['keys']; locales=source['locales']
assert len(locales)==15 and all(len(values)==len(keys) and all(values) for values in locales.values())
ids={key:'native_'+hashlib.sha256(key.encode()).hexdigest()[:12] for key in keys}

def output(path,text):
    if check:
        assert path.exists() and path.read_text()==text, f'UI-polish copy out of date: {path.relative_to(ROOT)}'
    else:
        path.write_text(text)

def after_la2_prefix(text):
    cursor=re.search(r'"strings"\s*:\s*\{',text).end()
    while True:
        cursor+=len(text[cursor:])-len(text[cursor:].lstrip())
        key,end=decoder.raw_decode(text,cursor)
        if not key.startswith('la2.'): return cursor
        value_start=text.index(':',end)+1
        value_start+=len(text[value_start:])-len(text[value_start:].lstrip())
        _,cursor=decoder.raw_decode(text,value_start)
        cursor+=len(text[cursor:])-len(text[cursor:].lstrip())
        if text[cursor]==',': cursor+=1

catalog=ROOT/'ios/Hadithly/Localizable.xcstrings'
text=catalog.read_text(); decoder=json.JSONDecoder()
for i,key in enumerate(keys):
    quoted=json.dumps(key,ensure_ascii=False)
    match=re.search(r'^    '+re.escape(quoted)+r'\s*:\s*',text,re.M)
    entry,end=decoder.raw_decode(text,match.end()) if match else ({'extractionState':'manual','localizations':{}},0)
    for locale,values in locales.items():
        existing=entry.setdefault('localizations',{}).get(locale,{}).get('stringUnit',{})
        if existing.get('value') and existing['value']!=key and existing.get('state')=='translated':
            continue
        entry['localizations'][locale]={'stringUnit':{'state':'translated' if locale=='en' else 'needs_review','value':values[i]}}
    value=json.dumps(entry,ensure_ascii=False,indent=2).replace('\n','\n    ')
    if match: text=text[:match.end()]+value+text[end:]
    else:
        insertion=after_la2_prefix(text)
        text=text[:insertion]+quoted+' : '+value+',\n    '+text[insertion:]
json.loads(text);output(catalog,text)

folders={'en':'values','es-419':'values-b+es+419','pt-BR':'values-pt-rBR'}
for locale,values in locales.items():
    path=ROOT/'android/app/src/main/res'/folders.get(locale,'values-'+locale)/'native.xml'
    text=path.read_text() if path.exists() else '<resources>\n</resources>\n'
    for i,key in enumerate(keys):
        name=ids[key]
        raw=escape(values[i]).replace("'",r"\'").replace('"',r'\"')
        row=f'    <string name="{name}" formatted="false">{raw}</string>'
        pattern=re.compile(r'^[ \t]*<string\b[^>]*name="'+name+r'"[^>]*>.*?</string>',re.M)
        if pattern.search(text): text=pattern.sub(lambda _:row,text)
        else: text=text.replace('</resources>',row+'\n</resources>')
    draft_note='    <!-- UI-polish locale entries are generated drafts; native review pending. -->'
    if locale != 'en' and draft_note not in text:
        text=text.replace('</resources>',draft_note+'\n</resources>')
    ET.fromstring(text)
    output(path,text)
helper=ROOT/'android/app/src/main/kotlin/com/hadithly/app/core/preferences/NativeCopy.kt'
text=helper.read_text()
for key,name in ids.items():
    if f'-> R.string.{name}' not in text:
        text=text.replace('    else -> null',f'    {json.dumps(key,ensure_ascii=False)} -> R.string.{name}\n    else -> null')
output(helper,text)
print(f'UI-polish copy synchronized: {len(keys)} keys x {len(locales)} locales; native review pending.')
