"""Prepare an on-disk legacy SQLite fixture BEFORE launching the built EXE."""
import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from operational_center.domain import uid, new_master, new_block, field


def prepare(destination):
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False)
    fixtures=Path(__file__).resolve().parents[1]/'tests/fixtures'
    meta=json.loads((fixtures/'legacy-template-0.1.json').read_text())
    data=(fixtures/'legacy-template-0.1.sql').read_bytes()
    assert hashlib.sha256(data).hexdigest()==meta['sql_sha256']
    db_path=destination/'operational-center.sqlite'
    db=sqlite3.connect(db_path)
    try:
        db.executescript(data.decode())
        configs={name:json.loads(raw) for name,raw in db.execute('SELECT name,data FROM config')}
        source=configs['published']['masters'][0]
        cases=[{'name':'historical-default','master_id':meta['master_id'],'block_id':meta['block_id'],
                'field_id':meta['field_id'],'source_property':'default','prefix':'Время: ','event_id':meta['event_full'],'expected':'14:35'}]
        cases.append({'name':'historical-place','master_id':meta['master_id'],'block_id':meta['block_id'],
                      'field_id':meta['other_field_id'],'source_property':'default','prefix':'Место: ','event_id':meta['event_full'],'expected':'Станция Пример'})
        next_number=db.execute('SELECT MAX(number) FROM events').fetchone()[0]+1
        for index,(name,source_property,value) in enumerate([('value','value','09:10'),('text','text','10:20'),('placeholder','placeholder','11:30'),('duplicate-static','default','13:50')]):
            master=copy.deepcopy(source);master.update(id=uid(),name='Совместимость '+name,tag='compat_'+name)
            remap={b['id']:uid() for b in master['blocks']}
            for block in master['blocks']:
                block['id']=remap[block['id']]
                for segment in block['config'].get('segments',[]):
                    if segment['kind']=='field':segment['id']=uid()
            master['links']=[remap[i] for i in master['links']]
            block=master['blocks'][0];definition=block['config']['segments'][0]
            if source_property=='placeholder':
                definition.update(default='',placeholder='Время: ')
            elif source_property!='default':
                definition.pop('default',None);definition[source_property]='Время: '+value
            if name=='duplicate-static':block['config']['segments'].insert(0,{'kind':'text','text':'Время: '})
            for config in configs.values():config['masters'].append(copy.deepcopy(master))
            event_id=uid()
            state={b['id']:{'values':{},'files':[],'initialized':True,'selected':[]} for b in master['blocks']}
            state[block['id']]['values']={s['id']:('Время: '+value if s['id']==definition['id'] else s.get('default','')) for s in block['config']['segments'] if s['kind']=='field'}
            db.execute('INSERT INTO events VALUES(?,?,?,?,?,?,?,?,?,1,0)',(event_id,next_number+index,'2026-01-01T00:00:00+00:00',master['id'],master['name'],master['tag'],2,json.dumps(master,ensure_ascii=False),json.dumps(state,ensure_ascii=False)))
            cases.append({'name':name,'master_id':master['id'],'block_id':block['id'],'field_id':definition['id'],
                          'source_property':source_property,'prefix':'Время: ','event_id':event_id,'expected':value})
            place=next(s for s in block['config']['segments'] if s['kind']=='field' and s['id']!=definition['id'])
            cases.append({'name':name+'-place','master_id':master['id'],'block_id':block['id'],'field_id':place['id'],
                          'source_property':'default','prefix':'Место: ','event_id':event_id,'expected':''})
        # Independent new template: the control case must never be repaired.
        fresh=new_master('Новый корректный шаблон','fresh_control');block=new_block('text');definition=field('Время',default='12:40')
        block['config']['segments']=[{'kind':'text','text':'Время: '},definition]
        fresh.update(blocks=[block],links=[block['id']])
        for config in configs.values():config['masters'].append(copy.deepcopy(fresh))
        fresh_id=uid();state={block['id']:{'values':{definition['id']:'12:40'},'files':[],'initialized':True,'selected':[]}}
        db.execute('INSERT INTO events VALUES(?,?,?,?,?,?,?,?,?,1,0)',(fresh_id,next_number+4,'2026-01-01T00:00:00+00:00',fresh['id'],fresh['name'],fresh['tag'],2,json.dumps(fresh,ensure_ascii=False),json.dumps(state,ensure_ascii=False)))
        for name,config in configs.items():db.execute('UPDATE config SET data=? WHERE name=?',(json.dumps(config,ensure_ascii=False),name))
        db.commit()
    finally:db.close()
    manifest={'synthetic_upgrade_fixture':True,'format':1,'database_sha256':hashlib.sha256(db_path.read_bytes()).hexdigest(),
              'historical_source_commit':meta['source_commit'],'cases':cases,'untouched_event_ids':[meta['event_value_only'],fresh_id],
              'fresh_event_id':fresh_id,'fresh_field_id':definition['id'],'fresh_block_id':block['id']}
    path=destination/'upgrade-fixture.json';path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    return path


if __name__=='__main__':print(prepare(sys.argv[1]))
