"""Generate synthetic OLD records using the committed 0.1 application itself.

Run manually from a Git checkout with that historical commit available. Tests
consume the frozen SQL dump; they never need Git history or the current builder.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
OLD='4674b65'
SCRIPT=r'''
import json,sqlite3
from pathlib import Path
from PySide6.QtWidgets import QApplication
from operational_center.storage import Store
from operational_center.controller import Controller
app=QApplication([])
store=Store(Path('old.sqlite'))
c=Controller(store,Path('.'))
assert c.command('add_block',json.dumps({'type':'text'}))
block=c.selected_block
source='Время: \nМесто: '
fields=[]
for caption in ['Время: ','Место: ']:
 start=source.index(caption)
 result=c.insertField(source,start,start+len(caption),json.dumps(fields),caption.strip(': '))
 source,fields=result['source'],result['fields']
fields[0]['phrases']=['Время: 12:00','Уточняется']
assert c.saveTemplate(block,'Существующий шаблон 0.1',source,json.dumps(fields))
assert c.command('add_block',json.dumps({'type':'documents'}))
assert c.command('publish','{}')
master=c.selected_master
assert c.command('create_event',json.dumps({'id':master}))
first=c.active
c.setValue(block,fields[0]['id'],'Время: 14:35')
c.setValue(block,fields[1]['id'],'Место: Станция Пример')
assert c.command('create_event',json.dumps({'id':master}))
second=c.active
c.setValue(block,fields[0]['id'],'17:40')
c.setValue(block,fields[1]['id'],'Место: Другая станция')
assert c.command('archive_event',json.dumps({'id':second}))
metadata={'master_id':master,'block_id':block,'field_id':fields[0]['id'],'other_field_id':fields[1]['id'],'event_full':first,'event_value_only':second}
dump='\n'.join(store.db.iterdump())+'\nPRAGMA user_version=1;\n'
Path('fixture.sql').write_text(dump,encoding='utf-8')
Path('metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
store.close()
'''


def main():
    commit=subprocess.check_output(['git','rev-parse',OLD],cwd=ROOT,text=True).strip()
    output=ROOT/'tests/fixtures';output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='oper-historical-') as temp:
        folder=Path(temp)
        names=subprocess.check_output(['git','ls-tree','-r','--name-only',commit,'operational_center'],cwd=ROOT,text=True).splitlines()
        for name in names:
            if name.endswith('.py'):
                path=folder/name;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(subprocess.check_output(['git','show',commit+':'+name],cwd=ROOT))
        env={**os.environ,'QT_QPA_PLATFORM':'offscreen','QT_QUICK_BACKEND':'software'}
        subprocess.run([sys.executable,'-c',SCRIPT],cwd=folder,env=env,check=True)
        data=(folder/'fixture.sql').read_bytes()
        # Replace temporary machine paths with a fixed non-operational fixture
        # path; no external files are needed by the initialized document block.
        data=data.replace(str(folder).encode(),b'/synthetic-legacy-data')
        (output/'legacy-template-0.1.sql').write_bytes(data)
        metadata=json.loads((folder/'metadata.json').read_text())
        metadata.update(source_commit=commit,sql_sha256=hashlib.sha256(data).hexdigest(),synthetic=True,
                        method='0.1 Controller.insertField selected labels, saveTemplate, publish, create_event and setValue; SQLite iterdump')
        (output/'legacy-template-0.1.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Frozen historical fixture:',metadata['source_commit'],metadata['sql_sha256'])


if __name__=='__main__': main()
