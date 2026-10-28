#!/usr/bin/env python3
"""Synchronize the scoped UI-polish copy while preserving unrelated catalog content."""
import hashlib
import json
import re
import argparse
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
parser.add_argument('--source',default='docs/ui-polish-copy.json')
parser.add_argument('--android-only', action='store_true', help='Reuse existing iOS copy without writing its catalog')
args=parser.parse_args()
check=args.check
source=json.loads((ROOT/args.source).read_text())
keys=source['keys']; locales=source['locales']
if source.get('reuse_indexed_ios'):
    assert args.android_only, 'Indexed iOS reuse must not write the catalog'
    indexed=json.loads(subprocess.check_output(['git','show',':ios/Hadithly/Localizable.xcstrings'],cwd=ROOT,text=True))['strings']
    locales={locale:[indexed[key]['localizations'][locale]['stringUnit']['value'] for key in keys] for locale in locales}
assert len(locales)==15 and all(len(values)==len(keys) and all(values) for values in locales.values())
targets={key:source.get('android_resources',{}).get(key,[{'name':'native_'+hashlib.sha256(key.encode()).hexdigest()[:12],'file':'native.xml'}]) for key in keys}
for resources in targets.values():
    assert resources
    for resource in resources:
        assert re.fullmatch(r'[a-z][a-z0-9_]*',resource['name'])
        assert Path(resource['file']).name==resource['file'] and resource['file'].endswith('.xml')
ids={key:targets[key][0]['name'] for key in keys}

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
for i,key in enumerate(keys if not args.android_only else []):
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
json.loads(text)
if not args.android_only: output(catalog,text)

folders={'en':'values','es-419':'values-b+es+419','pt-BR':'values-pt-rBR','id':'values-in'}
for locale,values in locales.items():
    updates={}
    for i,key in enumerate(keys):
        android_value=re.sub(r'%(\d+\$)?@',lambda m:'%'+(m.group(1) or '')+'s',values[i])
        raw=escape(android_value).replace("'",r"\'").replace('"',r'\"')
        for resource in targets[key]:
            path=ROOT/'android/app/src/main/res'/folders.get(locale,'values-'+locale)/resource['file']
            text=updates.get(path,path.read_text() if path.exists() else '<resources>\n</resources>\n')
            name=resource['name']
            row=f'    <string name="{name}" formatted="false">{raw}</string>'
            pattern=re.compile(r'^[ \t]*<string\b[^>]*name="'+name+r'"[^>]*>.*?</string>',re.M|re.S)
            if pattern.search(text): text=pattern.sub(lambda _:row,text)
            else: text=text.replace('</resources>',row+'\n</resources>')
            updates[path]=text
    for path,text in updates.items():
        draft_note='    <!-- UI-polish locale entries are generated drafts; native review pending. -->'
        if locale != 'en' and draft_note not in text:
            text=text.replace('</resources>',draft_note+'\n</resources>')
        ET.fromstring(text)
        output(path,text)
helper=ROOT/'android/app/src/main/kotlin/com/hadithly/app/core/preferences/NativeCopy.kt'
text=helper.read_text()
for key,name in ids.items():
    quoted=json.dumps(key,ensure_ascii=False)
    kotlin_quoted=quoted.replace('$',r'\$')
    row=f'    {kotlin_quoted} -> R.string.{name}'
    pattern=re.compile(r'^[ \t]*(?:'+re.escape(quoted)+'|'+re.escape(kotlin_quoted)+r') -> R\.string\.\w+',re.M)
    if pattern.search(text):
        text=pattern.sub(lambda _:row,text)
    else:
        text=text.replace('    else -> null',row+'\n    else -> null')
output(helper,text)
print(f'UI-polish copy synchronized: {len(keys)} keys x {len(locales)} locales; native review pending.')
