"""Upgrade frozen SQLite records produced by the historical 0.1 application."""
import hashlib
import json
from pathlib import Path
import sqlite3

import pytest
from PySide6.QtCore import QUrl, QPointF, Qt, QMetaObject, QObject
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest

from operational_center import template_migration as migration
from operational_center.controller import Controller
from operational_center.domain import render
from operational_center.storage import Store
from test_qml import visual_child

FIXTURES=Path(__file__).parent/'fixtures'
META=json.loads((FIXTURES/'legacy-template-0.1.json').read_text())


def old_database(path):
    data=(FIXTURES/'legacy-template-0.1.sql').read_bytes()
    assert hashlib.sha256(data).hexdigest()==META['sql_sha256']
    db=sqlite3.connect(path)
    try: db.executescript(data.decode())
    finally: db.close()
    return path


@pytest.fixture
def legacy(tmp_path):
    old=old_database(tmp_path/'original-0.1.sqlite')
    copy=tmp_path/'upgrade-copy.sqlite'
    source=sqlite3.connect(old);target=sqlite3.connect(copy)
    source.backup(target);source.close();target.close()
    store=Store(copy)
    yield store
    store.close()


def contents(store):
    return {table:[tuple(row) for row in store.db.execute('SELECT * FROM '+table+' ORDER BY 1')] for table in ['config','events','preferences','journal','contacts_cache']}


def plan(store): return migration.prepare(store,META['block_id'],META['field_id'],'Время: ')


def selected(proposal, ambiguous=False):
    return [row['key'] for row in proposal['rows'] if row['eligible'] and (ambiguous or '№2' not in row['scope'])]


def runtime(store,identity):
    event=store.event(identity)
    block=next(b for b in event['snapshot']['blocks'] if b['id']==META['block_id'])
    return event,block,render(block['config']['segments'],event['state'][block['id']]['values'])


def test_upgrade_opens_old_records_without_silent_rewrite(app,legacy,tmp_path):
    before=contents(legacy);c=Controller(legacy,tmp_path)
    block=c.state['event']['snapshot']['blocks'][0]
    assert block['tokens'][0]['token']=='field'
    assert block['runtime']['values'][META['field_id']]=='Время: 14:35'
    assert META['source_commit']=='4674b65a4614d623350cbca109a92c32e0e5f736'
    item=next(row for row in migration.inspect(legacy)['candidates'] if row['field_id']==META['field_id'])
    assert len(item['records'])==4 and all(row['default']=='Время: ' for row in item['records'])
    proposal=plan(legacy)
    assert len(proposal['rows'])==4
    assert any(row['copy_changes'] for row in proposal['rows'] if '№2' in row['scope'])
    assert all(row['phrase_changes'] for row in proposal['rows'])
    assert contents(legacy)==before
    assert not list((legacy.path.parent/'backups').glob('before-template-*'))


def test_backup_existing_snapshots_ids_links_values_phrases_and_restart(legacy):
    before=contents(legacy);first,old_block,message=runtime(legacy,META['event_full'])
    second_before=tuple(legacy.db.execute('SELECT * FROM events WHERE id=?',(META['event_value_only'],)).fetchone())
    proposal=plan(legacy);result=migration.apply(legacy,proposal,selected(proposal),True)
    backup=Store(result['backup'])
    try: assert contents(backup)==before
    finally: backup.close()
    event,block,after=runtime(legacy,META['event_full'])
    assert after==message
    assert block['config']['segments'][0]=={'kind':'text','text':'Время: '}
    definition=block['config']['segments'][1]
    assert definition['id']==META['field_id'] and definition['default']==''
    assert definition['phrases']==['12:00','Уточняется']
    assert event['state'][block['id']]['values'][META['field_id']]=='14:35'
    assert event['state'][block['id']]['values'][META['other_field_id']]==first['state'][block['id']]['values'][META['other_field_id']]
    for key in ['id','master_id','number','created','visible','archived','config_version']:
        assert event[key]==first[key]
    assert event['snapshot']['links']==first['snapshot']['links']
    assert [b['id'] for b in event['snapshot']['blocks']]==[b['id'] for b in first['snapshot']['blocks']]
    assert tuple(legacy.db.execute('SELECT * FROM events WHERE id=?',(META['event_value_only'],)).fetchone())==second_before
    assert legacy.db.execute('PRAGMA user_version').fetchone()[0]==1
    reopened=Store(legacy.path)
    try:
        assert runtime(reopened,META['event_full'])[2]==message
        assert reopened.events()==legacy.events()
        assert reopened.pref('template_migration_runs')[0]['backup']==result['backup']
    finally: reopened.close()
    assert [r['scope'] for r in plan(legacy)['rows'] if r['eligible']]==['Происшествие №2 · ДТП · архив']


def test_ambiguous_value_requires_review_and_is_kept_whole(legacy):
    proposal=plan(legacy);row=next(r for r in proposal['rows'] if '№2' in r['scope'])
    assert row['value_before']==row['value_after']=='17:40'
    assert row['copy_changes'] and row['copy_after'].startswith('Время: 17:40')
    before=contents(legacy)
    with pytest.raises(ValueError,match='подтвердите'): migration.apply(legacy,proposal,[row['key']],False)
    assert contents(legacy)==before and not list((legacy.path.parent/'backups').glob('before-template-*'))
    assert migration.apply(legacy,proposal,[row['key']],True)['records']==1
    event,_,text=runtime(legacy,META['event_value_only'])
    assert event['archived']==1 and event['state'][META['block_id']]['values'][META['field_id']]=='17:40'
    assert text==row['copy_after']


def test_backup_failure_prevents_all_writes(legacy,monkeypatch):
    proposal=plan(legacy);before=contents(legacy)
    def fail(*args,**kwargs): raise OSError('Нет места для резервной копии')
    monkeypatch.setattr(legacy,'backup',fail)
    with pytest.raises(OSError): migration.apply(legacy,proposal,selected(proposal),True)
    assert contents(legacy)==before and not legacy.db.in_transaction


def test_late_write_failure_rolls_back_every_record(legacy):
    legacy.db.execute("CREATE TRIGGER reject_migration BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT,'simulated write failure'); END");legacy.db.commit()
    proposal=plan(legacy);before=contents(legacy)
    with pytest.raises(sqlite3.IntegrityError): migration.apply(legacy,proposal,selected(proposal),True)
    assert contents(legacy)==before and not legacy.db.in_transaction
    backups=list((legacy.path.parent/'backups').glob('before-template-*'))
    assert len(backups)==1
    db=sqlite3.connect(backups[0])
    try: assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    finally: db.close()


def test_stale_review_cannot_overwrite_new_user_value(legacy):
    proposal=plan(legacy);event=legacy.event(META['event_full'])
    event['state'][META['block_id']]['values'][META['field_id']]='Время: 20:00';legacy.save_state(event['id'],event['state'])
    before=contents(legacy)
    with pytest.raises(ValueError,match='изменилась'): migration.apply(legacy,proposal,selected(proposal),True)
    assert contents(legacy)==before and not list((legacy.path.parent/'backups').glob('before-template-*'))


def test_unmatched_old_value_keys_are_preserved_and_block_automatic_mapping(legacy):
    event=legacy.event(META['event_full'])
    event['state'][META['block_id']]['values']['старое_имя']='Сохранить это значение'
    legacy.save_state(event['id'],event['state']);before=contents(legacy)
    row=next(r for r in plan(legacy)['rows'] if '№1' in r['scope'])
    assert not row['eligible'] and 'неизвестными ID' in row['reason']
    entry=next(e for e in migration.inspect(legacy)['candidates'] if e['field_id']==META['field_id'])
    assert any('старое_имя' in r['unmatched_value_keys'] for r in entry['records'])
    assert contents(legacy)==before


def test_unknown_structures_and_unmatched_prefix_are_not_guessed(legacy):
    proposal=migration.prepare(legacy,META['block_id'],META['field_id'],'Время:  ')
    assert not proposal['changes'] and all(not row['eligible'] for row in proposal['rows'])
    with pytest.raises(ValueError): migration.apply(legacy,proposal,[proposal['rows'][0]['key']],True)
    _,config=legacy.config('draft');config['masters'][0]['blocks'][0]['config']={'old_content':'Время:'}
    with legacy.db: legacy.db.execute("UPDATE config SET data=? WHERE name='draft'",(json.dumps(config),))
    assert migration.inspect(legacy)['unsupported'][0]['keys']==['old_content']
    assert all('Черновик'!=row['scope'] for row in plan(legacy)['rows'])


def click(root,item):
    assert item is not None and item.isVisible()
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,item.mapToScene(QPointF(item.width()/2,item.height()/2)).toPoint());QTest.qWait(70)


def test_existing_incident_after_reviewed_upgrade_has_protected_label_gui(app,legacy,tmp_path):
    sha='a1b2c3d4'*5;c=Controller(legacy,tmp_path,sha)
    engine=QQmlApplicationEngine();warnings=[]
    engine.warnings.connect(lambda ws:warnings.extend(w.toString() for w in ws));engine.rootContext().setContextProperty('backend',c)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1]/'operational_center/qml/Main.qml')))
    assert engine.rootObjects()
    root=engine.rootObjects()[0];root.setPosition(0,0)
    screen=app.primaryScreen().availableGeometry();root.resize(1366 if app.platformName()=='offscreen' else min(1366,screen.width()),min(768,screen.height()));root.requestActivate()
    try:
        root.setProperty('page','events');QTest.qWait(100)
        assert visual_child(root.contentItem(),'inlineField-'+META['field_id']).property('text')=='Время: 14:35'
        existing_id=c.active;count=len(legacy.events())
        root.setProperty('page','settings');QTest.qWait(100)
        assert visual_child(root.contentItem(),'buildCommit').property('text')==sha
        QMetaObject.invokeMethod(root,'inspectTemplates',Qt.DirectConnection);QTest.qWait(100)
        visual_child(root.contentItem(),'migrationFieldChoice').setProperty('currentIndex',next(i for i,r in enumerate(c.template_diagnostics['candidates']) if r['field_id']==META['field_id']))
        visual_child(root.contentItem(),'migrationPrefix').setProperty('text','Время: ')
        click(root,visual_child(root.contentItem(),'previewTemplateMigration'))
        dialog=root.findChild(QObject,'templateMigrationDialog')
        assert not visual_child(root.contentItem(),'applyTemplateMigration').isEnabled()
        dialog.setProperty('selected',selected(c.template_plan));click(root,visual_child(root.contentItem(),'confirmTemplateMigration'))
        click(root,visual_child(root.contentItem(),'applyTemplateMigration'))
        assert c.template_migration_result['records']==3
        QMetaObject.invokeMethod(root.findChild(QObject,'notificationDialog'),'close',Qt.DirectConnection);QMetaObject.invokeMethod(dialog,'close',Qt.DirectConnection)
        root.setProperty('page','events');QTest.qWait(100)
        assert visual_child(root.contentItem(),'inlineField-'+META['field_id']).property('text')=='14:35'
        card=visual_child(root.contentItem(),'runtimeBlock-'+META['block_id']);label=visual_child(card,'protectedLiteral')
        assert label.property('text')=='Время: ' and label.metaObject().indexOfProperty('readOnly')==-1
        label.forceActiveFocus();QTest.keyClick(root,Qt.Key_Backspace);QTest.keyClick(root,Qt.Key_Delete)
        assert label.property('text')=='Время: ' and c.active==existing_id and len(legacy.events())==count
    finally: root.close();del root;del engine
    assert not warnings
