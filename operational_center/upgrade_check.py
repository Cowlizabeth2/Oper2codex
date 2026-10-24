"""Opt-in EXE integration check; requires a precreated synthetic DB manifest."""
import hashlib
import json
from pathlib import Path

from PySide6.QtCore import QObject, QMetaObject, Qt, QPointF
from PySide6.QtTest import QTest

from .domain import render


def visual_child(item,name):
    if item.objectName()==name:return item
    for child in item.childItems():
        result=visual_child(child,name)
        if result is not None:return result
    return None


def guard(data_dir,manifest_path,phase):
    data_dir=Path(data_dir).resolve();manifest_path=Path(manifest_path).resolve()
    if manifest_path.parent!=data_dir or manifest_path.name!='upgrade-fixture.json':
        raise ValueError('EXE upgrade test requires its own synthetic fixture directory')
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest.get('synthetic_upgrade_fixture') is not True or manifest.get('format')!=1:
        raise ValueError('Not a synthetic upgrade fixture')
    if phase=='apply' and hashlib.sha256((data_dir/'operational-center.sqlite').read_bytes()).hexdigest()!=manifest['database_sha256']:
        raise ValueError('Precreated fixture database checksum does not match')
    if phase=='verify' and not (data_dir/'upgrade-baseline.json').is_file():
        raise ValueError('Upgrade verification needs an earlier application pass')
    return manifest


def event_text(store,identity,block_id):
    event=store.event(identity);block=next(b for b in event['snapshot']['blocks'] if b['id']==block_id)
    return render(block['config']['segments'],event['state'][block_id]['values'])


def stable_rows(store):
    return [list(row) for row in store.db.execute('SELECT id,number,created,master_id,name,tag,config_version,visible,archived FROM events ORDER BY id')]


def run(controller,root,manifest,phase,data_dir,output):
    store=controller.store;data_dir=Path(data_dir);output=Path(output);output.mkdir(parents=True,exist_ok=True)
    from PySide6.QtGui import QGuiApplication
    if QGuiApplication.platformName()=='offscreen':
        root.resize(1366,768)
        QTest.qWait(100)
    baseline_path=data_dir/'upgrade-baseline.json'
    if phase=='apply':
        baseline={'events':stable_rows(store),
                  'untouched':{i:list(store.db.execute('SELECT snapshot,state FROM events WHERE id=?',(i,)).fetchone()) for i in manifest['untouched_event_ids']},
                  'messages':{c['name']:event_text(store,c['event_id'],c['block_id']) for c in manifest['cases']}}
        baseline_path.write_text(json.dumps(baseline,ensure_ascii=False),encoding='utf-8')
    else:baseline=json.loads(baseline_path.read_text(encoding='utf-8'))
    report={'phase':phase,'cases':[],'commit':controller.commit,'precreated_database':True,'backups':[]}

    def invoke(action,**args):
        if not controller.command(action,json.dumps(args,ensure_ascii=False)):raise RuntimeError('Upgrade command failed: '+action)
        QTest.qWait(20)

    def click(name):
        item=visual_child(root.contentItem(),name)
        if item is None or not item.isVisible() or not item.isEnabled():raise RuntimeError('Unavailable control: '+name)
        point=item.mapToScene(QPointF(item.width()/2,item.height()/2)).toPoint()
        QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,point);QTest.qWait(50)

    for case in manifest['cases']:
        if phase=='apply':
            invoke('select_master',id=case['master_id']);invoke('select_block',id=case['block_id'])
            root.setProperty('page','builder');QTest.qWait(50)
            # Use the actual constructor action and the actual confirmation UI.
            click('repairTextStructure')
            diagnostics=controller.template_diagnostics
            if any(c['block_id']!=case['block_id'] for c in diagnostics['candidates']):raise RuntimeError('Diagnostics escaped selected block')
            choice=visual_child(root.contentItem(),'migrationFieldChoice')
            choice.setProperty('currentIndex',next(i for i,c in enumerate(diagnostics['candidates']) if c['field_id']==case['field_id']))
            visual_child(root.contentItem(),'migrationSource').setProperty('currentIndex',['default','value','text','placeholder'].index(case['source_property']))
            visual_child(root.contentItem(),'migrationPrefix').setProperty('text',case['prefix'])
            click('previewTemplateMigration')
            keys=[r['key'] for r in controller.template_plan['rows'] if r['eligible'] and (json.loads(r['key'])[0]=='config' or json.loads(r['key'])[1]==case['event_id'])]
            if len(keys)!=3:raise RuntimeError('Expected draft, published and existing event proposals')
            dialog=root.findChild(QObject,'templateMigrationDialog');dialog.setProperty('selected',keys)
            click('confirmTemplateMigration');click('applyTemplateMigration')
            result=controller.template_migration_result
            if not result or not Path(result['backup']).is_file():raise RuntimeError('No mandatory backup')
            report['backups'].append(result['backup'])
            QMetaObject.invokeMethod(root.findChild(QObject,'notificationDialog'),'close',Qt.DirectConnection)
            QMetaObject.invokeMethod(dialog,'close',Qt.DirectConnection)
        invoke('select_event',id=case['event_id']);root.setProperty('page','events');QTest.qWait(60)
        control=visual_child(root.contentItem(),'inlineField-'+case['field_id'])
        if control is None or control.property('text')!=case['expected']:raise RuntimeError('Wrong displayed value: '+case['name'])
        event=store.event(case['event_id']);block=next(b for b in event['snapshot']['blocks'] if b['id']==case['block_id'])
        definition=next(s for s in block['config']['segments'] if s.get('id')==case['field_id'])
        if definition['id']!=case['field_id']:raise RuntimeError('Field ID changed')
        if not any(s.get('kind')=='text' and s.get('text')==case['prefix'] for s in block['config']['segments']):raise RuntimeError('Static prefix missing')
        card=visual_child(root.contentItem(),'runtimeBlock-'+case['block_id'])
        image=card.grabToImage();QTest.qWait(60)
        if not image.saveToFile(str(output/(phase+'-'+case['name']+'.png'))):raise RuntimeError('Cannot capture existing card')
        invoke('copy_text',id=case['block_id'])
        expected=event_text(store,case['event_id'],case['block_id'])
        from PySide6.QtGui import QGuiApplication
        if QGuiApplication.clipboard().text()!=expected:raise RuntimeError('Copy differs from migrated stored message')
        if not case['name'].startswith('duplicate-static') and expected!=baseline['messages'][case['name']]:
            raise RuntimeError('Entered text changed: '+case['name'])
        report['cases'].append({'name':case['name'],'same_event_id':True,'same_field_id':True,'displayed_value_ok':True,'copy_ok':True})
    if stable_rows(store)!=baseline['events']:raise RuntimeError('Event identity/context changed or a new event was created')
    for identity,before in baseline['untouched'].items():
        after=list(store.db.execute('SELECT snapshot,state FROM events WHERE id=?',(identity,)).fetchone())
        if after!=before:raise RuntimeError('An ambiguous or fresh control record was modified')
    fresh=store.event(manifest['fresh_event_id'])
    if fresh['state'][manifest['fresh_block_id']]['values'][manifest['fresh_field_id']]!='12:40':raise RuntimeError('Fresh template regressed')
    controller.active=manifest['fresh_event_id'];controller.stateChanged.emit();root.setProperty('page','events');QTest.qWait(60)
    if visual_child(root.contentItem(),'inlineField-'+manifest['fresh_field_id']).property('text')!='12:40':raise RuntimeError('Fresh template display regressed')
    root.setProperty('page','settings');QTest.qWait(60)
    if visual_child(root.contentItem(),'buildCommit').property('text')!=controller.commit:raise RuntimeError('Full build SHA missing')
    report.update(ok=True,events_created=0,untouched_records_preserved=True,fresh_template_ok=True,full_sha_ok=True,
                  reopened_database=phase=='verify')
    return report
