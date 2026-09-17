from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import subprocess, sys, json
ROOT=Path(__file__).resolve().parents[1]
RENDER='/Users/matvey/.codex/plugins/cache/openai-primary-runtime/documents/26.905.11957/skills/documents/render_docx.py'
manifest=json.loads((ROOT/'work/manifest.json').read_text())
def run(item):
    key=Path(item['source']).name[:2]
    dst=ROOT/'work/render'/key
    result=subprocess.run([sys.executable,RENDER,item['file'],'--output_dir',str(dst),'--emit_pdf'],capture_output=True,text=True)
    (ROOT/'work'/f'render-{key}.log').write_text(result.stdout+'\n'+result.stderr)
    return {'id':key,'code':result.returncode,'pages':len(list(dst.glob('page-*.png'))),'output':str(dst)}
with ThreadPoolExecutor(max_workers=2) as pool:
    futs=[pool.submit(run,i) for i in manifest]
    reports=[]
    for fut in as_completed(futs):
        r=fut.result();reports.append(r);print(json.dumps(r,ensure_ascii=False),flush=True)
(ROOT/'work/render-report.json').write_text(json.dumps(sorted(reports,key=lambda r:r['id']),ensure_ascii=False,indent=2))
if any(r['code'] for r in reports):sys.exit(1)
