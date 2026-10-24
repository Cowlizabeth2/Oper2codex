"""Reopen a historical fixture, repair its existing records and capture proof.

This tool ONLY uses the committed synthetic 0.1 fixture. It does not claim to
inspect the user's unavailable database and never opens their default data dir.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtCore import QUrl, QMetaObject, Qt, QtMsgType, qInstallMessageHandler
from PySide6.QtGui import QFontInfo
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from operational_center.storage import Store
from operational_center.controller import Controller
from operational_center.domain import render
from operational_center import template_migration
from tools.visual_review import visual_child


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=Path('artifacts/template-upgrade'))
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    if sys.platform=='win32' and os.environ.get('QT_QPA_PLATFORM')=='offscreen':
        os.environ.setdefault('QT_QPA_FONTDIR',str(Path(os.environ.get('WINDIR',r'C:\Windows'))/'Fonts'))
    app=QApplication.instance() or QApplication([])
    warnings=[]
    def handler(kind,context,message):
        if kind in [QtMsgType.QtWarningMsg,QtMsgType.QtCriticalMsg,QtMsgType.QtFatalMsg]: warnings.append(message)
    previous=qInstallMessageHandler(handler)
    fixtures=Path(__file__).resolve().parents[1]/'tests/fixtures'
    metadata=json.loads((fixtures/'legacy-template-0.1.json').read_text())
    data=(fixtures/'legacy-template-0.1.sql').read_bytes()
    assert hashlib.sha256(data).hexdigest()==metadata['sql_sha256']
    report={'source':'committed synthetic historical 0.1 SQLite dump','user_database_verified':False,
            'source_commit':metadata['source_commit'],'sql_sha256':metadata['sql_sha256'],'qml_errors':warnings,'steps':[],'backups':[]}
    with tempfile.TemporaryDirectory(prefix='oper-upgrade-review-') as temp:
        root_dir=Path(temp);old=sqlite3.connect(root_dir/'old.sqlite');old.executescript(data.decode());old.commit()
        copy=sqlite3.connect(root_dir/'copy.sqlite');old.backup(copy);old.close();copy.close()
        store=Store(root_dir/'copy.sqlite');backend=Controller(store,root_dir,os.environ.get('GITHUB_SHA','development'))
        identity=backend.active;events_before=store.events()
        event_before=store.event(identity)
        text_before=render(event_before['snapshot']['blocks'][0]['config']['segments'],event_before['state'][metadata['block_id']]['values'])
        engine=QQmlApplicationEngine();engine.rootContext().setContextProperty('backend',backend)
        engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1]/'operational_center/qml/Main.qml')))
        if not engine.rootObjects(): raise RuntimeError('Cannot open upgraded historical database')
        root=engine.rootObjects()[0];root.setPosition(0,0);root.resize(1366,768);root.setProperty('page','events');QTest.qWait(150)
        report.update(platform=app.platformName(),resolved_font=QFontInfo(root.property('font')).family())
        def capture(phase):
            for theme in ['dark','light']:
                assert backend.command('theme',json.dumps({'name':theme}))
                QTest.qWait(100)
                card=visual_child(root.contentItem(),'runtimeBlock-'+metadata['block_id'])
                frame=card.grabToImage();QTest.qWait(100)
                if not frame.saveToFile(str(args.output/f'{phase}-{theme}-block.png')): raise RuntimeError('Empty block capture')
                if not root.grabWindow().save(str(args.output/f'{phase}-{theme}-window.png')): raise RuntimeError('Empty window capture')
        capture('before')
        control=visual_child(root.contentItem(),'inlineField-'+metadata['field_id'])
        assert control.property('text')=='Время: 14:35'
        for field_id,prefix in [(metadata['field_id'],'Время: '),(metadata['other_field_id'],'Место: ')]:
            plan=template_migration.prepare(store,metadata['block_id'],field_id,prefix)
            # The explicit test policy is part of this synthetic fixture review:
            # leave the ambiguous value-only archived incident untouched.
            chosen=[r['key'] for r in plan['rows'] if r['eligible'] and '№2' not in r['scope']]
            result=template_migration.apply(store,plan,chosen,True)
            report['steps'].append({'field_id':field_id,'records':result['records'],'ambiguous_not_selected':sum(1 for r in plan['rows'] if r['eligible'] and '№2' in r['scope'])})
            backup=sqlite3.connect(result['backup'])
            try: assert backup.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
            finally: backup.close()
            report['backups'].append({'created_before_write':True,'integrity':'ok'})
        backend.stateChanged.emit();QTest.qWait(100)
        event_after=store.event(identity)
        assert store.events()==events_before and backend.active==identity
        assert render(event_after['snapshot']['blocks'][0]['config']['segments'],event_after['state'][metadata['block_id']]['values'])==text_before
        assert visual_child(root.contentItem(),'inlineField-'+metadata['field_id']).property('text')=='14:35'
        assert visual_child(root.contentItem(),'inlineField-'+metadata['other_field_id']).property('text')=='Станция Пример'
        capture('after')
        root.close();del root;del engine;app.processEvents();store.close()
        # Also reopen the UPDATED on-disk database, rather than only rendering
        # an in-memory edit or creating another new incident.
        reopened=Store(root_dir/'copy.sqlite')
        assert reopened.events()==events_before and reopened.event(identity)['state']==event_after['state']
        reopened.close()
    qInstallMessageHandler(previous)
    report.update(ok=not warnings,existing_event_id_preserved=True,events_created_during_upgrade=0,
                  exact_message_preserved=True,restart_verified=True,commit=os.environ.get('GITHUB_SHA','development'))
    (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    return 0 if report['ok'] else 1


if __name__=='__main__': raise SystemExit(main())
