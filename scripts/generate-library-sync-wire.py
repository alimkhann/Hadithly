#!/usr/bin/env python3
"""Generate native sync wire values from the actual Convex validators."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='hadithly-sync-contract-') as directory:
    environment = dict(os.environ, HADITHLY_LIBRARY_SYNC_CONTRACT_DIR=directory)
    result = subprocess.run(['npm', 'test', '--', 'convex/lib/librarySyncPolicy.test.ts'], cwd=ROOT/'backend', env=environment, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('Sync contract source tests failed; inspect backend tests.')
    parity_result = subprocess.run(['npm', 'test', '--', 'convex/librarySavedFacts.test.ts', '-t', 'source facts preserve canonical'], cwd=ROOT/'backend', env=environment, capture_output=True, text=True)
    if parity_result.returncode:
        raise SystemExit('Saved parity fixture source failed; inspect backend tests.')
    reads_result = subprocess.run(['npm', 'test', '--', 'convex/librarySavedReads.test.ts', '-t', 'metadata excludes passages'], cwd=ROOT/'backend', env=environment, capture_output=True, text=True)
    if reads_result.returncode:
        raise SystemExit('Saved read parity fixture source failed; inspect backend tests.')
    saved_reads_parity = json.loads((Path(directory)/'saved-reads-parity.json').read_text())
    saved_parity = json.loads((Path(directory)/'saved-parity.json').read_text())
    roots = json.loads((Path(directory)/'contract.json').read_text())
    limits = roots.pop('limits')
    intent_digests = roots.pop('intentDigests')

def signature(node): return json.dumps(node, sort_keys=True, separators=(',', ':'))
def pascal(value): return ''.join(part[:1].upper()+part[1:] for part in value.split('_'))
def camel(value): return value[:1].lower()+value[1:]
known = {signature(node): name for name, node in roots.items()}
definitions = {name: node for name, node in roots.items() if name != 'ReadingPosition'}
payloads = set()

def type_name(node, hint, language):
    basic = {'string':'String', 'id':'String', 'number':'Double', 'boolean':'Bool' if language=='swift' else 'Boolean'}
    if node['type'] in basic: return basic[node['type']]
    if node['type'] == 'array':
        child = type_name(node['value'], hint+'Item', language)
        return '['+child+']' if language=='swift' else 'List<'+child+'>'
    key = signature(node)
    if key in known: return known[key]
    if node['type'] == 'literal':
        return 'String' if isinstance(node['value'], str) else 'Double'
    assert node['type'] in ('object', 'union'), node
    known[key] = hint
    definitions[hint] = node
    return hint

def fields(node, name):
    return {key: value for key,value in node['value'].items() if not (name in payloads and key=='kind')}

def swift(name,node):
    if node['type']=='object':
        rows=[]
        for key,field in fields(node,name).items():
            typ=type_name(field['fieldType'],name+pascal(key),'swift')+('?' if field['optional'] else '')
            rows.append(f'    let {key}: {typ}')
        return '\n'.join([f'struct {name}: Codable, Equatable, Sendable {{',*rows,'}'])
    values=node['value']
    if all(value['type']=='literal' and isinstance(value['value'],str) for value in values):
        return '\n'.join([f'enum {name}: String, Codable, Sendable {{',*[f'    case {camel(pascal(value["value"]))} = {json.dumps(value["value"])}' for value in values],'}'])
    assert all(value['type']=='object' and value['value']['kind']['fieldType']['type']=='literal' for value in values),name
    variants=[]
    for value in values:
        tag=value['value']['kind']['fieldType']['value']; case=camel(pascal(tag)); data=len(value['value'])>1; payload=name+pascal(tag)
        if data: definitions[payload]=value; payloads.add(payload)
        variants.append((tag,case,payload,data))
    lines=[f'enum {name}: Codable, Equatable, Sendable {{']
    lines += [f'    case {case}'+(f'({payload})' if data else '') for tag,case,payload,data in variants]
    lines += ['    private enum KindKey: String, CodingKey { case kind }','    init(from decoder: Decoder) throws {','        let values = try decoder.container(keyedBy: KindKey.self)','        switch try values.decode(String.self, forKey: .kind) {']
    lines += [f'        case {json.dumps(tag)}: self = .{case}'+(f'(try {payload}(from: decoder))' if data else '') for tag,case,payload,data in variants]
    lines += ['        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")','        }','    }','    func encode(to encoder: Encoder) throws {','        var values = encoder.container(keyedBy: KindKey.self)','        switch self {']
    for tag,case,payload,data in variants:
        lines += [f'        case .{case}'+('(let value)' if data else '')+':',f'            try values.encode({json.dumps(tag)}, forKey: .kind)']
        if data:lines.append('            try value.encode(to: encoder)')
    lines += ['        }','    }','}']
    return '\n'.join(lines)

def kotlin(name,node):
    if node['type']=='object':
        rows=[]
        for key,field in fields(node,name).items():
            typ=type_name(field['fieldType'],name+pascal(key),'kotlin')+('?' if field['optional'] else '')
            rows.append(f'    val {key}: {typ}'+(' = null' if field['optional'] else '')+',')
        return '\n'.join(['@Serializable',f'data class {name}(',*rows,')'])
    values=node['value']
    if all(value['type']=='literal' and isinstance(value['value'],str) for value in values):
        return '\n'.join(['@Serializable',f'enum class {name} {{',*[f'    @SerialName({json.dumps(value["value"])}) {value["value"].upper()},' for value in values],'}'])
    lines=['@Serializable','@JsonClassDiscriminator("kind")',f'sealed interface {name} {{']
    for value in values:
        tag=value['value']['kind']['fieldType']['value'];case=pascal(tag);fs={k:v for k,v in value['value'].items() if k!='kind'}
        lines += ['    @Serializable',f'    @SerialName({json.dumps(tag)})']
        if not fs:lines.append(f'    data object {case} : {name}')
        else:
            lines.append(f'    data class {case}(')
            for key,field in fs.items():
                typ=type_name(field['fieldType'],name+case+pascal(key),'kotlin')+('?' if field['optional'] else '')
                lines.append(f'        val {key}: {typ}'+(' = null' if field['optional'] else '')+',')
            lines.append(f'    ) : {name}')
    lines.append('}')
    return '\n'.join(lines)

# Discover nested types before rendering either platform. Swift payload types stay
# Swift-only; Kotlin serializable variants live inside their sealed interface.
index=0
while index < len(definitions):
    name=list(definitions)[index];swift(name,definitions[name]);index+=1
swift_names=list(definitions)
swift_code='// MARK: - Generated library sync wire values\n// Source: scripts/generate-library-sync-wire.py\n\n'+'enum LibrarySyncLimits {\n'+''.join(f'    static let {name} = {value}\n' for name,value in limits.items())+'}\n\n'+'\n\n'.join(swift(name,definitions[name]) for name in swift_names)+'\n'
swift_code += '\nenum LibrarySyncIntentVectors {\n    static let values: [(json: String, digest: String)] = [\n' + ''.join('        (' + json.dumps(value['json'], ensure_ascii=False) + ', ' + json.dumps(value['digest']) + '),\n' for value in intent_digests) + '    ]\n}\n'
kotlin_names=[name for name in definitions if name not in payloads]
index=0
while index<len(kotlin_names):
    name=kotlin_names[index];kotlin(name,definitions[name]);kotlin_names=[name for name in definitions if name not in payloads];index+=1
kotlin_code='''@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
package com.hadithly.app.core.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonClassDiscriminator

// Generated by scripts/generate-library-sync-wire.py.

'''+ 'object LibrarySyncLimits {\n'+''.join(f'    const val {name} = {value}\n' for name,value in limits.items())+'}\n\n'+ '\n\n'.join(kotlin(name,definitions[name]) for name in kotlin_names)+'\n'
kotlin_code += '\nobject LibrarySyncIntentVectors {\n    val values = listOf(\n' + ''.join('        ' + json.dumps(value['json'], ensure_ascii=False).replace('$', '\\$') + ' to ' + json.dumps(value['digest']) + ',\n' for value in intent_digests) + '    )\n}\n'

saved_facts_json = json.dumps(saved_parity['facts'], ensure_ascii=False, separators=(',', ':'))
saved_expected_json = json.dumps(saved_parity['expected'], ensure_ascii=False, separators=(',', ':'))
swift_code += '\nenum LibrarySavedParityVector {\n    static let factsJSON = ' + json.dumps(saved_facts_json, ensure_ascii=False) + '\n    static let expectedJSON = ' + json.dumps(saved_expected_json, ensure_ascii=False) + '\n    static let digests = [' + ', '.join(json.dumps(value) for value in saved_parity['digests']) + ']\n}\n'
kotlin_code += '\nobject LibrarySavedParityVector {\n    const val factsJSON = ' + json.dumps(saved_facts_json, ensure_ascii=False).replace('$', '\\$') + '\n    const val expectedJSON = ' + json.dumps(saved_expected_json, ensure_ascii=False).replace('$', '\\$') + '\n    val digests = listOf(' + ', '.join(json.dumps(value) for value in saved_parity['digests']) + ')\n}\n'

swift_code += '\nenum LibrarySavedReadsParityVector {\n'
kotlin_code += '\nobject LibrarySavedReadsParityVector {\n'
for key, value in saved_reads_parity.items():
    encoded = json.dumps(json.dumps(value, ensure_ascii=False, separators=(',', ':')), ensure_ascii=False)
    swift_code += '    static let ' + key + 'JSON = ' + encoded + '\n'
    kotlin_code += '    const val ' + key + 'JSON = ' + encoded.replace('$', '\\$') + '\n'
swift_code += '}\n'
kotlin_code += '}\n'

swift_path=ROOT/'ios/Hadithly/Core/GuestData/GuestDataModels.swift'
old=swift_path.read_text();marker='// MARK: - Generated library sync wire values'
swift_text=old.split(marker)[0].rstrip()+'\n\n'+swift_code
outputs={swift_path:swift_text,ROOT/'android/app/src/main/kotlin/com/hadithly/app/core/data/LibrarySyncWire.kt':kotlin_code}
for path,text in outputs.items():
    if args.check:
        assert path.exists() and path.read_text()==text, 'Sync wire code out of date: '+str(path.relative_to(ROOT))
    else:path.write_text(text)
print('Native sync wire values verified from actual Convex validators.' if args.check else 'Generated both native sync wire value sets from actual Convex validators.')
