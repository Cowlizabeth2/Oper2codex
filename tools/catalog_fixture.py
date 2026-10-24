"""Synthetic 300-station catalog and import proposal for visual review only."""
from pathlib import Path
from openpyxl import Workbook

from operational_center.catalog import new_catalog
from operational_center.domain import new_master, new_block
from tools.review_fixture import prepare as base_prepare


def prepare(store, root):
    master, text = base_prepare(store, root)
    _, config = store.config('draft')
    master = config['masters'][0]
    block = new_block('static_text')
    block.update(title='Памятка дежурному', x=text['x'], y=text['y'], width=text['width'], height=text['height'])
    block['config'].update(format='markdown', text='# Порядок действий\n\n**Уточните место и характер происшествия.**\n\n1. Проверьте адрес и наличие пострадавших.\n2. Передайте информацию оперативному дежурному.\n3. Заполните рабочую копию документа.\n\n*Используйте контакты оповещения справа.*\n\n__Содержание памятки изменяет разработчик.__')
    master['blocks'][0] = block
    master['links'] = [block['id'] if i == text['id'] else i for i in master['links']]
    stations = []
    for n in range(1, 301):
        m = new_master('Станция '+str(n), 'metro_'+str(n))
        m.update(km_code='КМ '+str(n), category='Линия '+str(n%3+1), aliases=['Станционная '+str(n)], tags=['метро', 'пересадка'])
        stations.append(m)
    stations[0].update(name='Семёновская', aliases=['СМН', 'Семеновская'])
    config['masters'].extend(stations)
    catalog = new_catalog();catalog.update(name='Станции метро · КМ', icon='М', members=[m['id'] for m in stations])
    config['catalogs'] = [catalog]
    store.save_draft(config);store.publish()
    file = Path(root)/'Импорт сценариев.xlsx'
    book = Workbook()
    book.active.append(['Название','Системный код','Поисковые теги','Альтернативные названия','Категория','Папка документов','Шаблон','Код КМ'])
    for n in range(301,304):
        book.active.append(['Новая станция '+str(n),'metro_'+str(n),'метро;пересадка','Альтернативная '+str(n),'Линия 4','',master['tag'],'КМ '+str(n)])
    book.active.append(['Повтор существующего кода','metro_1','','','','',master['tag'],''])
    book.active.append(['Недоступная папка','bad_path','','','',str(Path(root)/'Нет такой папки'),master['tag'],''])
    book.save(file);book.close()
    return master, block, file
