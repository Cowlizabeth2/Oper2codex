"""Real event fixtures for the TextTemplateBlock visual acceptance review."""
from operational_center.domain import field, new_block
from tools.review_fixture import prepare as base_prepare


def prepare(store, root):
    master, text = base_prepare(store, root)
    fields = [s for s in text['config']['segments'] if s['kind']=='field']
    fields[3].update(label='Событие',multiline=False,default='Столкновение автомобилей')
    fields.append(field('Обстоятельства',multiline=True,default='Движение затруднено.\nОбстоятельства уточняются.'))
    segments=[]
    for index, definition in enumerate(fields):
        segments.extend([{'kind':'text','text':('\n' if index else '')+definition['label']+': '},definition])
    text['config']['segments']=segments
    text.update(width=560,height=468)
    mixed=new_block('text')
    mixed.update(title='Смешанный текстовый документ',x=844,y=40,width=440,height=468)
    a=field('Маршрут',default='42');b=field('Направление',default='центр',phrases=['центр','область'])
    long=field('Дополнение',default='Информация подтверждена')
    mixed['config']['segments']=[{'kind':'text','text':'На маршруте '},a,{'kind':'text','text':' в направлении '},b,{'kind':'text','text':' движение восстановлено.\n\nДлинная неизменяемая подпись с дополнительным уточнением места происшествия: '},long,{'kind':'text','text':'\n\nЭтот текст после полей также нельзя редактировать.'}]
    _,config=store.config('draft')
    master=config['masters'][0]
    master.update(blocks=[text,mixed],links=[text['id'],mixed['id']])
    store.save_draft(config);store.publish()
    return master,text
