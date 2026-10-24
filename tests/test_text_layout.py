"""Acceptance checks on a real incident card, not a mocked form."""
import json
from pathlib import Path

import pytest
from PySide6.QtCore import QUrl, QPointF, Qt
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest

from operational_center.controller import Controller
from operational_center.domain import render
from tools.text_layout_fixture import prepare
from test_qml import visual_child


def descendants(item):
    return [item]+[entry for child in item.childItems() for entry in descendants(child)]


@pytest.fixture
def document(app, store, tmp_path, request):
    width, theme = getattr(request, 'param', (560, 'dark'))
    master, text = prepare(store,tmp_path)
    config=store.config('draft')[1]
    config['masters'][0]['blocks'][0]['width']=width
    store.save_draft(config);store.publish()
    c=Controller(store,tmp_path)
    assert c.command('theme',json.dumps({'name':theme}))
    assert c.command('create_event',json.dumps({'id':master['id']}))
    engine=QQmlApplicationEngine();warnings=[]
    engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
    engine.rootContext().setContextProperty('backend',c)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1]/'operational_center/qml/Main.qml')))
    assert engine.rootObjects()
    root=engine.rootObjects()[0]
    screen=app.primaryScreen().availableGeometry()
    root.setPosition(0,0);root.resize(1366 if app.platformName()=='offscreen' else min(1366,screen.width()),min(768,screen.height()))
    root.setProperty('page','events');root.requestActivate();QTest.qWait(150)
    yield c,root,text,width
    root.close();del root;del engine
    assert not warnings


@pytest.mark.parametrize('document',[(560,'dark'),(560,'light'),(320,'dark'),(320,'light')],indirect=True)
def test_labels_are_plain_protected_text_and_values_stay_beside_them(document,app):
    c,root,text,width=document
    card=visual_child(root.contentItem(),'runtimeBlock-'+text['id'])
    literals=[x for x in descendants(card) if x.objectName()=='protectedLiteral']
    definitions=[s for s in text['config']['segments'] if s['kind']=='field']
    controls=[visual_child(card,'inlineField-'+f['id']) for f in definitions]
    assert len(literals)==len(controls)==6
    assert [s.property('text').rstrip() for s in literals]==[f['label']+':' for f in definitions]
    positions=[x.mapToScene(QPointF(0,0)) for x in controls]
    assert max(p.x() for p in positions)-min(p.x() for p in positions)<1
    for label,control,definition in zip(literals,controls,definitions):
        assert label.metaObject().indexOfProperty('readOnly')==-1  # Text, never a TextField/TextArea.
        assert label.metaObject().className().startswith('QQuickText')
        assert control.property('text')==definition['default']
        assert control.property('placeholderText')==''
        p=control.mapToItem(card,QPointF(0,0));q=label.mapToItem(card,QPointF(0,0))
        assert p.x()>=q.x()+label.width() and abs(p.y()-q.y())<1
        assert p.x()+control.width()<=card.width()
        if width==560 and not definition['multiline']:
            # Short values must not scroll horizontally just because the font
            # resolved after the first layout pass.
            assert control.property('contentWidth')<=control.width()-control.property('leftPadding')-control.property('rightPadding')
        if width==560:
            assert label.property('lineCount')==1
        preset=visual_child(card,'presetButton-'+definition['id'])
        assert preset.isVisible()==bool(definition.get('phrases'))
        if preset.isVisible():
            assert preset.mapToScene(QPointF(0,0)).x()>control.mapToScene(QPointF(0,0)).x()+control.width()
    assert len({round(x.width()) for x in controls})>1
    assert controls[-1].height()>controls[0].height()
    assert len([x for x in descendants(card) if x.objectName()=='copyInlineMessage'])==1
    assert not any(x.property('text')==render(text['config']['segments'],{}) for x in descendants(card) if x.metaObject().indexOfProperty('text')>=0)
    before=c.store.event(c.active)
    for label in literals:
        original=label.property('text');label.forceActiveFocus()
        QTest.keyClick(root,Qt.Key_A,Qt.ControlModifier)
        QTest.keyClick(root,Qt.Key_Backspace);QTest.keyClick(root,Qt.Key_Delete)
        assert label.property('text')==original
    assert c.store.event(c.active)==before
    button=visual_child(card,'copyInlineMessage')
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,button.mapToScene(QPointF(button.width()/2,button.height()/2)).toPoint())
    assert app.clipboard().text()==render(text['config']['segments'],before['state'][text['id']]['values'])


def test_mixed_sentences_long_labels_and_text_after_fields_remain_separate(document,app):
    c,root,_,_=document
    mixed=c.store.event(c.active)['snapshot']['blocks'][1]
    card=visual_child(root.contentItem(),'runtimeBlock-'+mixed['id'])
    definitions=[s for s in mixed['config']['segments'] if s['kind']=='field']
    controls=[visual_child(card,'inlineField-'+f['id']) for f in definitions]
    assert len(controls)==3
    assert controls[0].mapToScene(QPointF(0,0)).y()==controls[1].mapToScene(QPointF(0,0)).y()
    labels=[x for x in descendants(card) if x.objectName()=='protectedLiteral']
    long=next(x for x in labels if x.property('text').startswith('Длинная'))
    assert long.height()>controls[-1].height()
    assert controls[-1].mapToScene(QPointF(0,0)).x()>long.mapToScene(QPointF(0,0)).x()+long.width()
    assert any('нельзя' in x.property('text') for x in labels)
    assert c.command('copy_text',json.dumps({'id':mixed['id']}))
    assert app.clipboard().text()==render(mixed['config']['segments'],{})
