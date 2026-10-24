import json
from pathlib import Path
import subprocess
import sys

import pytest

from operational_center.controller import Controller
from operational_center.domain import render
from operational_center.storage import Store
from operational_center import template_migration
from operational_center.upgrade_check import guard
from tools.prepare_exe_upgrade import prepare


@pytest.mark.parametrize('name',['historical-default','value','text','placeholder','duplicate-static'])
def test_old_editable_properties_are_repaired_only_after_review(tmp_path,name):
    path=prepare(tmp_path/'profile');manifest=json.loads(path.read_text())
    case=next(c for c in manifest['cases'] if c['name']==name)
    store=Store(path.parent/'operational-center.sqlite')
    try:
        before=store.event(case['event_id'])
        block=next(b for b in before['snapshot']['blocks'] if b['id']==case['block_id'])
        original=next(s for s in block['config']['segments'] if s.get('id')==case['field_id'])
        diagnosis=template_migration.inspect(store,case['block_id'])
        assert diagnosis['problem_count']>0 and all(c['block_id']==case['block_id'] for c in diagnosis['candidates'])
        plan=template_migration.prepare(store,case['block_id'],case['field_id'],case['prefix'],case['source_property'])
        assert store.event(case['event_id'])==before
        keys=[r['key'] for r in plan['rows'] if r['eligible'] and json.loads(r['key'])[1]==case['event_id']]
        assert len(keys)==1
        with pytest.raises(ValueError):template_migration.apply(store,plan,keys,False)
        result=template_migration.apply(store,plan,keys,True)
        assert Path(result['backup']).is_file()
        after=store.event(case['event_id']);fixed=next(b for b in after['snapshot']['blocks'] if b['id']==case['block_id'])
        field=next(s for s in fixed['config']['segments'] if s.get('id')==case['field_id'])
        assert after['state'][case['block_id']]['values'][case['field_id']]==case['expected']
        assert field['_repair_archive'][-1]['properties'][case['source_property']]==original[case['source_property']]
        assert field['_repair_archive'][-1]['properties']['phrases']==original['phrases']
        assert field['_repair_archive'][-1]['stored_value']==before['state'][case['block_id']]['values'][case['field_id']]
        assert field['id']==original['id'] and after['snapshot']['links']==before['snapshot']['links']
        assert len([s for s in fixed['config']['segments'] if s.get('kind')=='text' and s.get('text')=='Время: '])==1
    finally:store.close()


def test_new_template_from_constructor_uses_same_static_field_model(app,store,tmp_path):
    c=Controller(store,tmp_path)
    assert c.command('add_block',json.dumps({'type':'text'}))
    block_id=c.selected_block
    result=c.insertField('Время: 14:35',7,12,'[]','Время')
    assert c.saveTemplate(block_id,'Новый шаблон',result['source'],json.dumps(result['fields']))
    assert list((tmp_path/'backups').glob('before-template-edit-*'))
    assert c.command('publish','{}') and c.command('create_event',json.dumps({'id':c.selected_master}))
    block=c.state['event']['snapshot']['blocks'][0]
    assert block['tokens'][0]['token']=='static'
    assert block['config']['segments'][0]['text']=='Время: '
    assert block['fields'][0]['default']=='14:35'
    assert render(block['config']['segments'],block['runtime']['values'])=='Время: 14:35'


def test_upgrade_cli_refuses_a_changed_or_non_fixture_database(tmp_path):
    manifest=prepare(tmp_path/'profile')
    assert guard(manifest.parent,manifest,'apply')['synthetic_upgrade_fixture']
    with (manifest.parent/'operational-center.sqlite').open('ab') as stream:stream.write(b'changed')
    with pytest.raises(ValueError,match='checksum'):guard(manifest.parent,manifest,'apply')
    wrong=tmp_path/'wrong.json';wrong.write_text('{}')
    with pytest.raises(ValueError):guard(tmp_path,wrong,'apply')


def test_real_process_opens_precreated_old_db_then_reopens_repaired_db(tmp_path):
    manifest=prepare(tmp_path/'profile')
    root=Path(__file__).resolve().parents[1]
    reports=[]
    for phase in ['apply','verify']:
        report=tmp_path/(phase+'.json')
        result=subprocess.run([sys.executable,str(root/'main.py'),'--upgrade-test','--data-dir',str(manifest.parent),
            '--upgrade-manifest',str(manifest),'--upgrade-output',str(tmp_path/'captures'),'--upgrade-phase',phase,
            '--smoke-report',str(report)],cwd=root,capture_output=True,text=True,encoding='utf-8',timeout=120)
        assert result.returncode==0,result.stdout+result.stderr
        payload=json.loads(report.read_text(encoding='utf-8'));assert payload['ok'] and not payload['qml_errors']
        assert len(payload['upgrade']['cases'])==10 and payload['upgrade']['events_created']==0
        reports.append(payload['upgrade'])
    assert len(reports[0]['backups'])==10 and reports[1]['reopened_database']
    assert reports[0]['fresh_template_ok'] and reports[1]['untouched_records_preserved']
