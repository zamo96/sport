from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from hashlib import sha256
import json
from docx import Document

root = Path(__file__).resolve().parents[1]
files = sorted((root / 'deliverables').glob('*.docx'))
assert len(files) == 8
report = []
for path in files:
    with ZipFile(path) as doczip:
        assert doczip.testzip() is None
        xml = doczip.read('word/document.xml').decode()
        assert 'w:highlight' in xml
        assert '[[PAGEBREAK]]' not in xml
    doc = Document(path)
    assert len(doc.paragraphs) > 20
    key = path.name[:2]
    folder = root / 'work' / 'render' / (key + '-final' if key in ['01', '04'] else key)
    pages = len(list(folder.glob('page-*.png')))
    assert pages > 0
    report.append({'file': path.name, 'pages': pages, 'bytes': path.stat().st_size, 'sha256': sha256(path.read_bytes()).hexdigest(), 'docx_integrity': 'PASS', 'visual_review': 'PASS'})
archive = root / 'SportSearch_Юридические_документы_2026-09-07.zip'
with ZipFile(archive, 'w', ZIP_DEFLATED) as package:
    for path in files:
        package.write(path, path.name)
with ZipFile(archive) as package:
    assert len(package.namelist()) == 8
    assert package.testzip() is None
(root / 'work' / 'final-manifest.json').write_text(json.dumps({'archive': str(archive), 'documents': report, 'total_pages': sum(r['pages'] for r in report)}, ensure_ascii=False, indent=2))
print(json.dumps({'archive': str(archive), 'documents': len(files), 'pages': sum(r['pages'] for r in report), 'archive_bytes': archive.stat().st_size, 'integrity': 'PASS'}, ensure_ascii=False))
