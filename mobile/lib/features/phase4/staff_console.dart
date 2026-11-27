import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../lobby/lobby_api.dart';
import 'staff_market_tab.dart';

class StaffConsoleDialog extends StatefulWidget{final LobbyApiClient api;const StaffConsoleDialog({super.key,required this.api});@override State<StaffConsoleDialog>createState()=>_StaffConsoleDialogState();}
class _StaffConsoleDialogState extends State<StaffConsoleDialog>{
  final search=TextEditingController(),eventTitle=TextEditingController(),eventSubtitle=TextEditingController();bool loading=true,busy=false;int tab=0;Map<String,dynamic>snap={};List<Map<String,dynamic>>players=[];double slot=94,horse=90,circus=90,drop=91,eventXp=1.25;int eventReward=25000,eventBonus=10;
  @override void initState(){super.initState();unawaited(load());}@override void dispose(){search.dispose();eventTitle.dispose();eventSubtitle.dispose();super.dispose();}
  Future<void>load()async{try{final x=await widget.api.staffSnapshot();final initialPlayers=await widget.api.staffPlayers('');if(!mounted)return;final games=_map(_map(x['config'])['side_games']);setState((){snap=x;players=initialPlayers;slot=_double(_map(games['slot'])['rtp_percent'],94);horse=_double(_map(games['horse'])['rtp_percent'],90);circus=_double(_map(games['circus'])['rtp_percent'],90);drop=_double(_map(games['drop'])['rtp_percent'],91);loading=false;});}catch(e){if(mounted)setState(()=>loading=false);toast('Yönetim paneli açılamadı.');}}
  Future<void>run(Future<void>Function()f)async{if(busy)return;setState(()=>busy=true);try{await f();}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext c){final staff=_map(snap['staff']),perm=_list(staff['permissions']).map((x)=>'$x').toSet();return Dialog(backgroundColor:const Color(0xFF0E0A26),insetPadding:const EdgeInsets.symmetric(horizontal:12,vertical:8),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22),side:BorderSide(color:OkeyXColors.gold.withValues(alpha:.3))),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1080,maxHeight:640),child:Stack(children:[Padding(padding:const EdgeInsets.all(12),child:Column(children:[Row(children:[const Icon(Icons.admin_panel_settings_rounded,color:OkeyXColors.gold),const SizedBox(width:7),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('OKEYX OPERASYON MERKEZİ',style:TextStyle(fontSize:13,fontWeight:FontWeight.w900)),Text('${staff['role']??'-'} • ${perm.length} yetki',style:const TextStyle(fontSize:7,color:Colors.white54))]),const Spacer(),IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded)),IconButton(onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close_rounded))]),const SizedBox(height:5),Row(children:[_tab(0,Icons.dashboard_rounded,'GENEL'),const SizedBox(width:5),_tab(1,Icons.manage_accounts_rounded,'OYUNCULAR'),const SizedBox(width:5),_tab(2,Icons.auto_graph_rounded,'RTP / ETKİNLİK'),const SizedBox(width:5),_tab(3,Icons.history_rounded,'KAYITLAR'),const SizedBox(width:5),_tab(4,Icons.storefront_rounded,'MARKET / EKONOMİ')]),const SizedBox(height:8),Expanded(child:switch(tab){0=>overview(),1=>playersTab(),2=>liveOps(perm),4=>StaffMarketTab(api:widget.api),_=>audit()})])),if(loading||busy)const Positioned.fill(child:ColoredBox(color:Color(0x66000000),child:Center(child:CircularProgressIndicator()))) ])));}
  Widget _tab(int i,IconData icon,String text)=>Expanded(child:Material(color:tab==i?OkeyXColors.mint.withValues(alpha:.12):const Color(0x77130C37),borderRadius:BorderRadius.circular(10),child:InkWell(onTap:()=>setState(()=>tab=i),child:SizedBox(height:36,child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:14,color:tab==i?OkeyXColors.mint:Colors.white38),const SizedBox(width:4),Text(text,style:TextStyle(fontSize:7,fontWeight:FontWeight.w900,color:tab==i?Colors.white:Colors.white54))])))));
  Widget overview(){final m=_map(snap['metrics']);return ListView(children:[Wrap(spacing:7,runSpacing:7,children:[stat('HESAPLAR',_int(m['accounts']),Icons.groups_rounded),stat('VIP',_int(m['vip_users']),Icons.workspace_premium_rounded),stat('SATIN ALMA',_int(m['verified_receipts']),Icons.receipt_rounded),stat('İADE',_int(m['refunded_receipts']),Icons.undo_rounded),stat('BAN',_int(m['active_bans']),Icons.gavel_rounded),stat('SUSTURMA',_int(m['active_mutes']),Icons.volume_off_rounded),stat('RNG OLAYI',_int(m['rng_events']),Icons.casino_rounded)]),const SizedBox(height:8),panel(const Text('Bu panelden yapılan cüzdan, moderasyon ve RTP değişiklikleri denetim kaydına yazılır. VIP hiçbir oyun kuralı avantajı vermez.',style:TextStyle(fontSize:8,color:Colors.white54))) ]);}
  Widget playersTab()=>Column(children:[Row(children:[Expanded(child:TextField(controller:search,decoration:const InputDecoration(hintText:'Oyuncu adı veya ID',prefixIcon:Icon(Icons.search_rounded),isDense:true),onSubmitted:(_)=>find())),const SizedBox(width:6),FilledButton(onPressed:find,child:const Text('ARA'))]),const SizedBox(height:7),Expanded(child:players.isEmpty?const Center(child:Text('Oyuncu ara; ban, susturma ve cüzdan işlemleri burada yapılır.',style:TextStyle(fontSize:8,color:Colors.white38))):ListView(children:[for(final p in players)playerRow(p)]))]);
  Future<void>find()=>run(()async{final x=await widget.api.staffPlayers(search.text.trim());if(mounted)setState(()=>players=x);});
  Widget playerRow(Map<String,dynamic>p){final sanctions=_list(p['sanctions']).map(_map).toList(),banned=sanctions.any((x)=>x['type']=='ban'),muted=sanctions.any((x)=>x['type']=='mute');return Container(margin:const EdgeInsets.only(bottom:5),padding:const EdgeInsets.all(7),decoration:BoxDecoration(color:const Color(0x99130C35),borderRadius:BorderRadius.circular(12),border:Border.all(color:banned?Colors.redAccent.withValues(alpha:.3):Colors.white10)),child:Row(children:[CircleAvatar(radius:16,child:Text('${p['name']??'O'}'.substring(0,1))),const SizedBox(width:7),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${p['name']} • LV ${_int(p['level'])}${_int(p['vip_level'])>0?' • VIP ${_int(p['vip_level'])}':''}',style:const TextStyle(fontSize:8.5,fontWeight:FontWeight.w900)),Text('${p['public_id']??''} • ${_compact(_int(p['coins']))} altın • ${_int(p['diamonds'])} elmas${banned?' • BANLI':''}${muted?' • SUSTURULMUŞ':''}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:6.5,color:Colors.white54))])),PopupMenuButton<String>(onSelected:(v)=>moderate(p,v),itemBuilder:(_)=>[PopupMenuItem(value:muted?'unmute':'mute30',child:Text(muted?'Susturmayı kaldır':'30 dk sustur')),PopupMenuItem(value:banned?'unban':'ban60',child:Text(banned?'Banı kaldır':'60 dk ban')),if(!banned)const PopupMenuItem(value:'ban0',child:Text('Kalıcı ban')),const PopupMenuDivider(),const PopupMenuItem(value:'chatlock',child:Text('Sohbeti kapat')),const PopupMenuItem(value:'giftlock',child:Text('Hediye göndermeyi kapat'))]),IconButton.filledTonal(onPressed:()=>walletDialog(p),icon:const Icon(Icons.account_balance_wallet_rounded,size:16))]));}
  Future<void>moderate(Map<String,dynamic>p,String a)=>run(()async{String t='unban';int d=0;if(a=='mute30'){t='mute';d=30;}else if(a=='ban60'){t='ban';d=60;}else if(a=='ban0'){t='ban';}else if(a=='unmute'){t='unmute';}else if(a=='chatlock'){t='chat_lock';}else if(a=='giftlock'){t='gift_lock';}final x=await widget.api.staffSanction('${p['id']}',t,durationMinutes:d,reason:'Oyun içi moderasyon');toast(x['ok']==true?'İşlem uygulandı.':'İşlem başarısız');await find();await load();});
  Future<void> walletDialog(Map<String, dynamic> p) async {
    String cur = 'coins';
    final amount = TextEditingController();
    final reason = TextEditingController(text: 'Destek / düzeltme');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          final parsed = _parseAdminAmount(amount.text);
          final size = MediaQuery.sizeOf(dialogContext);
          return Dialog(
            backgroundColor: const Color(0xFF120B32),
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: OkeyXColors.mint.withValues(alpha: .24)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (size.width - 28).clamp(300.0, 520.0).toDouble(), maxHeight: (size.height - 20).clamp(240.0, 620.0).toDouble()),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, size.height < 430 ? 10 : 16, 18, size.height < 430 ? 10 : 14),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 38,height:38,decoration:BoxDecoration(shape:BoxShape.circle,color:OkeyXColors.gold.withValues(alpha:.12)),child:const Icon(Icons.account_balance_wallet_rounded,color:OkeyXColors.gold,size:20)),
                    const SizedBox(width:9),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${p['name']} • Cüzdan',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900)),Text('${p['public_id']??''}',style:const TextStyle(fontSize:7,color:Colors.white54))])),
                    IconButton(onPressed:()=>Navigator.pop(dialogContext,false),icon:const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height:10),
                  SizedBox(width: double.infinity, child: SegmentedButton<String>(
                    segments: const [ButtonSegment(value:'coins',icon:Icon(Icons.monetization_on_rounded,size:16),label:Text('Altın')),ButtonSegment(value:'diamonds',icon:Icon(Icons.diamond_rounded,size:16),label:Text('Elmas'))],
                    selected:{cur},onSelectionChanged:(v)=>setLocal(()=>cur=v.first),
                  )),
                  const SizedBox(height:10),
                  TextField(
                    controller:amount,onChanged:(_)=>setLocal((){}),keyboardType:TextInputType.text,
                    decoration:InputDecoration(labelText:'Miktar (+/-)',hintText:'2b • 2000m • 500k • -250000',helperMaxLines:2,helperText:amount.text.trim().isEmpty?'K / M / B kısaltmaları ve tam sayılar desteklenir.':'Uygulanacak: ${_formatExact(parsed)} ${cur=='coins'?'altın':'elmas'}'),
                  ),
                  const SizedBox(height:8),
                  TextField(controller:reason,maxLength:120,minLines:1,maxLines:2,decoration:const InputDecoration(labelText:'Neden',counterText:'',hintText:'Destek / düzeltme')),
                  const SizedBox(height:9),
                  Container(
                    padding:const EdgeInsets.all(9),
                    decoration:BoxDecoration(color:OkeyXColors.gold.withValues(alpha:.07),borderRadius:BorderRadius.circular(12),border:Border.all(color:OkeyXColors.gold.withValues(alpha:.18))),
                    child:const Row(children:[Icon(Icons.notifications_active_rounded,size:15,color:OkeyXColors.gold),SizedBox(width:7),Expanded(child:Text('İşlem anında uygulanır ve oyuncuya miktar + neden içeren yönetim bildirimi gider.',style:TextStyle(fontSize:7,color:Colors.white60)))]),
                  ),
                  const SizedBox(height:12),
                  Row(children:[
                    Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('VAZGEÇ'))),
                    const SizedBox(width:8),
                    Expanded(flex:2,child:FilledButton.icon(onPressed:amount.text.trim().isEmpty?null:()=>Navigator.pop(dialogContext,true),icon:const Icon(Icons.done_rounded,size:17),label:const FittedBox(fit:BoxFit.scaleDown,child:Text('UYGULA',style:TextStyle(fontWeight:FontWeight.w900))))),
                  ]),
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (ok == true) {
      await run(() async {
        final v = _parseAdminAmount(amount.text);
        if (v == 0 && amount.text.trim().replaceAll(RegExp(r'[0.,\s]'), '').isNotEmpty) {
          toast('Miktarı okuyamadım. 2b, 2000m veya tam sayı kullan.');
          return;
        }
        final x = await widget.api.staffWallet('${p['id']}', cur, v, reason.text);
        toast(x['ok'] == true ? '${_formatExact(_int(x['actual']))} ${cur == 'coins' ? 'altın' : 'elmas'} uygulandı.' : 'İşlem başarısız');
        await find();
        await load();
      });
    }
    amount.dispose();
    reason.dispose();
  }

  Widget liveOps(Set<String> perm) {
    final events = _list(snap['live_events']).map(_map).toList();
    return ListView(children: [
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_graph_rounded, size: 17, color: OkeyXColors.gold),
          const SizedBox(width: 6),
          const Text('YAN OYUN RTP', style: TextStyle(fontWeight: FontWeight.w900, color: OkeyXColors.gold)),
          const Spacer(),
          const Text('Yeni turlara uygulanır', style: TextStyle(fontSize: 6.5, color: Colors.white38)),
        ]),
        rtp('5×9 Slot', slot, (v) => setState(() => slot = v)),
        rtp('Hipodrom', horse, (v) => setState(() => horse = v)),
        rtp('Sirk Işıkları', circus, (v) => setState(() => circus = v)),
        rtp('Okey Drop', drop, (v) => setState(() => drop = v)),
        const SizedBox(height: 5),
        TextField(controller: eventTitle, decoration: const InputDecoration(labelText: 'RTP değişikliği / etkinlik adı', isDense: true)),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: perm.contains('rtp') ? applyRtp : null, icon: const Icon(Icons.publish_rounded), label: const Text('RTP SÜRÜMÜNÜ YAYINLA'))),
      ])),
      const SizedBox(height: 8),
      panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Row(children:[Icon(Icons.redeem_rounded,size:17,color:OkeyXColors.mint),SizedBox(width:6),Text('ÇARK & SANDIK AYARLARI',style:TextStyle(fontWeight:FontWeight.w900,color:OkeyXColors.mint)),Spacer(),Text('Ödül havuzu sunucudan yönetilir',style:TextStyle(fontSize:6,color:Colors.white38))]),
        const SizedBox(height:6),
        Row(children:[Expanded(child:FilledButton.tonalIcon(onPressed:()=>_editRewardConfig('wheel'),icon:const Icon(Icons.casino_rounded,size:15),label:const Text('ÇARK İÇERİĞİ'))),const SizedBox(width:6),Expanded(child:FilledButton.tonalIcon(onPressed:()=>_editRewardConfig('chest'),icon:const Icon(Icons.inventory_2_rounded,size:15),label:const Text('SANDIK İÇERİĞİ')))]),
      ])),
      const SizedBox(height: 8),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.campaign_rounded, size: 17, color: OkeyXColors.mint),
          const SizedBox(width: 6),
          const Expanded(child: Text('CANLI ETKİNLİKLER', style: TextStyle(fontWeight: FontWeight.w900))),
          Text('${events.length} kayıt', style: const TextStyle(fontSize: 6.5, color: Colors.white38)),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: TextField(controller: eventTitle, decoration: const InputDecoration(labelText: 'Etkinlik adı', hintText: 'Altın Gecesi', isDense: true))),
          const SizedBox(width: 6),
          Expanded(child: TextField(controller: eventSubtitle, decoration: const InputDecoration(labelText: 'Kısa açıklama', hintText: 'Ekstra ödül + bonus', isDense: true))),
          const SizedBox(width: 6),
          FilledButton.icon(onPressed: perm.contains('events') ? _createLiveEvent : null, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('24 SAAT YAYINLA')),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: _eventSetting('KATILIM ÖDÜLÜ', '${_compact(eventReward)} altın', Slider(value:eventReward.toDouble(),min:5000,max:250000,divisions:49,onChanged:(v)=>setState(()=>eventReward=v.round())))),
          const SizedBox(width:6),
          Expanded(child: _eventSetting('ŞANS BONUSU', '+%$eventBonus', Slider(value:eventBonus.toDouble(),min:0,max:50,divisions:10,onChanged:(v)=>setState(()=>eventBonus=v.round())))),
          const SizedBox(width:6),
          Expanded(child: _eventSetting('XP ÇARPANI', '×${eventXp.toStringAsFixed(2)}', Slider(value:eventXp,min:1,max:2,divisions:20,onChanged:(v)=>setState(()=>eventXp=v)))),
        ]),
        const SizedBox(height: 7),
        if (events.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 9), child: Text('Aktif veya planlı etkinlik yok.', style: TextStyle(fontSize: 8, color: Colors.white38))),
        for (final e in events)
          Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: e['enabled'] == true ? OkeyXColors.mint.withValues(alpha: .20) : Colors.white10)),
            child: Row(children: [
              Icon(e['enabled'] == true ? Icons.radio_button_checked_rounded : Icons.pause_circle_outline_rounded, size: 14, color: e['enabled'] == true ? OkeyXColors.mint : Colors.white38),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['title']}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900)),
                Text('${e['subtitle'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 6.3, color: Color(0x73FFFFFF))),
              ])),
              if (perm.contains('events')) IconButton(onPressed: () => _deleteLiveEvent('${e['id']}'), icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent)),
            ]),
          ),
      ])),
    ]);
  }

  Future<void> _editRewardConfig(String kind) async {
    final cfg=_map(snap['reward_config']);final current=_map(cfg[kind]);
    final limit=TextEditingController(text:'${_int(current['daily_limit'])==0?(kind=='wheel'?1:5):_int(current['daily_limit'])}');
    final rows=_list(current[kind=='wheel'?'segments':'rewards']).map(_map).toList();
    final rewards=TextEditingController(text:rows.map((x)=>'${_int(x['reward'])}').join(', '));
    final weights=TextEditingController(text:rows.map((x)=>'${_int(x['weight'])}').join(', '));
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(kind=='wheel'?'Çark içeriği':'Sandık içeriği'),content:SizedBox(width:460,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:limit,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Günlük maksimum kullanım')),const SizedBox(height:6),TextField(controller:rewards,decoration:const InputDecoration(labelText:'Ödüller (virgülle)',hintText:'500, 1000, 2500, 5000')),const SizedBox(height:6),TextField(controller:weights,decoration:const InputDecoration(labelText:'Ağırlıklar (aynı sırada)',hintText:'30, 25, 20, 15')),const SizedBox(height:6),const Text('Ağırlık büyüdükçe ödül daha sık gelir. Böylece RTP hissini içerik ve oran üzerinden yönetebilirsin.',style:TextStyle(fontSize:7,color:Colors.white54))])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('VAZGEÇ')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('YAYINLA'))]));
    if(ok==true)await run(()async{final rv=rewards.text.split(',').map((x)=>_parseAdminAmount(x)).where((x)=>x>=0).toList();final wt=weights.text.split(',').map((x)=>int.tryParse(x.trim())??1).toList();final list=<Map<String,dynamic>>[];for(var i=0;i<rv.length;i++)list.add({'reward':rv[i],'weight':i<wt.length?wt[i].clamp(1,10000):1});final out=await widget.api.staffRewardConfig({kind:{'daily_limit':int.tryParse(limit.text)??(kind=='wheel'?1:5),kind=='wheel'?'segments':'rewards':list}});toast(out['ok']==true?'Ödül sistemi güncellendi.':'Güncellenemedi.');await load();});
    limit.dispose();rewards.dispose();weights.dispose();
  }

  Future<void> _createLiveEvent() => run(() async {
    final title = eventTitle.text.trim();
    if (title.isEmpty) { toast('Etkinlik adı gerekli.'); return; }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = await widget.api.staffUpsertEvent(title: title, subtitle: eventSubtitle.text.trim(), startsAt: now, endsAt: now + 86400, enabled: true, config: {'reward_coins':eventReward,'side_game_bonus_percent':eventBonus,'xp_multiplier':eventXp});
    toast(out['ok'] == true ? 'Etkinlik 24 saat için yayınlandı.' : 'Etkinlik yayınlanamadı.');
    if (out['ok'] == true) { eventTitle.clear(); eventSubtitle.clear(); }
    await load();
  });

  Future<void> _deleteLiveEvent(String id) => run(() async {
    final out = await widget.api.staffDeleteEvent(id);
    toast(out['ok'] == true ? 'Etkinlik kaldırıldı.' : 'Etkinlik kaldırılamadı.');
    await load();
  });

  Widget _eventSetting(String title,String value,Widget slider)=>Container(padding:const EdgeInsets.fromLTRB(8,6,8,2),decoration:BoxDecoration(color:Colors.black26,borderRadius:BorderRadius.circular(10),border:Border.all(color:Colors.white10)),child:Column(children:[Row(children:[Expanded(child:Text(title,style:const TextStyle(fontSize:5.8,color:Colors.white38,fontWeight:FontWeight.w900))),Text(value,style:const TextStyle(fontSize:7,color:OkeyXColors.gold,fontWeight:FontWeight.w900))]),SizedBox(height:24,child:slider)]));
  Widget rtp(String n,double v,ValueChanged<double>f)=>Row(children:[SizedBox(width:100,child:Text(n,style:const TextStyle(fontSize:7))),Expanded(child:Slider(value:v.clamp(85.0,97.0).toDouble(),min:85,max:97,divisions:24,onChanged:f)),SizedBox(width:45,child:Text('%${v.toStringAsFixed(1)}',style:const TextStyle(fontSize:7,color:OkeyXColors.gold)))]);
  Future<void>applyRtp()=>run(()async{await widget.api.staffRtp('slot',slot,title:eventTitle.text);await widget.api.staffRtp('horse',horse,title:eventTitle.text);await widget.api.staffRtp('circus',circus,title:eventTitle.text);await widget.api.staffRtp('drop',drop,title:eventTitle.text);toast('Yeni RTP sürümü yayınlandı.');await load();});
  Widget audit(){final rows=_list(snap['audit']).map(_map).toList().reversed.take(80);return ListView(children:[for(final r in rows)Container(margin:const EdgeInsets.only(bottom:4),padding:const EdgeInsets.all(7),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.025),borderRadius:BorderRadius.circular(9)),child:Row(children:[SizedBox(width:100,child:Text('${r['action']}',style:const TextStyle(fontSize:7,fontWeight:FontWeight.w900))),Expanded(child:Text('${r['actor']??'-'} • ${r['player_id']??r['game']??''}',style:const TextStyle(fontSize:6.8,color:Colors.white54))),Text('${r['created_at']??''}',style:const TextStyle(fontSize:5.5,color:Colors.white30))]))]);}
  Widget stat(String n,int v,IconData i)=>SizedBox(width:210,child:panel(Row(children:[Icon(i,color:OkeyXColors.mint,size:19),const SizedBox(width:7),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(n,style:const TextStyle(fontSize:6,color:Colors.white38)),Text(_compact(v),style:const TextStyle(fontSize:13,fontWeight:FontWeight.w900))])])));Widget panel(Widget w)=>Container(padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:const Color(0x99120B33),borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.white10)),child:w);void toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
}
int _parseAdminAmount(String raw){var s=raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'),'');if(s.isEmpty)return 0;var mult=1.0;var suffix=false;if(s.endsWith('b')||s.endsWith('mr')){mult=1000000000;s=s.endsWith('mr')?s.substring(0,s.length-2):s.substring(0,s.length-1);suffix=true;}else if(s.endsWith('m')||s.endsWith('mn')){mult=1000000;s=s.endsWith('mn')?s.substring(0,s.length-2):s.substring(0,s.length-1);suffix=true;}else if(s.endsWith('k')||s.endsWith('bin')){mult=1000;s=s.endsWith('bin')?s.substring(0,s.length-3):s.substring(0,s.length-1);suffix=true;}if(suffix){final commas=','.allMatches(s).length,dots='.'.allMatches(s).length;if(commas+dots==1){final sep=commas==1?',':'.';final tail=s.split(sep).last;if(tail.length<=3)s=s.replaceAll(',','.');else s=s.replaceAll(sep,'');}else{s=s.replaceAll('.','').replaceAll(',','');}}else{s=s.replaceAll('.','').replaceAll(',','');}final n=double.tryParse(s);if(n==null||!n.isFinite)return 0;final value=(n*mult).round();return value.clamp(-9000000000000,9000000000000).toInt();}
int _int(dynamic v)=>v is num?v.toInt():int.tryParse('$v')??0;double _double(dynamic v,double d)=>v is num?v.toDouble():double.tryParse('$v')??d;Map<String,dynamic>_map(dynamic v)=>v is Map?Map<String,dynamic>.from(v):{};List<dynamic>_list(dynamic v)=>v is List?v:const [];String _compact(int v){if(v.abs()>=1000000000)return '${(v/1000000000).toStringAsFixed(2).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'')}B';if(v.abs()>=1000000)return '${(v/1000000).toStringAsFixed(2).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'')}M';if(v.abs()>=1000)return '${(v/1000).toStringAsFixed(1).replaceAll('.0','')}K';return '$v';}
String _formatExact(int v)=>v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>'.');
