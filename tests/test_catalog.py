import copy
import json
from pathlib import Path

import pytest
from openpyxl import Workbook
from PySide6.QtCore import QUrl, QPointF, Qt, QMetaObject, QObject
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest

from operational_center.catalog import new_catalog, normalize, search
from operational_center.controller import Controller
from operational_center.domain import new_master, new_block, validate_config
from operational_center.scenario_import import prepare, apply, sample
from operational_center.static_text import presentation
from operational_center.storage import Store
from test_qml import visual_child


def run(c, action, **args):
    assert c.command(action, json.dumps(args, ensure_ascii=False)), (action, args)


def click(root, item):
    assert item is not None and item.isVisible()
    QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, item.mapToScene(QPointF(item.width()/2, item.height()/2)).toPoint())
    QTest.qWait(50)


@pytest.fixture
def catalog_config(store, tmp_path):
    _, config = store.config('draft')
    masters = []
    for n in range(1, 301):
        m = new_master('Станция '+str(n), 'station_'+str(n))
        m.update(km_code='КМ '+str(n), aliases=['Альтернатива '+str(n)], tags=['пересадка' if n%2 else 'выход'], category='Линия '+str(n%3))
        masters.append(m)
    masters[0].update(name='Семёновская', aliases=['Семёново', 'СМН'], tags=['пересадка', 'восток'])
    masters[1]['name'] = 'Семёновская площадь'
    text = new_block('static_text')
    text.update(x=260, y=40)
    text['config']['text'] = '  Строка 1\r\n\r\nСтрока 2\tконец\n'
    doc = new_block('documents')
    doc.update(x=692, y=40)
    source = tmp_path/'Исходник.txt'
    source.write_text('Оригинал', encoding='utf-8')
    doc['config']['sources'] = [str(source)]
    masters[0].update(blocks=[text, doc], links=[text['id'], doc['id']])
    first, second = new_catalog(), new_catalog()
    first.update(name='Станции', icon='М', members=[m['id'] for m in masters])
    second.update(name='Восток', members=[masters[0]['id']])
    config['masters'].extend(masters)
    config['catalogs'] = [first, second]
    store.save_draft(config); store.publish()
    return config, masters, first, second, text, doc


def test_catalog_300_ranked_search_and_km_boundaries(catalog_config):
    config, masters, cat, _, _, _ = catalog_config
    def find(q, **kw): return search(config, cat['id'], q, **kw)
    assert len(find('')) == 300
    assert normalize('  СЕМЁНОВСКАЯ  ') == 'семеновская'
    assert find('  СЕМЕНОВСКАЯ ')[0]['id'] == masters[0]['id']
    assert find('семеновская')[0]['exact']
    assert find('СМН')[0]['id'] == masters[0]['id']
    assert find('восток')[0]['id'] == masters[0]['id']
    assert len(find('пересадка')) == 150
    assert find('station_281')[0]['id'] == masters[280]['id']
    for q in ['КМ1', 'КМ-1', 'km №001', 'км 1']:
        assert [m['id'] for m in find(q)] == [masters[0]['id']]
    assert [m['id'] for m in find('КМ 10')] == [masters[9]['id']]
    assert len(find('', category='Линия 1')) == 100
    # A favorite partial match must not outrank an exact station match.
    assert find('семеновская', favorites=[masters[1]['id']])[0]['id'] == masters[0]['id']
    assert not find('несуществующая станция')


def test_launch_two_independent_events_real_ids_context_documents_and_restart(app, store, tmp_path, catalog_config):
    config, masters, cat, _, text, doc = catalog_config
    c = Controller(store, tmp_path)
    run(c, 'launch_catalog', id=masters[0]['id'], catalog=cat['id'])
    first = store.event(c.active)
    path1 = Path(first['state'][doc['id']]['files'][0]['path'])
    path1.write_text('Правки первого', encoding='utf-8')
    run(c, 'launch_catalog', id=masters[0]['id'], catalog=cat['id'])
    second = store.event(c.active)
    assert first['id'] != second['id'] and first['number'] != second['number']
    assert first['master_id'] == second['master_id'] == masters[0]['id']
    assert first['snapshot']['km_code'] == 'КМ 1'
    assert {b['id'] for b in first['snapshot']['blocks']} == {text['id'], doc['id']}
    path2 = Path(second['state'][doc['id']]['files'][0]['path'])
    assert path2 != path1 and path2.read_text(encoding='utf-8') == 'Оригинал'
    run(c, 'catalog_favorite', id=masters[0]['id'])
    run(c, 'catalog_favorite', id=masters[10]['id'])
    assert len(c.searchCatalog(cat['id'], '', '', 'favorites')) == 2
    assert len(c.searchCatalog(cat['id'], '', '', 'recent')) == 1
    assert store.config()[1] == config
    with StoreContext(store.path) as reopened:
        again = Controller(reopened, tmp_path)
        assert len(again.searchCatalog(cat['id'], '', '', 'favorites')) == 2
        assert again.searchCatalog(cat['id'], '', '', 'recent')[0]['id'] == masters[0]['id']
        assert path1.read_text(encoding='utf-8') == 'Правки первого'
        assert reopened.config()[1] == config
        assert len(reopened.events()) == 2
    assert not c.command('launch_catalog', json.dumps({'catalog':cat['id'], 'id':config['masters'][0]['id']}))
    assert len(store.events()) == 2


class StoreContext:
    def __init__(self, path): self.path = path
    def __enter__(self): self.store = Store(self.path); return self.store
    def __exit__(self, *args): self.store.close()


def test_membership_edit_and_catalog_delete_preserve_source(app, store, tmp_path, catalog_config):
    _, masters, cat, other, _, _ = catalog_config
    c = Controller(store, tmp_path)
    original = copy.deepcopy(store.config('draft')[1]['masters'])
    run(c, 'save_catalog', **{**cat, 'members':cat['members'][1:]})
    run(c, 'delete_catalog', id=cat['id'])
    draft = store.config('draft')[1]
    assert draft['masters'] == original and draft['catalogs'] == [other]
    run(c, 'undo')
    assert len(store.config('draft')[1]['catalogs']) == 2
    run(c, 'select_master', id=masters[0]['id'])
    run(c, 'delete_master')
    assert all(masters[0]['id'] not in item['members'] for item in store.config('draft')[1]['catalogs'])


def test_static_multiple_edit_copy_snapshot_and_hidden_button(app, store, tmp_path):
    c = Controller(store, tmp_path)
    ids=[]
    for text in ['  Первая\r\n\r\nВторая\t\n', 'Другой текст']:
        run(c, 'add_block', type='static_text'); ids.append(c.selected_block)
        cfg = {**new_block('static_text')['config'], 'text':text}
        run(c, 'save_block', id=c.selected_block, title='Памятка', config=cfg, accent='#AABBCC')
    master = c.state['master']
    run(c, 'publish'); run(c, 'create_event', id=master['id'])
    run(c, 'copy_static', id=ids[0])
    assert app.clipboard().text() == master['blocks'][0]['config']['text']
    original = store.event(c.active)['snapshot']
    cfg = {**master['blocks'][0]['config'], 'text':'Новая памятка', 'copy_enabled':False}
    run(c, 'save_block', id=ids[0], title='Новая', config=cfg)
    run(c, 'publish')
    assert store.event(c.active)['snapshot'] == original
    run(c, 'create_event', id=master['id'])
    assert not c.command('copy_static', json.dumps({'id':ids[0]}))
    assert store.event(c.active)['state'][ids[0]]['values'] == {}
    assert store.db.execute('PRAGMA user_version').fetchone()[0] == 1
    with StoreContext(store.path) as reopened:
        assert reopened.config()[1]['masters'][0]['blocks'][0]['config'] == cfg
        assert len(reopened.config()[1]['masters'][0]['blocks']) == 2


def test_static_formatting_is_safe_and_preserves_copy_line_endings():
    source = '# Памятка\r\n**Жирный** и *курсив* и __линия__\n<script>x</script>\n'
    shown = presentation({'text':source, 'format':'markdown'})
    assert shown['plain'] == 'Памятка\r\nЖирный и курсив и линия\n<script>x</script>\n'
    assert '<b>Жирный</b>' in shown['html'] and '<i>курсив</i>' in shown['html']
    assert '<u>линия</u>' in shown['html'] and '<script>' not in shown['html']


@pytest.mark.parametrize('extra', [{'fields':[]}, {'phrases':[]}, {'segments':[]}, {'font_size':0}, {'format':'html'}])
def test_static_rejects_template_fields(store, extra):
    config = store.config('draft')[1]
    block=new_block('static_text');block['config'].update(extra)
    config['masters'][0]['blocks']=[block]
    with pytest.raises(ValueError): validate_config(config)


def workbook(path, rows):
    book=Workbook()
    book.active.append(['Название','Системный код','Поисковые теги','Альтернативные названия','Категория','Папка документов','Шаблон','Код КМ'])
    for row in rows: book.active.append(row)
    book.save(path);book.close()
    return path


def test_excel_preview_duplicates_missing_paths_atomic_append_and_links(app, store, tmp_path, configured):
    master, block, _, _ = configured
    before=copy.deepcopy(store.config('draft')[1])
    folder=tmp_path/'документы';folder.mkdir();(folder/'Акт.txt').write_text('Акт',encoding='utf-8')
    file=workbook(tmp_path/'import.xlsx', [
        ['Семёновская','metro_1','метро;восток','СМН;Семёново','Линия 3',str(folder),master['tag'],'КМ 1'],
        ['Дубль существующего',master['tag'],'','','','',master['tag'],''],
        ['Дубль А','duplicate','','','','',master['tag'],''],
        ['Дубль Б','DUPLICATE','','','','',master['tag'],''],
        ['Нет пути','bad_path','','','',str(tmp_path/'нет'),master['tag'],''],
        ['Нет шаблона','bad_template','','','','','unknown',''],
        ['Формула','=1+2','','','','',master['tag'],''],
    ])
    proposal=prepare(file,before)
    assert proposal['valid']==1 and proposal['invalid']==6
    assert store.config('draft')[1]==before
    assert 'уже существует' in proposal['rows'][1]['errors'][0]
    assert 'Дубликат' in proposal['rows'][2]['errors'][0]
    catalog=new_catalog();before['catalogs']=[catalog];store.save_draft(before)
    c=Controller(store,tmp_path)
    run(c,'preview_scenarios',path=str(file))
    token=c.state['importPreview']['token']
    assert 'masters' not in c.state['importPreview']
    assert not c.command('commit_scenarios',json.dumps({'token':token,'confirmed':False}))
    assert store.config('draft')[1]==before
    run(c,'commit_scenarios',token=token,confirmed=True,catalog=catalog['id'])
    after=store.config('draft')[1]
    assert after['masters'][:-1]==before['masters']
    imported=after['masters'][-1]
    assert imported['aliases']==['СМН','Семёново'] and imported['tags']==['метро','восток']
    assert imported['id']!=master['id'] and imported['blocks'][0]['id']!=block['id']
    assert len(imported['links'])==2
    assert after['catalogs'][0]['members']==[imported['id']]
    run(c,'publish');run(c,'launch_catalog',catalog=catalog['id'],id=imported['id'])
    event=store.event(c.active)
    doc=next(b for b in imported['blocks'] if b['type']=='documents')
    assert Path(event['state'][doc['id']]['files'][0]['path']).read_text(encoding='utf-8')=='Акт'
    assert not c.command('commit_scenarios',json.dumps({'token':token,'confirmed':True}))


def test_excel_stale_draft_and_disappearing_path_never_write(store, tmp_path):
    config=store.config('draft')[1]
    folder=tmp_path/'source';folder.mkdir()
    file=workbook(tmp_path/'import.xlsx',[['Новая','new','','','',str(folder),'dtp','']])
    proposal=prepare(file,config)
    stale=copy.deepcopy(config);stale['masters'][0]['name']='Изменено'
    with pytest.raises(ValueError,match='изменился'): apply(stale,proposal)
    assert len(stale['masters'])==3
    folder.rmdir()
    with pytest.raises(ValueError,match='недоступ'): apply(config,proposal)
    assert len(config['masters'])==3 and store.config('draft')[1]==config


def test_excel_sample_and_duplicate_headers(store, tmp_path):
    path=tmp_path/'sample.xlsx';sample(path)
    assert prepare(path,store.config('draft')[1])['valid']==1
    with pytest.raises(FileExistsError): sample(path)
    book=Workbook();book.active.append(['Название','name','Системный код','Шаблон']);book.save(tmp_path/'bad.xlsx');book.close()
    with pytest.raises(ValueError,match='Повторяющийся'): prepare(tmp_path/'bad.xlsx',store.config('draft')[1])


def test_excel_numeric_zero_is_a_valid_code_not_an_empty_cell(store, tmp_path):
    file=workbook(tmp_path/'numeric.xlsx',[[0,0,'','','','','dtp',0]])
    proposal=prepare(file,store.config('draft')[1])
    assert proposal['valid']==1
    master=proposal['masters'][0]
    assert master['name']==master['tag']==master['km_code']=='0'


def test_excel_300_scenarios_relink_clones_and_preserve_existing_data(app, store, tmp_path, configured):
    master, _, _, _ = configured
    c=Controller(store,tmp_path)
    original=copy.deepcopy(store.config('draft')[1]['masters'])
    run(c,'create_event',id=master['id'])
    event_before=store.event(c.active)
    run(c,'new_catalog');catalog=c.state['draft']['catalogs'][0]
    file=workbook(tmp_path/'bulk.xlsx',[[f'Станция {n}',f'bulk_{n}','метро',f'Алиас {n}','Линия 1','',master['tag'],f'КМ {n}'] for n in range(1,301)])
    run(c,'preview_scenarios',path=str(file))
    preview=c.state['importPreview'];assert preview['valid']==300 and preview['invalid']==0
    run(c,'commit_scenarios',token=preview['token'],confirmed=True,catalog=catalog['id'])
    draft=store.config('draft')[1]
    assert draft['masters'][:len(original)]==original
    imported=draft['masters'][len(original):]
    assert {m['tag'] for m in imported}=={f'bulk_{n}' for n in range(1,301)}
    assert len({b['id'] for m in imported for b in m['blocks']})==300
    assert all(m['links']==[m['blocks'][0]['id']] for m in imported)
    assert set(draft['catalogs'][0]['members'])=={m['id'] for m in imported}
    assert store.event(event_before['id'])==event_before
    run(c,'publish')
    assert len(c.searchCatalog(catalog['id'],'','','all'))==300
    run(c,'undo')
    assert store.config('draft')[1]['masters']==original
    assert len(c.searchCatalog(catalog['id'],'','','all'))==300  # Undo changes only the draft.


@pytest.fixture
def gui(app, store, tmp_path, catalog_config):
    c=Controller(store,tmp_path)
    engine=QQmlApplicationEngine();errors=[]
    engine.warnings.connect(lambda ws: errors.extend(w.toString() for w in ws))
    engine.rootContext().setContextProperty('backend',c)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1]/'operational_center/qml/Main.qml')))
    assert engine.rootObjects()
    root=engine.rootObjects()[0]
    screen=app.primaryScreen().availableGeometry()
    root.setPosition(0,0);root.resize(1366 if app.platformName()=='offscreen' else max(1024,min(1366,screen.width())),min(768,max(680,screen.height())));root.requestActivate()
    QTest.qWait(100)
    yield c,root,catalog_config
    root.close();del root;del engine
    assert not errors


@pytest.mark.parametrize('opening',['compact','wide','panel'])
def test_catalog_gui_300_keyboard_search_enter_escape_and_favorites(gui, app, opening):
    c,root,(_,masters,cat,_,text,_) = gui
    run(c,'save_catalog',**{**cat,'opening':opening});run(c,'publish');QTest.qWait(50)
    click(root,visual_child(root.contentItem(),'catalogCard-'+cat['id']))
    popup=root.findChild(QObject,'catalogSearchDialog')
    assert popup.property('modal')==(opening!='panel')
    query=visual_child(root.contentItem(),'catalogQuery')
    assert query is not None
    app.clipboard().setText('СЕМЕНОВСКАЯ')
    query.forceActiveFocus();QTest.keyClick(root,Qt.Key_V,Qt.ControlModifier);QTest.qWait(100)
    results=visual_child(root.contentItem(),'catalogResults')
    assert results.property('count')==2
    QTest.keyClick(root,Qt.Key_Down);assert results.property('currentIndex')==1
    QTest.keyClick(root,Qt.Key_Up);assert results.property('currentIndex')==0
    QTest.keyClick(root,Qt.Key_Return);QTest.qWait(150)
    assert store_event(c)['master_id']==masters[0]['id']
    display=visual_child(root.contentItem(),'staticDisplay-'+text['id'])
    assert display is not None
    click(root,visual_child(root.contentItem(),'copyStatic-'+text['id']))
    assert app.clipboard().text()==text['config']['text']
    root.setProperty('page','home');QTest.qWait(100)
    click(root,visual_child(root.contentItem(),'catalogCard-'+cat['id']))
    click(root,visual_child(root.contentItem(),'catalogFavorite-'+masters[0]['id']))
    assert masters[0]['id'] in c.state['catalogFavorites']
    QTest.keyClick(root,Qt.Key_Escape);QTest.qWait(50)
    assert len(c.store.events())==1


def store_event(c): return c.store.event(c.active)


def test_gui_catalog_management_and_excel_confirmation(gui, tmp_path):
    c,root,_=gui
    QMetaObject.invokeMethod(root,'manageCatalogs',Qt.DirectConnection);QTest.qWait(100)
    click(root,visual_child(root.contentItem(),'newCatalog'))
    name=visual_child(root.contentItem(),'catalogName');name.setProperty('text','Новый поиск')
    click(root,visual_child(root.contentItem(),'saveCatalog'))
    assert c.state['draft']['catalogs'][-1]['name']=='Новый поиск'
    QTest.keyClick(root,Qt.Key_Escape);QTest.qWait(50)
    file=workbook(tmp_path/'gui.xlsx',[['Новая станция','gui_code','метро','Алиас','Линия','','dtp','КМ 500']])
    QMetaObject.invokeMethod(root,'importScenarios',Qt.DirectConnection);QTest.qWait(100)
    visual_child(root.contentItem(),'scenarioImportPath').setProperty('text',str(file))
    before=len(c.state['draft']['masters'])
    button=visual_child(root.contentItem(),'commitScenarios')
    assert not button.isEnabled()
    click(root,visual_child(root.contentItem(),'previewScenarios'))
    assert c.state['importPreview']['valid']==1 and not button.isEnabled()
    assert len(c.state['draft']['masters'])==before
    click(root,visual_child(root.contentItem(),'confirmScenarioImport'))
    assert button.isEnabled()
    click(root,button)
    assert len(c.state['draft']['masters'])==before+1
    assert c.state['draft']['masters'][-1]['tag']=='gui_code'


def test_gui_static_editor_save_theme_and_read_only_runtime(gui, app):
    c,root,_=gui
    root.setProperty('page','builder')
    run(c,'add_block',type='static_text');first=c.selected_block
    QTest.qWait(100)
    source=visual_child(root.contentItem(),'staticTextEditor')
    source.forceActiveFocus();QTest.keyClick(root,Qt.Key_A,Qt.ControlModifier)
    app.clipboard().setText('Первая строка\nВторая строка')
    QTest.keyClick(root,Qt.Key_V,Qt.ControlModifier)
    run(c,'theme',name='light');QTest.qWait(50)
    assert source.property('text')=='Первая строка\nВторая строка'
    inspector=visual_child(root.contentItem(),'blockInspector')
    QMetaObject.invokeMethod(inspector,'save',Qt.DirectConnection);QTest.qWait(50)
    assert c.state['selectedBlock']['config']['text']=='Первая строка\nВторая строка'
    run(c,'add_block',type='static_text');second=c.selected_block
    assert second!=first
    cfg=copy.deepcopy(c.state['selectedBlock']['config']);cfg.update(text='Только чтение',copy_enabled=False)
    run(c,'save_block',id=second,title='Без кнопки',config=cfg)
    run(c,'publish');run(c,'create_event',id=c.selected_master)
    root.setProperty('page','events');QTest.qWait(100)
    assert visual_child(root.contentItem(),'copyStatic-'+first).isVisible()
    assert not visual_child(root.contentItem(),'copyStatic-'+second).isVisible()
    display=visual_child(root.contentItem(),'staticDisplay-'+second)
    before=display.property('text');display.forceActiveFocus();QTest.keyClick(root,Qt.Key_X)
    assert display.property('text')==before and c.store.event(c.active)['state'][second]['values']=={}
