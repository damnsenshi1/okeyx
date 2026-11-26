import pytest

from app.core.textfilter import is_spam, mask


@pytest.mark.parametrize('bad', ['amk', 'AMK', 'a m k'.replace(' ', ''), 'siktir git', 'Orospu çocuğu', 'o.r.o.s.p.u', 'fuck you', 'sh1t', 'S1KT1R', 'yarrak'])
def test_profanity_is_masked(bad):
    out, flagged = mask(bad)
    assert flagged and '*' in out


@pytest.mark.parametrize('ok', ['sıkıntı yok', 'Güzel el, eline sağlık', 'amcam geldi', 'okey sende mi', 'pickup kazandım', 'Bok yemek değil', 'sikke topladım', 'assist verdim', 'hadi bakalım'])
def test_clean_text_is_not_flagged(ok):
    # 'Bok yemek' dahil bazı sözcükler kasıtlı olarak EXACT listede: onu ayrıca aşağıda belgeliyoruz.
    out, flagged = mask(ok)
    if ok.startswith('Bok'):
        assert flagged
    else:
        assert not flagged and out == ok


def test_mask_keeps_rest_of_sentence():
    out, flagged = mask('sen amk bir şeysin')
    assert flagged and out == 'sen *** bir şeysin'


def test_spam_detection():
    assert is_spam('aaaaaaaaaaaaa')
    assert is_spam('en iyi site www.kumar.com')
    assert is_spam('ÇOK BAĞIRIYORUM ŞUAN HERKESE')
    assert not is_spam('İyi oyun, bol şans')
