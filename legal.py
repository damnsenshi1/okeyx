"""Mağaza zorunlu sayfaları: gizlilik politikası ve hesap silme talimatı (herkese açık)."""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter()

_STYLE = ("body{font-family:system-ui,sans-serif;max-width:720px;margin:32px auto;padding:0 16px;"
          "line-height:1.6;color:#10211e}h1{color:#0a6f66}code{background:#eef5f3;padding:2px 5px;border-radius:4px}")


def _page(title: str, body: str) -> HTMLResponse:
    return HTMLResponse(f"<!doctype html><html lang='tr'><meta charset='utf-8'>"
                        f"<meta name='viewport' content='width=device-width,initial-scale=1'>"
                        f"<title>{title}</title><style>{_STYLE}</style><body>{body}</body></html>")


@router.get('/privacy', response_class=HTMLResponse)
def privacy():
    return _page('OkeyX Gizlilik Politikası', """
<h1>OkeyX Gizlilik Politikası</h1>
<p>OkeyX, 101 Okey oyunudur. Oyun içi altın, elmas ve jetonların nakit değeri yoktur; para çekilemez, gerçek para ödülü verilmez.</p>
<h2>Topladığımız veriler</h2>
<ul><li>Hesap: takma ad, oturum açma kimliği (Google/e-posta), avatar tercihi.</li>
<li>Oyun verisi: bakiye, istatistik, arkadaşlar, kulüp, sıralama, mesajlar.</li>
<li>Teknik: hata kayıtları ve IP (hız sınırı ve kötüye kullanım önleme için, kısa süre).</li>
<li>Reklam: Google AdMob reklam kimliği (reklamlar için).</li></ul>
<h2>Kullanım amacı</h2><p>Oyunu çalıştırmak, hesabını korumak, hile ve kötüye kullanımı önlemek.</p>
<h2>Saklama</h2><p>Veriler AB'deki (Frankfurt) sunucularda saklanır. Hesabını silersen verilerin kaldırılır.</p>
<h2>Haklarınız</h2><p>Verilerinizin silinmesini <a href='/delete-account'>buradan</a> talep edebilirsiniz.</p>
""")


@router.get('/delete-account', response_class=HTMLResponse)
def delete_account_page():
    return _page('OkeyX Hesap Silme', """
<h1>Hesap ve veri silme</h1>
<p>Uygulama içinden: <b>Ayarlar → Hesabı sil</b>. Hesabın, bakiyen, arkadaş bağlantıların ve profilin kalıcı olarak silinir; geri alınamaz.</p>
<p>Uygulamaya erişemiyorsan, hesap kimliğinle destek adresimize yaz; kimliğini doğruladıktan sonra silinir.</p>
""")


@router.get('/terms', response_class=HTMLResponse)
def terms():
    return _page('OkeyX Kullanım Şartları', """
<h1>OkeyX Kullanım Şartları</h1>
<ul>
<li>OkeyX bir eğlence oyunudur. Oyun içi altın, elmas ve jetonların nakit değeri yoktur; para çekilemez, nakit ödül yoktur.</li>
<li>Hile, bot kullanımı, hesap/altın satışı, başkasının hesabını kullanma ve istismar yasaktır; hesap kapatılabilir.</li>
<li>Sohbette hakaret, spam ve bağlantı paylaşımı yasaktır. Şikâyet edilen hesaplar incelenir.</li>
<li>Satın alımlar Google Play kurallarına tabidir; iade talepleri Google Play üzerinden yapılır.</li>
<li>Şans Salonu yalnız oyunla kazanılan jetonla oynanır, satın alınamaz.</li>
<li>Hizmet "olduğu gibi" sunulur; bakım ve güncellemeler için kesinti olabilir.</li>
<li>Gizlilik için <a href='/privacy'>Gizlilik Politikası</a>, silme için <a href='/delete-account'>Hesap Silme</a> sayfalarına bakın.</li>
</ul>
""")
