"""uiautomator dökümünde metni geçen ilk öğenin merkezini yazdırır.
Kullanım: python3 ui_find.py ui.xml "MİSAFİR OYNA" ["İKİNCİ ADAY" ...]
Flutter yazıları erişilebilirlik ağacında content-desc / text olarak görünür."""
import re, sys, xml.etree.ElementTree as ET

def norm(s):
    return (s or '').replace('\n', ' ').casefold()

try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(1)
for want in sys.argv[2:]:
    w = norm(want)
    best = None
    for n in root.iter('node'):
        label = norm(n.get('content-desc')) + ' ' + norm(n.get('text'))
        if w in label:
            m = re.findall(r'\d+', n.get('bounds', ''))
            if len(m) == 4:
                x0, y0, x1, y1 = map(int, m)
                area = (x1 - x0) * (y1 - y0)
                if area > 0 and (best is None or area < best[0]):
                    best = (area, (x0 + x1) // 2, (y0 + y1) // 2)
    if best:
        print(best[1], best[2])
        sys.exit(0)
sys.exit(1)
