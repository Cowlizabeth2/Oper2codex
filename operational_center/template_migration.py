"""Reviewed content repair, never an automatic guess based on a field label.

The historical SQL/segment schema is unchanged. Moving an explicitly chosen
prefix out of a field is a content migration, including saved incident snapshots.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sqlite3
from contextlib import closing

from .domain import now, render, uid, validate_config


def documents(store):
    result = []
    for row in store.db.execute('SELECT name,data FROM config ORDER BY name'):
        result.append({'scope':'config', 'identity':row['name'], 'title':{'draft':'Черновик','published':'Опубликовано'}.get(row['name'],row['name']),
                       'document':json.loads(row['data'])})
    for row in store.db.execute('SELECT id,number,name,snapshot,state,archived FROM events ORDER BY number'):
        result.append({'scope':'event','identity':row['id'], 'title':f"Происшествие №{row['number']} · {row['name']}"+(' · архив' if row['archived'] else ''),
                       'document':json.loads(row['snapshot']), 'state':json.loads(row['state'])})
    return result


def fingerprint(store):
    # Include every durable column: concurrent edits, new events and changes to
    # visibility invalidate the review rather than silently replacing a row.
    values = [list(row) for row in store.db.execute('SELECT * FROM config ORDER BY name')]
    values += [list(row) for row in store.db.execute('SELECT * FROM events ORDER BY id')]
    return hashlib.sha256(json.dumps(values,ensure_ascii=False).encode()).hexdigest()


def blocks(document):
    masters = document['document'].get('masters', []) if document['scope']=='config' else [document['document']]
    for master in masters:
        for block in master.get('blocks', []):
            if block.get('type')=='text':
                yield master, block


def key(document, master, block, field):
    return json.dumps([document['scope'],document['identity'],master['id'],block['id'],field['id']],ensure_ascii=False)


def inspect(store, block_id=''):
    candidates, unsupported = {}, []
    for document in documents(store):
        for master, block in blocks(document):
            if block_id and block['id']!=block_id:
                continue
            segments = block.get('config', {}).get('segments')
            if not isinstance(segments,list) or any(not isinstance(s,dict) or s.get('kind') not in {'text','field'} or s.get('kind')=='field' and not s.get('id') for s in segments):
                unsupported.append({'scope':document['title'], 'block':block.get('title',''), 'keys':list(block.get('config',{})),
                                    'reason':'Нет известного массива segments; автоматическое преобразование запрещено'})
                continue
            values=document.get('state',{}).get(block['id'],{}).get('values',{})
            known={s['id'] for s in segments if s.get('kind')=='field'}
            for index, field in enumerate(segments):
                if field.get('kind')!='field':
                    continue
                identity = json.dumps([block['id'],field['id']])
                entry = candidates.setdefault(identity, {'id':identity,'block_id':block['id'],'field_id':field['id'],
                    'title':f"{master.get('name','')} / {block.get('title','')} / {field.get('label','')}", 'records':[]})
                properties={name:copy.deepcopy(field[name]) for name in ('default','value','text','placeholder') if name in field}
                caption=str(field.get('label','')).rstrip(': ') + ':'
                issues=[]
                for name,value in properties.items():
                    if isinstance(value,str) and (value.strip().casefold().startswith(caption.casefold()) or re.match(r'^\s*[^\W\d_][^:\r\n]{0,59}:',value)):
                        issues.append(f'Возможная подпись в редактируемом свойстве {name}; требуется просмотр')
                effective=values.get(field['id'],field.get('default',''))
                if isinstance(effective,str) and effective.strip().casefold().startswith(caption.casefold()):
                    issues.append('Подпись присутствует в сохранённом значении происшествия')
                for name in ('value','text'):
                    if name in properties and ('default' not in field or field[name]!=field['default']):
                        issues.append(f'Неканоническое свойство {name}: требуется явный выбор источника')
                entry['records'].append({'scope':document['title'], 'default':field.get('default',''),
                    'properties':properties,'issues':issues,'segments':copy.deepcopy(segments),
                    'kind':field['kind'],'previous_segment':segments[index-1] if index else None,
                    'value':values.get(field['id'],field.get('default','')),
                    'value_present':field['id'] in values,'unmatched_value_keys':sorted(set(values)-known),
                    'phrases':field.get('phrases',[])})
    return {'candidates':list(candidates.values()), 'unsupported':unsupported,
            'problem_count':sum(len(r['issues']) for candidate in candidates.values() for r in candidate['records'])+len(unsupported),
            'explanation':'Тип field в SQLite напрямую становится полем ввода. Префикс не определяется по имени поля автоматически.'}


def prepare(store, block_id, field_id, prefix, source_property='default'):
    with store.db:
        store.db.execute('BEGIN')
        return _prepare(store,block_id,field_id,prefix,source_property)


def _prepare(store, block_id, field_id, prefix, source_property):
    if source_property not in {'default','value','text','placeholder'}:
        raise ValueError('Неизвестный источник значения')
    if not isinstance(prefix,str) or not prefix or '\n' in prefix or '\r' in prefix:
        raise ValueError('Укажите точный непустой однострочный префикс из сохранённого значения')
    rows, changes = [], []
    for document in documents(store):
        for master, block in blocks(document):
            if block.get('id')!=block_id:
                continue
            segments=block.get('config',{}).get('segments',[])
            if not isinstance(segments,list) or any(not isinstance(s,dict) or s.get('kind') not in {'text','field'} for s in segments):
                continue
            for index, field in enumerate(segments):
                if field.get('kind')!='field' or field.get('id')!=field_id:
                    continue
                record_key=key(document,master,block,field)
                values=document.get('state',{}).get(block_id,{}).get('values',{})
                default=field.get('default','')
                source_value=field.get(source_property)
                already_static=bool(index and segments[index-1].get('kind')=='text' and segments[index-1].get('text','').endswith(prefix))
                row={'key':record_key,'scope':document['title'],'default_before':default,
                     'source_property':source_property,'source_before':source_value,'already_static':already_static,
                     'value_before':values.get(field_id,default),'phrases_before':copy.deepcopy(field.get('phrases',[])),
                     'eligible':True,'reason':'','copy_before':render(segments,values)}
                if not isinstance(source_value,str) or not source_value.startswith(prefix):
                    row.update(eligible=False,reason=f'Свойство {source_property} не начинается с точного префикса. Выберите другой источник или точный текст.')
                if set(values)-{s.get('id') for s in segments if s.get('kind')=='field'}:
                    row.update(eligible=False,reason='Есть значения с неизвестными ID полей. Их соответствие нельзя угадывать; нужен отдельный разбор.')
                if not row['eligible']:
                    rows.append(row)
                    continue
                updated=copy.deepcopy(field)
                updated.setdefault('_repair_archive',[]).append({'source':source_property,'prefix':prefix,
                    'properties':{name:copy.deepcopy(field[name]) for name in ('default','value','text','placeholder','phrases') if name in field}})
                if source_property=='placeholder':
                    updated['default']=default[len(prefix):] if isinstance(default,str) and default.startswith(prefix) else default
                else:
                    updated['default']=source_value[len(prefix):]
                updated[source_property]=source_value[len(prefix):]
                # Preserve every phrase; only move the exact reviewed prefix.
                updated['phrases']=[p[len(prefix):] if isinstance(p,str) and p.startswith(prefix) else p for p in field.get('phrases',[])]
                after_segments=copy.deepcopy(segments)
                after_segments[index:index+1]=([{'kind':'text','text':prefix}] if not already_static else [])+[updated]
                after_values=copy.deepcopy(values)
                old_value=values.get(field_id,default)
                if field_id in values and isinstance(old_value,str) and old_value.startswith(prefix):
                    after_values[field_id]=old_value[len(prefix):]
                row.update(default_after=updated['default'],value_after=after_values.get(field_id,updated['default']),
                           phrases_after=updated['phrases'],copy_after=render(after_segments,after_values),static_prefix=prefix)
                row['copy_changes']=row['copy_before']!=row['copy_after']
                # Phrases without the prefix keep their complete contents but
                # will now follow the static label. Show this semantic change.
                row['phrase_changes']=any(not isinstance(p,str) or not p.startswith(prefix) for p in field.get('phrases',[]))
                rows.append(row)
                changes.append({'key':record_key,'document':document,'master_id':master['id'],'block_id':block_id,
                                'segments':after_segments,'values':after_values})
    if not rows:
        raise ValueError('Поле в сохранённых записях не найдено')
    return {'fingerprint':fingerprint(store),'rows':rows,'changes':changes,'prefix':prefix,'block_id':block_id,'field_id':field_id}


def apply(store, plan, selected, confirmed):
    if confirmed is not True or not selected:
        raise ValueError('Выберите записи и подтвердите просмотр изменений')
    selected=set(selected)
    eligible={change['key']:change for change in plan['changes']}
    if not selected<=eligible.keys():
        raise ValueError('Выбраны неизвестные или неоднозначные записи')
    with store.db:
        store.db.execute('BEGIN IMMEDIATE')
        if fingerprint(store)!=plan['fingerprint']:
            raise ValueError('База изменилась после предпросмотра. Повторите проверку')
        # Hold the writer reservation. A separate read-only source connection
        # lets SQLite backup see a committed, consistent database without a
        # same-connection backup/write-lock deadlock.
        target=store.path.parent/'backups'/f'before-template-migration-{uid()}.sqlite'
        with closing(sqlite3.connect(store.path.resolve().as_uri()+'?mode=ro',uri=True)) as source:
            backup=store.backup(target,source_connection=source)
        modified={}
        for record_key in sorted(selected):
            change=eligible[record_key]
            source=change['document']
            doc_key=(source['scope'],source['identity'])
            doc=modified.setdefault(doc_key,copy.deepcopy(source))
            master=next(m for m in (doc['document']['masters'] if doc['scope']=='config' else [doc['document']]) if m['id']==change['master_id'])
            block=next(b for b in master['blocks'] if b['id']==change['block_id'])
            block['config']['segments']=copy.deepcopy(change['segments'])
            if doc['scope']=='event':
                doc['state'][block['id']]['values']=copy.deepcopy(change['values'])
        for (scope, identity), doc in modified.items():
            validate_config(doc['document'] if scope=='config' else {'format':1,'masters':[doc['document']]})
            data=json.dumps(doc['document'],ensure_ascii=False)
            if scope=='config':
                store.db.execute('UPDATE config SET data=? WHERE name=?',(data,identity))
            else:
                store.db.execute('UPDATE events SET snapshot=?,state=? WHERE id=?',
                                 (data,json.dumps(doc['state'],ensure_ascii=False),identity))
        history=store.pref('template_migration_runs',[])
        history.append({'created':now(),'kind':'explicit_static_prefix_v1','backup':backup,'records':sorted(selected)})
        store.db.execute('INSERT OR REPLACE INTO preferences VALUES(?,?)',
                         ('template_migration_runs',json.dumps(history,ensure_ascii=False)))
        store.log('INFO',f'Перенесён явно подтверждённый префикс шаблона: {len(selected)} записей. Резервная копия: {backup}')
    return {'backup':backup,'records':len(selected)}
