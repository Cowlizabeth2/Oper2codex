import copy
import json
from pathlib import Path

import pytest
from PySide6.QtCore import QObject, QPointF, QPoint, Qt, QMetaObject, QUrl
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

from operational_center.controller import Controller
from operational_center.domain import inline_tokens, render, field
from tools.review_fixture import prepare
from test_qml import visual_child


def run(c, action, **args):
    assert c.command(action, json.dumps(args))


def center(item):
    return item.mapToScene(QPointF(item.width()/2,item.height()/2)).toPoint()


@pytest.fixture
def gui(app,store,tmp_path):
    master,text=prepare(store,tmp_path)
    c=Controller(store,tmp_path)
    run(c,'create_event',id=master['id'])
    run(c,'select_block',id=text['id'])
    engine=QQmlApplicationEngine()
    errors=[]
    engine.warnings.connect(lambda warnings: errors.extend(w.toString() for w in warnings))
    engine.rootContext().setContextProperty('backend',c)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1]/'operational_center/qml/Main.qml')))
    assert engine.rootObjects()
    root=engine.rootObjects()[0]
    screen=app.primaryScreen().availableGeometry()
    # Mouse injection must target the runner's real desktop; resolution/DPI
    # coverage is separately enforced by tools/visual_review.py.
    width=1366 if app.platformName()=='offscreen' else max(1024,min(1366,screen.width()))
    root.setPosition(0,0);root.resize(width,min(768,max(680,screen.height())));root.requestActivate()
    yield c,root,text
    root.close();del root;del engine
    assert not errors


def test_inline_tokenization_keeps_whitespace_and_field_identity():
    a,b=field('A'),field('B')
    segments=[{'kind':'text','text':'  До '},a,{'kind':'text','text':' / '},b,{'kind':'text','text':'\r\n\nПосле\tконец'}]
    before=copy.deepcopy(segments)
    tokens=inline_tokens(segments)
    assert [t['id'] for t in tokens if t['token']=='field']==[a['id'],b['id']]
    reconstructed=''.join('[[%s]]'%t['id'] if t['token']=='field' else t['text'] for t in tokens)
    assert reconstructed=='  До [[%s]] / [[%s]]\r\n\nПосле\tконец'%(a['id'],b['id'])
    assert segments==before
    assert [t['blank'] for t in tokens if t['token']=='break']==[False,True]


def test_group_geometry_is_atomic_undoable_and_clone_settings_independent(app,store,tmp_path):
    c=Controller(store,tmp_path)
    run(c,'add_block',type='text');a=c.selected_block
    run(c,'add_block',type='contacts');b=c.selected_block
    before=copy.deepcopy(c.state['master'])
    items=[dict(id=i,x=120+n*400,y=80,width=360,height=280) for n,i in enumerate([a,b])]
    run(c,'geometry_batch',items=items)
    assert [i['x'] for i in c.state['master']['blocks']]==[120,520]
    run(c,'undo');assert c.state['master']==before
    run(c,'redo')
    valid=copy.deepcopy(c.state['master'])
    bad=copy.deepcopy(items);bad[0]['x']=999;bad[1]['height']=0
    assert not c.command('geometry_batch',json.dumps({'items':bad}))
    assert c.state['master']==valid
    run(c,'copy_blocks',ids=[a,b]);run(c,'paste_blocks')
    blocks=c.state['master']['blocks']
    assert len(blocks)==4 and len({i['id'] for i in blocks})==4
    original=copy.deepcopy(blocks[0]['config'])
    run(c,'save_block',id=blocks[2]['id'],title='Другой',config={'segments':[{'kind':'text','text':'Независимо'}]})
    assert c.state['master']['blocks'][0]['config']==original


def test_legacy_snapshots_and_values_are_not_rewritten_by_new_ui(app,store,configured,tmp_path):
    master,block,a,b=configured
    event=store.create_event(master['id'])
    event['state'][block['id']]['values'].update({a['id']:'Старое значение',b['id']:'42'})
    store.save_state(event['id'],event['state'])
    before=tuple(store.db.execute('SELECT snapshot,state FROM events WHERE id=?',(event['id'],)).fetchone())
    config_before=store.config()
    c=Controller(store,tmp_path)
    runtime=c.state['event']['snapshot']['blocks'][0]
    assert runtime['preview']=='Перевозчик Старое значение, автобус 42.\nКонец сообщения.'
    assert [t['id'] for t in runtime['tokens'] if t['token']=='field']==[a['id'],b['id']]
    assert tuple(store.db.execute('SELECT snapshot,state FROM events WHERE id=?',(event['id'],)).fetchone())==before
    assert store.config()==config_before
    assert store.db.execute('PRAGMA user_version').fetchone()[0]==1


def test_inline_gui_newlines_input_presets_exact_copy_and_independent_tabs(gui,app):
    c,root,text=gui
    root.setProperty('page','events');QTest.qWait(150)
    fields=[s for s in text['config']['segments'] if s['kind']=='field']
    controls=[visual_child(root.contentItem(),'inlineField-'+s['id']) for s in fields]
    assert all(x is not None for x in controls)
    positions=[x.mapToScene(QPointF(0,0)) for x in controls]
    assert abs(positions[0].y()-positions[1].y())<2
    assert positions[2].y()>positions[0].y()
    assert positions[3].y()>positions[2].y()
    assert positions[4].y()>positions[3].y()
    static=visual_child(root.contentItem(),'protectedLiteral')
    literal=static.property('text')
    static.forceActiveFocus()
    QTest.keyClick(root,Qt.Key_X)
    assert static.property('text')==literal
    controls[0].forceActiveFocus()
    QTest.keyClick(root,Qt.Key_A,Qt.ControlModifier)
    QTest.keyClick(root,Qt.Key_1);QTest.keyClick(root,Qt.Key_2)
    assert c.store.event(c.active)['state'][text['id']]['values'][fields[0]['id']]=='12'
    carrier_before=controls[2]
    button=visual_child(root.contentItem(),'presetButton-'+fields[2]['id'])
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,center(button));QTest.qWait(50)
    item=visual_child(root.contentItem(),'presetChoice-'+fields[2]['id']+'-1')
    assert item is not None
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,center(item));QTest.qWait(50)
    assert visual_child(root.contentItem(),'inlineField-'+fields[2]['id'])==carrier_before
    assert carrier_before.property('text')=='Стартранс'
    run(c,'copy_text',id=text['id'])
    expected=render(text['config']['segments'],c.store.event(c.active)['state'][text['id']]['values'])
    assert app.clipboard().text()==expected
    assert expected.startswith('Время: 12  Место: ') and '\nПеревозчик: Стартранс\n' in expected
    first=c.active
    run(c,'create_event',id=c.selected_master)
    assert c.store.event(c.active)['state'][text['id']]['values'][fields[0]['id']]=='14:35'
    run(c,'select_event',id=first);QTest.qWait(100)
    assert visual_child(root.contentItem(),'inlineField-'+fields[0]['id']).property('text')=='12'
    assert c.eventHistory(first)[0]['message']=='Открыта карточка'


def test_builder_theme_change_does_not_discard_unsaved_template(gui):
    c,root,text=gui
    root.setProperty('page','builder');QTest.qWait(100)
    source=visual_child(root.contentItem(),'templateSourceEditor')
    assert source is not None
    unsaved=source.property('text')+'\nНесохранённый абзац'
    source.setProperty('text',unsaved)
    run(c,'theme',name='light');QTest.qWait(100)
    assert source.property('text')==unsaved
    assert root.property('color').name()=='#f2f5fa'
    run(c,'ui_scale',value=1.25);QTest.qWait(100)
    assert source.property('text')==unsaved
    assert c.themes.uiScale==1.25


def test_fit_and_sidebar_never_rewrite_logical_geometry(gui):
    c,root,text=gui
    before=copy.deepcopy(c.store.event(c.active)['snapshot'])
    root.setProperty('page','events');QTest.qWait(100)
    QMetaObject.invokeMethod(root.property('activePage'),'fitContents',Qt.DirectConnection)
    run(c,'sidebar',collapsed=True);QTest.qWait(100)
    root.resize(1920,1080);QTest.qWait(50)
    assert c.store.event(c.active)['snapshot']==before
    assert c.state['sidebarCollapsed'] is True


def test_event_audit_is_private_independent_and_coalesces_typing(app,store,configured,tmp_path):
    master,block,a,b=configured
    c=Controller(store,tmp_path)
    run(c,'create_event',id=master['id']);first=c.active
    c.setValue(block['id'],a['id'],'Секретное значение')
    c.setValue(block['id'],a['id'],'Другое значение')
    assert len(c.eventHistory(first))==2
    assert 'Секретное' not in json.dumps(c.eventHistory(first),ensure_ascii=False)
    run(c,'create_event',id=master['id']);second=c.active
    assert len(c.eventHistory(second))==1 and first!=second
    backup=store.backup(tmp_path/'audit.sqlite')
    store.restore(backup)
    assert len(c.eventHistory(first))==2


def test_designer_creates_field_from_actual_mouse_selection(gui):
    from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QRectF
    c,root,text=gui
    root.setProperty('page','builder');QTest.qWait(100)
    source=visual_child(root.contentItem(),'templateSourceEditor')
    source.setProperty('text','Сообщение: Перевозчик.')
    source.forceActiveFocus()
    start=QMetaObject.invokeMethod(source,'positionToRectangle',Qt.DirectConnection,Q_RETURN_ARG(QRectF),Q_ARG(int,11))
    end=QMetaObject.invokeMethod(source,'positionToRectangle',Qt.DirectConnection,Q_RETURN_ARG(QRectF),Q_ARG(int,21))
    a=source.mapToScene(start.center()).toPoint();b=source.mapToScene(end.center()).toPoint()
    QTest.mousePress(root,Qt.LeftButton,Qt.NoModifier,a)
    QTest.mouseMove(root,b,50)
    QTest.mouseRelease(root,Qt.LeftButton,Qt.NoModifier,b)
    assert source.property('selectedText')=='Перевозчик'
    visual_child(root.contentItem(),'newFieldLabel').setProperty('text','Перевозчик')
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,center(visual_child(root.contentItem(),'createTemplateField')))
    inspector=visual_child(root.contentItem(),'blockInspector')
    QMetaObject.invokeMethod(inspector,'save',Qt.DirectConnection)
    cfg=c.state['selectedBlock']['config']
    fields=[s for s in cfg['segments'] if s['kind']=='field']
    assert len(fields)==1 and fields[0]['default']=='Перевозчик'
    assert render(cfg['segments'],{})=='Сообщение: Перевозчик.'


def test_builder_ctrl_selection_group_drag_and_clickable_arrow(gui):
    c,root,text=gui
    original_event=c.active
    blocks=c.state['master']['blocks']
    first,second=blocks[0]['id'],blocks[1]['id']
    run(c,'geometry_batch',items=[dict(id=first,x=232,y=40,width=320,height=260),dict(id=second,x=592,y=40,width=320,height=260)])
    root.setProperty('page','builder');QTest.qWait(100)
    root.property('activePage').setProperty('showInspector',False);QTest.qWait(50)
    one=visual_child(root.contentItem(),'dragHandle-'+first)
    two=visual_child(root.contentItem(),'dragHandle-'+second)
    a=one.mapToScene(QPointF(20,20)).toPoint();b=two.mapToScene(QPointF(20,20)).toPoint()
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,a)
    QTest.mouseClick(root,Qt.LeftButton,Qt.ControlModifier,b);QTest.qWait(50)
    one=visual_child(root.contentItem(),'dragHandle-'+first)
    a=one.mapToScene(QPointF(20,20)).toPoint()
    QTest.mousePress(root,Qt.LeftButton,Qt.NoModifier,a)
    QTest.mouseMove(root,a+QPoint(20,20),30)
    QTest.mouseMove(root,a+QPoint(40,40),30)
    QTest.mouseRelease(root,Qt.LeftButton,Qt.NoModifier,a+QPoint(40,40));QTest.qWait(50)
    moved={b['id']:b for b in c.state['master']['blocks']}
    assert moved[first]['x']>232 and moved[second]['x']>592
    assert moved[first]['x']-232==moved[second]['x']-592
    assert moved[first]['y']-40==moved[second]['y']-40
    page=root.property('activePage');page.setProperty('linkMode',True);QTest.qWait(50)
    viewport=visual_child(root.contentItem(),'builderViewport')
    stage=viewport.property('stage')
    edges=viewport.property('edges')
    if hasattr(edges,'toVariant'): edges=edges.toVariant()
    points=edges[0]['points']
    midpoint=stage.mapToScene(QPointF((points[1]['x']+points[2]['x'])/2,(points[1]['y']+points[2]['y'])/2)).toPoint()
    QTest.mouseClick(root,Qt.LeftButton,Qt.NoModifier,midpoint);QTest.qWait(50)
    dialog=root.findChild(QObject,'confirmationDialog')
    assert dialog is not None and dialog.property('visible')
    QMetaObject.invokeMethod(dialog,'accept',Qt.DirectConnection);QTest.qWait(50)
    assert first not in c.state['master']['links']
    assert len(c.state['master']['blocks'])==4
    run(c,'publish');run(c,'create_event',id=c.selected_master)
    assert len(c.state['event']['snapshot']['blocks'])==3
    assert len(c.store.event(original_event)['snapshot']['blocks'])==4


def test_readable_editor_markers_roundtrip_without_persisting_aliases():
    from operational_center.domain import editor_template, parse_editor_template
    a,b=field('Перевозчик'),field('Перевозчик')
    segments=[{'kind':'text','text':'Любой текст ⟦1 · Перевозчик⟧: '},a,{'kind':'text','text':' / '},b]
    source,fields=editor_template(segments)
    assert a['id'] not in source and b['id'] not in source
    assert fields[0]['_editor_token']!=fields[1]['_editor_token']
    assert parse_editor_template(source,fields)==segments
    assert '_editor_token' not in json.dumps(parse_editor_template(source,fields))


def test_saving_appearance_keeps_unsaved_template_changes_and_is_one_undo(gui):
    c,root,text=gui
    root.setProperty('page','builder');QTest.qWait(100)
    before=copy.deepcopy(c.state['selectedBlock'])
    source=visual_child(root.contentItem(),'templateSourceEditor')
    source.setProperty('text',source.property('text')+'\nДополнение')
    visual_child(root.contentItem(),'blockAccent').setProperty('text','#36B89B')
    QMetaObject.invokeMethod(visual_child(root.contentItem(),'blockInspector'),'save',Qt.DirectConnection)
    current=c.state['selectedBlock']
    assert current['accent']=='#36B89B'
    assert render(current['config']['segments'],{}).endswith('\nДополнение')
    assert len([s for s in current['config']['segments'] if s['kind']=='field'])==5
    run(c,'undo')
    assert c.state['selectedBlock']==before
