"""Hazır sesli mesajları Piper TTS (Türkçe) ile üretir ve komik/doğal efekt ekler.
CI'da çalışır (internet orada açık). Çıktı: out/<ad>.wav + MODEL_CARD'lar."""
import json, subprocess, sys, wave, os, urllib.request
from pathlib import Path
OUT=Path('out');OUT.mkdir(exist_ok=True)
BASE='https://huggingface.co/rhasspy/piper-voices/resolve/main/tr/tr_TR'
VOICES=['fahrettin/medium/tr_TR-fahrettin-medium','fettah/medium/tr_TR-fettah-medium','dfki/medium/tr_TR-dfki-medium']
have=[]
for v in VOICES:
    name=v.split('/')[-1]
    try:
        for ext in ('.onnx','.onnx.json'):
            urllib.request.urlretrieve(f'{BASE}/{v}{ext}',f'{name}{ext}')
        d=v.rsplit('/',1)[0]
        urllib.request.urlretrieve(f'{BASE}/{d}/MODEL_CARD',OUT/f'MODEL_CARD_{name}.txt')
        have.append(name);print('voice ok',name)
    except Exception as e:print('voice missing',name,e)
if not have:sys.exit('no voice')
main=have[0]
for i,line in enumerate(Path(sys.argv[1]).read_text(encoding='utf-8').strip().splitlines()):
    key,text,ls,pitch=line.split('|');ls=float(ls);pitch=float(pitch)
    voice=have[i%len(have)] if len(have)>1 and key in ('voice_luck','voice_eline','voice_cift') else main
    raw=f'raw_{key}.wav'
    subprocess.run(['piper','--model',f'{voice}.onnx','--output_file',raw,'--length_scale',str(ls),'--noise_scale','0.75','--noise_w','0.9'],input=text.encode('utf-8'),check=True)
    sr=wave.open(raw).getframerate()
    # Komik ve sıcak: hafif perde oynatma, kahvehane yankısı, ses yüksekliği eşitleme.
    af=(f"asetrate={int(sr*pitch)},aresample=44100,atempo={1/pitch:.4f},"
        "highpass=f=90,acompressor=threshold=-18dB:ratio=3:attack=5:release=80,"
        "aecho=0.8:0.5:35|70:0.18|0.10,loudnorm=I=-16:TP=-1.5:LRA=7")
    subprocess.run(['ffmpeg','-loglevel','error','-y','-i',raw,'-af',af,'-ac','1','-ar','44100',str(OUT/f'{key}.wav')],check=True)
    print('made',key,voice)
