"""Held-out category retrieval benchmark. NOT exact-product or multi-view accuracy.

python -m backend.tools.evaluate_photos --output docs/photo_benchmark.json
Run after startup/indexing, with the same DATABASE_URL and SEARCH_BACKEND.
"""
import argparse, json, hashlib
from collections import defaultdict
from ..app.config import ROOT, MEDIA, SEARCH_BACKEND
from ..app.database import SessionLocal
from ..app.search import nearest_images
from ..app.ml_index import nearest_ml_images
from ..app.models import ProductImage, Product


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',default='docs/photo_benchmark.json')
    args=parser.parse_args()
    rows=json.loads((ROOT/'demo_data/photo_catalog.json').read_text())
    hashes={r['sha256'] for r in rows if r['split']=='catalog'}
    queries=[r for r in rows if r['split']=='query']
    results=[]
    search=nearest_ml_images if SEARCH_BACKEND=='clip' else nearest_images
    with SessionLocal() as session:
        for row in queries:
            data=(ROOT/'demo_data/queries'/row['filename']).read_bytes()
            assert hashlib.sha256(data).hexdigest() not in hashes, 'Query duplicates catalog image'
            ranked=search(session,data,limit=1000)
            hits=[]; seen=set()
            for iid,score in ranked:
                image=session.get(ProductImage,iid)
                if image.product_id in seen: continue
                seen.add(image.product_id)
                p=session.get(Product,image.product_id)
                hits.append({'id':p.id,'category':p.category,'score':score})
                if len(hits)==5: break
            if not hits: raise RuntimeError('Empty index: start the server/index first')
            correct=[h['category']==row['category'] for h in hits]
            results.append({'query':row['filename'],'category':row['category'],
                            'top1':bool(correct[0]),'hit5':any(correct),
                            'precision5':sum(correct)/5,'results':hits})
    n=len(results)
    report={'engine':SEARCH_BACKEND,'queries':n,'catalog_photos':240,
            'scope':'Held-out category retrieval; not exact identity, not independently verified multi-view pairs. No category filter or threshold used.',
            'category_top1':sum(r['top1'] for r in results)/n,
            'category_hit5':sum(r['hit5'] for r in results)/n,
            'category_precision5':sum(r['precision5'] for r in results)/n,
            'details':results}
    path=ROOT/args.output;path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='details'},ensure_ascii=False,indent=2))


if __name__=='__main__': main()
