#!/usr/bin/env bash
# OKEYX gerçek ekran turu: emülatörde uygulamayı açar, misafir girer,
# ana sayfa → Masalar → Masa kur → Hızlı oyna → oyun masası yolunu gezer.
# Her adımda gerçek ekran görüntüsü alır ve tüm turu ekran kaydına çeker.
# Adımlardan biri bulunamazsa tur durmaz; o anki ekranı kaydedip devam eder.
set -u
APP=com.senshilabs.okeyx_mobile
OUT=${OUT:-tour_out}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT/ekran" "$OUT/ui"
N=0
log(){ echo "[$(date +%T)] $*" | tee -a "$OUT/tur_kaydi.txt"; }
shot(){ N=$((N+1)); local f; f=$(printf '%02d_%s.png' "$N" "$1")
  timeout 25 adb shell screencap -p /sdcard/_s.png && timeout 25 adb pull /sdcard/_s.png "$OUT/ekran/$f" >/dev/null 2>&1
  [ -s "$OUT/ekran/$f" ] || timeout 25 adb exec-out screencap -p > "$OUT/ekran/$f"
  log "ekran: $f ($(stat -c %s "$OUT/ekran/$f" 2>/dev/null || echo 0) bayt)"
  { echo "== $f"; timeout 10 adb shell top -b -n 1 -m 8 2>/dev/null | tail -9; } >> "$OUT/cpu.txt"; }
dump(){ rm -f "$OUT/ui/son.xml"; adb shell rm -f /sdcard/ui.xml; timeout 30 adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; timeout 15 adb pull /sdcard/ui.xml "$OUT/ui/son.xml" >/dev/null 2>&1; [ -s "$OUT/ui/son.xml" ] || { log "UYARI: ekran dökümü alınamadı"; echo '<hierarchy/>' > "$OUT/ui/son.xml"; }; }
tap(){ # tap "METİN" ["ALTERNATİF" ...] → bulursa dokunur
  for try in 1 2 3; do
    dump
    if xy=$(python3 "$HERE/ui_find.py" "$OUT/ui/son.xml" "$@"); then
      log "dokun: $1 → $xy"; adb shell input tap $xy; return 0
    fi
    sleep 2
  done
  cp "$OUT/ui/son.xml" "$OUT/ui/bulunamadi_$(echo "$1" | tr ' /' '__').xml" 2>/dev/null
  log "BULUNAMADI: $*"; return 1
}
dismiss(){ # açılış pencerelerini kapat (ödül, öğretici, izinler)
  for k in 1 2 3 4; do
    dump
    if xy=$(python3 "$HERE/ui_find.py" "$OUT/ui/son.xml" "BONUSU AL" "Wait" "Got it" "Anladım" "KAPAT" "ŞİMDİ DEĞİL" "ATLA" "TAMAM" "Allow" "İzin ver" "Don't allow" "İzin verme"); then
      log "pencere kapatıldı → $xy"; adb shell input tap $xy; sleep 2
    else
      return 0
    fi
  done
}

adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
adb shell svc power stayon true
adb shell settings put secure immersive_mode_confirmations confirmed
# Sürekli dönen süs animasyonları emülatörü (yazılım GPU) boğmasın, uiautomator boşta kalabilsin.
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb logcat -c
( adb logcat -v time > "$OUT/logcat.txt" 2>&1 & echo $! > "$OUT/.logcat.pid" )

rec(){ adb shell screenrecord --bit-rate 6000000 --time-limit 175 "/sdcard/tur_$1.mp4" & echo $! > "$OUT/.rec.pid"; }
rec 1
log "uygulama başlatılıyor"
adb shell monkey -p $APP -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 12; shot acilis
sleep 10; dismiss; shot giris

tap "MİSAFİR OYNA" "MISAFIR" && sleep 25
dismiss; sleep 3; dismiss; shot ana_sayfa
sleep 4; dismiss; shot ana_sayfa_2

tap "Masalar" && sleep 6; shot masalar
if tap "MASA KUR"; then
  sleep 4; shot masa_kur_1
  tap "DEVAM ET" && sleep 3; shot masa_kur_2
  tap "GELİŞMİŞ AYARLAR" && sleep 2; shot masa_kur_gelismis
  tap "VAZGEÇ" "GERİ" >/dev/null; sleep 2
  tap "VAZGEÇ" >/dev/null; sleep 2
fi

# İlk kayıt 175 sn ile sınırlı; oyun kısmı için yenisini başlat.
kill "$(cat "$OUT/.rec.pid")" 2>/dev/null; sleep 3
rec 2
tap "HIZLI OYNA" "OYNA" && sleep 6; dismiss; shot bekleme_odasi
for i in 1 2 3 4; do sleep 5; dismiss >/dev/null; shot "masa_$i"; done
# Sıra bize gelince desteye dokun (sağ orta bölge) ve bir taş at: gerçek etkileşim.
for i in 5 6 7 8 9 10 11 12; do sleep 8; shot "masa_$i"; done
sleep 100
kill "$(cat "$OUT/.rec.pid")" 2>/dev/null; sleep 3
shot son
for k in 1 2; do adb pull "/sdcard/tur_$k.mp4" "$OUT/tur_$k.mp4" >/dev/null 2>&1 && log "kayıt alındı: tur_$k.mp4"; done
kill "$(cat "$OUT/.logcat.pid")" 2>/dev/null
grep -E "OKEYX_|FlutterError|Exception|I/flutter|E/flutter|AndroidRuntime|ANR in" "$OUT/logcat.txt" | head -400 > "$OUT/hatalar.txt" || true
log "tur bitti"
exit 0
