"""Capture real QML screens in both themes; never open a user's database."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtCore import QUrl, QMetaObject, Qt, qInstallMessageHandler, QtMsgType
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFontInfo
from PySide6.QtTest import QTest
from operational_center.storage import Store
from operational_center.controller import Controller
from tools.review_fixture import prepare


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=Path('artifacts/visual'))
    parser.add_argument('--sizes',default='1920x1080,1366x768')
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    if sys.platform=='win32' and os.environ.get('QT_QPA_PLATFORM')=='offscreen':
        # The offscreen plugin uses Qt's basic font database, not the native
        # Windows font service. Point it at the fonts already on this runner.
        os.environ.setdefault('QT_QPA_FONTDIR',str(Path(os.environ.get('WINDIR',r'C:\Windows'))/'Fonts'))
    app=QApplication.instance() or QApplication([])
    warnings=[]
    def handler(kind,context,message):
        if kind in [QtMsgType.QtWarningMsg,QtMsgType.QtCriticalMsg,QtMsgType.QtFatalMsg]: warnings.append(message)
    old=qInstallMessageHandler(handler)
    report={'screens':[],'qml_errors':warnings,'scale_factor':os.environ.get('QT_SCALE_FACTOR','1'),'platform':app.platformName()}
    with tempfile.TemporaryDirectory(prefix='oper-visual-') as temp:
        store=Store(Path(temp)/'review.sqlite')
        master,text=prepare(store,temp)
        backend=Controller(store,temp,os.environ.get('GITHUB_SHA','development'))
        backend.command('create_event',json.dumps({'id':master['id']}))
        backend.command('create_event',json.dumps({'id':master['id']}))
        backend.command('select_block',json.dumps({'id':text['id']}))
        engine=QQmlApplicationEngine()
        engine.rootContext().setContextProperty('backend',backend)
        engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1]/'operational_center/qml/Main.qml')))
        if not engine.rootObjects(): raise RuntimeError('QML failed to load')
        root=engine.rootObjects()[0]
        report['requested_font']=root.property('font').family()
        report['resolved_font']=QFontInfo(root.property('font')).family()
        root.setPosition(0,0)
        for size in args.sizes.split(','):
            width,height=map(int,size.split('x'))
            root.resize(width,height)
            for theme in ['dark','light']:
                backend.command('theme',json.dumps({'name':theme}))
                for page in ['home','events','history','builder','settings','logs']:
                    root.setProperty('page',page)
                    QTest.qWait(120)
                    current=root.property('activePage')
                    if page in ['events','builder']:
                        QMetaObject.invokeMethod(current,'focusContents' if page=='events' else 'fitContents',Qt.DirectConnection)
                        if page=='builder': current.setProperty('linkMode',True)
                    QTest.qWait(100)
                    image=root.grabWindow()
                    if image.isNull(): raise RuntimeError('Empty screenshot: '+page)
                    filename=f'{size}-{theme}-{page}.png'
                    if not image.save(str(args.output/filename)): raise RuntimeError('Cannot save screenshot')
                    report['screens'].append({'file':filename,'page':page,'theme':theme,'requested':[width,height],'actual':[root.width(),root.height()],'pixels':[image.width(),image.height()],'dpr':root.devicePixelRatio()})
        root.close();del current;del root;del engine
        app.processEvents()
        store.close()
    qInstallMessageHandler(old)
    report['geometry_ok']=all(s['actual']==s['requested'] and all(abs(s['pixels'][i]-s['actual'][i]*s['dpr'])<=2 for i in (0,1)) for s in report['screens'])
    report['ok']=not warnings and report['geometry_ok'] and len(report['screens'])==len(args.sizes.split(','))*12
    (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'ok':report['ok'],'screens':len(report['screens']),'warnings':warnings},ensure_ascii=False))
    return 0 if report['ok'] else 1


if __name__=='__main__': raise SystemExit(main())
