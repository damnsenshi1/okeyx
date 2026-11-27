import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';
import '../lobby/lobby_api.dart';
import 'ad_service.dart';
import 'commerce_service.dart';

class Phase4Screen extends StatefulWidget {
  final LobbyApiClient api;
  final bool compact;
  final VoidCallback? onWalletChanged;
  final bool soundEnabled;

  const Phase4Screen({
    super.key,
    required this.api,
    required this.compact,
    this.onWalletChanged,
    this.soundEnabled = true,
  });

  @override
  State<Phase4Screen> createState() => _Phase4ScreenState();
}

class _Phase4ScreenState extends State<Phase4Screen> with AutomaticKeepAliveClientMixin {
  final CommerceService _commerce = CommerceService();
  final AdService _ads = AdService();
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic> _hub = const {};
  bool _loading = true;
  bool _busy = false;
  int _tab = 0;
  String _status = '';
  String _cosmeticFilter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _commerce.serverVerify = widget.api.googleVerifyPurchase;
    unawaited(_commerce.initialize(
      onVerified: (_) async {
        if (!mounted) return;
        _toast('Satın alma doğrulandı, hesabına işlendi.');
        unawaited(GameAudio.sfx('coin_count', enabled: widget.soundEnabled, volume: .90));
        Future<void>.delayed(const Duration(milliseconds: 120), () =>
          unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .84)));
        await _load();
        widget.onWalletChanged?.call();
      },
      onStatus: (message) {
        if (mounted) _toast(message);
      },
    ));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_commerce.dispose());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final hub = await widget.api.phase4Hub();
      final products = _list(hub['billing_products']).map(_map).toList();
      // Google Play product discovery is optional during APK/dev testing.
      // A billing failure must never take Store/Inventory/VIP/Okey Pass down.
      unawaited(Future<void>(() async {
        try {
          await _commerce.loadProducts(products.map((x) => '${x['sku'] ?? ''}'));
        } catch (error, stack) {
          debugPrint('OKEYX_COMMERCE_PRODUCTS_ERROR: $error\n$stack');
        }
      }));
      if (!mounted) return;
      setState(() {
        _hub = hub;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('OKEYX_PHASE4_LOAD_ERROR: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Faz 4 servisi: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wallet = _map(_hub['wallet']);
    final vip = _map(_hub['vip']);
    final pass = _map(_hub['pass']);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.all(widget.compact ? 8 : 13),
            children: [
              _hero(wallet, vip, pass),
              const SizedBox(height: 8),
              _tabs(),
              const SizedBox(height: 9),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    0 => _store(),
                    1 => _inventory(),
                    2 => _vip(),
                    _ => _pass(),
                  },
                ),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status, style: const TextStyle(fontSize: 8, color: Colors.white54)),
              ],
            ],
          ),
        ),
        if (_loading || _busy)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0x660B071E),
                child: Center(child: CircularProgressIndicator(color: _loading ? OkeyXColors.gold : OkeyXColors.mint)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hero(Map<String, dynamic> wallet, Map<String, dynamic> vip, Map<String, dynamic> pass) {
    final level = _int(vip['level']);
    final progress = (vip['progress'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: EdgeInsets.all(widget.compact ? 10 : 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E1453), Color(0xFF0F0A28)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OkeyXColors.gold.withValues(alpha: .28)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: widget.compact ? 46 : 58,
            height: widget.compact ? 46 : 58,
            decoration: BoxDecoration(shape: BoxShape.circle, color: OkeyXColors.gold.withValues(alpha: .12), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .55))),
            child: const Icon(Icons.workspace_premium_rounded, color: OkeyXColors.gold, size: 28),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('VIP $level • OKEY PASS', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble(), minHeight: 6, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(OkeyXColors.mint))),
              const SizedBox(height: 5),
              Text('Sonraki VIP: ${_moneyMinor(_int(vip['next_threshold_minor']))} • Okey Pass ${_int(pass['level'])}/${_int(pass['max_level'])}', style: const TextStyle(fontSize: 7.5, color: Colors.white60)),
            ]),
          ),
          const SizedBox(width: 10),
          _wallet(Icons.monetization_on_rounded, _compact(_int(wallet['coins'])), OkeyXColors.gold),
          const SizedBox(width: 5),
          _wallet(Icons.diamond_rounded, _compact(_int(wallet['diamonds'])), const Color(0xFF7EE8FF)),
        ],
      ),
    );
  }

  Widget _tabs() {
    const labels = [
      (Icons.storefront_rounded, 'MAĞAZA'),
      (Icons.inventory_2_rounded, 'ENVANTER'),
      (Icons.workspace_premium_rounded, 'VIP'),
      (Icons.auto_awesome_rounded, 'OKEY PASS'),
    ];
    return SizedBox(
      height: widget.compact ? 46 : 45,
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 5),
              child: Material(
                color: _tab == i ? OkeyXColors.mint.withValues(alpha: .16) : const Color(0x99160F3C),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: () => _switchTab(i),
                  borderRadius: BorderRadius.circular(13),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(labels[i].$1, size: 15, color: _tab == i ? OkeyXColors.mint : Colors.white54),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i].$2,
                        maxLines: 1,
                        style: TextStyle(fontSize: widget.compact ? 5.7 : 7.2, color: _tab == i ? Colors.white : Colors.white54, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  void _switchTab(int value) {
    if (_tab == value) return;
    setState(() => _tab = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  Widget _store() {
    final products = _list(_hub['billing_products']).map(_map).toList();
    final standardProducts = products.where((p) => p['daily_offer'] != true && p['first_purchase'] != true).toList();
    final offers = _list(_hub['offers']).map(_map).toList();
    final allCosmetics = _list(_hub['cosmetics']).map(_map).where((x) => x['owned'] != true).toList();
    final cosmetics = _cosmeticFilter == 'all' ? allCosmetics : allCosmetics.where((x) => '${x['category']}' == _cosmeticFilter).toList();
    final bySku = {for (final p in products) '${p['sku'] ?? ''}': p};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (offers.isNotEmpty) ...[
        Row(children:[_title('GÜNLÜK FIRSATLAR'), const Spacer(), const _Badge('HER GÜN YENİLENİR')]),
        SizedBox(
          height: 142,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: offers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final offer = offers[i];
              final sku = '${offer['sku'] ?? ''}';
              final product = bySku[sku] ?? const <String, dynamic>{};
              final play = _commerce.product(sku);
              final price = play?.price ?? '${product['price_hint'] ?? 'Play Store'}';
              final normalPrice = '${offer['normal_price_hint'] ?? ''}';
              final isWelcome = '${offer['id']}' == 'welcome_72h';
              final consumable = product['kind'] != 'non_consumable';
              return Container(
                width: widget.compact ? 286 : 328,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: isWelcome ? const [Color(0xFF2A1B79), Color(0xFF211559), Color(0xFF0F0A28)] : const [Color(0xFF1D1351), Color(0xFF1A1145), Color(0xFF0F0A28)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (isWelcome ? OkeyXColors.gold : OkeyXColors.cyan).withValues(alpha: .45)),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 5))],
                ),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x22FFA34B), border: Border.all(color: const Color(0x55FFA34B))),
                    child: Icon(isWelcome ? Icons.workspace_premium_rounded : Icons.local_fire_department_rounded, color: isWelcome ? OkeyXColors.gold : OkeyXColors.cyan, size: 28),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Row(children: [
                        Expanded(child: Text('${offer['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5))),
                        _Badge('${offer['badge'] ?? 'FIRSAT'}'),
                      ]),
                      const SizedBox(height: 3),
                      Text(product.isEmpty ? 'Süreli mağaza fırsatı' : _grantText(product), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.2, color: Colors.white70)),
                      const SizedBox(height: 3),
                      Row(children:[
                        if(normalPrice.isNotEmpty) Text(normalPrice, style: const TextStyle(fontSize:6.5,color:Colors.white38,decoration:TextDecoration.lineThrough)),
                        if(normalPrice.isNotEmpty) const SizedBox(width:5),
                        Text(price, style: const TextStyle(fontSize:8.5,color:OkeyXColors.gold,fontWeight:FontWeight.w900)),
                        const Spacer(),
                        Text('⏱ ${_offerRemaining(_int(offer['ends_at']))}', style: const TextStyle(fontSize: 6.8, color: Colors.white60)),
                      ]),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 29,
                        child: FilledButton(
                          onPressed: _busy || sku.isEmpty ? null : () => _purchase(sku, consumable),
                          child: Text(isWelcome ? "VIP 1'İ AÇ • $price" : 'FIRSATI AL • $price', style: const TextStyle(fontSize: 7.1, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 9),
      ],
      _title('GOOGLE PLAY PAKETLERİ'),
      Wrap(spacing: 8, runSpacing: 8, children: standardProducts.map(_billingCard).toList()),
      const SizedBox(height: 12),
      Row(children:[_titleWidget('KOZMETİK MAĞAZASI'),const Spacer(),_Badge('${allCosmetics.length} ÜRÜN')]),
      const SizedBox(height:6),
      SizedBox(
        height:34,
        child:ListView(
          scrollDirection:Axis.horizontal,
          children:[
            for(final entry in const <(String,String)>[('all','TÜMÜ'),('rack','ISTAKA'),('tiles','TAŞ'),('cloth','MASA'),('frame','ÇERÇEVE'),('avatar','AVATAR'),('music_kit','MÜZİK'),('victory_fx','BİTİŞ'),('spawn_fx','GİRİŞ'),('sound_pack','SES'),('emoji_pack','EMOJİ'),('title','UNVAN')])
              Padding(
                padding:const EdgeInsets.only(right:5),
                child:ChoiceChip(
                  selected:_cosmeticFilter==entry.$1,
                  onSelected:(_)=>setState(()=>_cosmeticFilter=entry.$1),
                  label:Text(entry.$2,style:const TextStyle(fontSize:6.5,fontWeight:FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height:7),
      if (cosmetics.isEmpty)
        _emptyState(Icons.check_circle_rounded, _cosmeticFilter=='all'?'Tüm mevcut kozmetikler envanterinde.':'Bu kategoride alınacak ürün kalmadı.', 'Yeni sezon kozmetikleri mağazaya geldiğinde burada görünecek.'),
      if (cosmetics.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: cosmetics.map(_cosmeticCard).toList()),
    ]);
  }

  Widget _billingCard(Map<String, dynamic> product) {
    final sku = '${product['sku'] ?? ''}';
    final play = _commerce.product(sku);
    final price = play?.price ?? '${product['price_hint'] ?? 'Play Store'}';
    final consumable = product['kind'] != 'non_consumable';
    return _card(
      width: widget.compact ? 180 : 220,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(product['premium_pass'] == true ? Icons.auto_awesome_rounded : product['diamonds'] != null && _int(product['diamonds']) > 0 ? Icons.diamond_rounded : Icons.monetization_on_rounded, color: OkeyXColors.gold, size: 22), const Spacer(), if (product['first_purchase'] == true) const _Badge('İLK ALIM')]),
        const SizedBox(height: 8),
        Text('${product['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
        const SizedBox(height: 4),
        Text(_grantText(product), style: const TextStyle(fontSize: 7.5, color: Colors.white54)),
        const SizedBox(height: 9),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : () => _purchase(sku, consumable), child: Text(price, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900)))),
      ]),
    );
  }

  Widget _cosmeticCard(Map<String, dynamic> item) {
    final category='${item['category']}';
    final rarity='${item['rarity'] ?? 'common'}';
    final accent=_rarityColor(rarity);
    return Container(
      width:widget.compact?186:224,
      padding:const EdgeInsets.all(10),
      decoration:BoxDecoration(
        gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[accent.withValues(alpha:.12),const Color(0xE6140D36),const Color(0xF20E0927)]),
        borderRadius:BorderRadius.circular(17),
        border:Border.all(color:accent.withValues(alpha:.34)),
        boxShadow:[BoxShadow(color:accent.withValues(alpha:.07),blurRadius:14,offset:const Offset(0,5))],
      ),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _cosmeticPreview(item),
        const SizedBox(height:8),
        Row(children:[Expanded(child:Text('${item['name']}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:9.6,fontWeight:FontWeight.w900))),_Badge(rarity.toUpperCase())]),
        const SizedBox(height:2),
        Text(_categoryName(category),style:const TextStyle(fontSize:6.8,color:Colors.white54,fontWeight:FontWeight.w700)),
        const SizedBox(height:8),
        SizedBox(width:double.infinity,height:30,child:OutlinedButton.icon(
          onPressed:_busy?null:()=>_buyCosmetic('${item['id']}'),
          icon:Icon(item['currency']=='diamonds'?Icons.diamond_rounded:Icons.monetization_on_rounded,size:12,color:item['currency']=='diamonds'?const Color(0xFF82E8FF):OkeyXColors.gold),
          label:Text('${_int(item['price'])} ${item['currency']=='diamonds'?'ELMAS':'ALTIN'}',style:const TextStyle(fontSize:7.2,fontWeight:FontWeight.w900)),
        )),
      ]),
    );
  }

  Color _rarityColor(String rarity)=>switch(rarity){
    'legendary'=>const Color(0xFFFFC75A),'epic'=>const Color(0xFFBC86FF),'rare'=>const Color(0xFF68CBFF),_=>OkeyXColors.mint
  };

  Widget _cosmeticPreview(Map<String,dynamic> item){
    final id='${item['id']}';final category='${item['category']}';final accent=_cosmeticAccentForId(id);
    Widget content;
    if(category=='rack'){
      content=Align(alignment:Alignment.center,child:Container(height:25,margin:const EdgeInsets.symmetric(horizontal:12),decoration:BoxDecoration(gradient:LinearGradient(colors:[accent.withValues(alpha:.95),accent.withValues(alpha:.42),const Color(0xFF0E0927)]),borderRadius:BorderRadius.circular(8),border:Border.all(color:accent.withValues(alpha:.6))),child:Align(alignment:const Alignment(0,.48),child:Container(height:3,margin:const EdgeInsets.symmetric(horizontal:8),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(9))))));
    }else if(category=='tiles'){
      content=Row(mainAxisAlignment:MainAxisAlignment.center,children:[for(final n in const [1,0,1]) Container(width:28,height:38,margin:const EdgeInsets.symmetric(horizontal:2),alignment:Alignment.center,decoration:BoxDecoration(gradient:LinearGradient(colors:[Colors.white,accent.withValues(alpha:.22)]),borderRadius:BorderRadius.circular(6),border:Border.all(color:accent.withValues(alpha:.62))),child:Text('$n',style:TextStyle(color:n==0?Colors.black:const Color(0xFFD32929),fontSize:14,fontWeight:FontWeight.w900)))]);
    }else if(category=='cloth'){
      content=Container(margin:const EdgeInsets.symmetric(horizontal:18,vertical:5),decoration:BoxDecoration(color:accent.withValues(alpha:.24),borderRadius:BorderRadius.circular(40),border:Border.all(color:accent,width:2),boxShadow:[BoxShadow(color:accent.withValues(alpha:.18),blurRadius:15)]),child:Center(child:Icon(Icons.table_restaurant_rounded,color:accent,size:22)));
    }else if(category=='frame'){
      content=Center(child:Container(width:52,height:52,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:accent,width:id.contains('dragon')||id.contains('founder')?4:3),boxShadow:[BoxShadow(color:accent.withValues(alpha:.42),blurRadius:12)]),child:const Icon(Icons.person_rounded,color:Colors.white70,size:28)));
    }else if(category=='avatar'){
      final icon=id.contains('fox')||id.contains('cat')?Icons.pets_rounded:id.contains('phoenix')?Icons.local_fire_department_rounded:Icons.shield_rounded;
      content=Center(child:CircleAvatar(radius:27,backgroundColor:accent.withValues(alpha:.22),child:Icon(icon,color:accent,size:30)));
    }else if(category=='emoji_pack'){
      final set=id.contains('party')?'🥳 🎉 🔥':id.contains('cafe')?'☕ 🧿 🍀':id.contains('troll')?'😈 🤡 🩴':'💜 ⚡ ✨';
      content=Center(child:Text(set,style:const TextStyle(fontSize:21)));
    }else if(category=='sound_pack'){
      content=Center(child:Row(mainAxisSize:MainAxisSize.min,children:[for(final h in const [10.0,24.0,16.0,32.0,20.0,12.0]) Container(width:4,height:h,margin:const EdgeInsets.symmetric(horizontal:2),decoration:BoxDecoration(color:accent,borderRadius:BorderRadius.circular(5)))]));
    }else if(category=='music_kit'){
      content=Center(child:Stack(alignment:Alignment.center,children:[Icon(Icons.album_rounded,color:accent.withValues(alpha:.55),size:58),const Icon(Icons.music_note_rounded,color:Colors.white,size:25)]));
    }else if(category=='victory_fx'){
      content=Center(child:Text(id.contains('rose')?'🌹 ✨ 🌹':id.contains('ice')?'❄ ✦ ❄':id.contains('ember')?'🔥 ✦ 🔥':id.contains('crown')?'♛ ✨ ♛':'✦ ✨ ✦',style:TextStyle(fontSize:22,color:accent)));
    }else if(category=='spawn_fx'){
      content=Center(child:Icon(id.contains('fire')?Icons.local_fire_department_rounded:id.contains('lightning')?Icons.bolt_rounded:Icons.login_rounded,size:52,color:accent));
    }else if(category=='title'){
      content=Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),decoration:BoxDecoration(color:accent.withValues(alpha:.12),borderRadius:BorderRadius.circular(10),border:Border.all(color:accent.withValues(alpha:.42))),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.workspace_premium_rounded,color:accent,size:15),const SizedBox(width:5),Text('${item['name']}'.toUpperCase(),style:TextStyle(fontSize:7,color:accent,fontWeight:FontWeight.w900))])));
    }else{content=Center(child:_cosmeticIcon(category));}
    return Container(height:68,width:double.infinity,decoration:BoxDecoration(color:Colors.black.withValues(alpha:.16),borderRadius:BorderRadius.circular(13),border:Border.all(color:Colors.white10)),child:content);
  }

  Color _cosmeticAccentForId(String id){
    if(id.contains('gold')||id.contains('royal')||id.contains('crown'))return OkeyXColors.gold;
    if(id.contains('sakura')||id.contains('rose'))return const Color(0xFFFF9AB8);
    if(id.contains('ice'))return const Color(0xFF9DEBFF);
    if(id.contains('ember')||id.contains('phoenix'))return const Color(0xFFFF8D58);
    if(id.contains('neon')||id.contains('bosphorus'))return OkeyXColors.cyan;
    if(id.contains('obsidian')||id.contains('carbon'))return const Color(0xFF9DA8B4);
    if(id.contains('midnight')||id.contains('tokyo'))return const Color(0xFF8B8DFF);
    return OkeyXColors.mint;
  }

  Widget _inventory() {
    final all = _list(_hub['cosmetics']).map(_map).where((x) => x['owned'] == true).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in all) {
      groups.putIfAbsent('${item['category']}', () => <Map<String, dynamic>>[]).add(item);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('ENVANTER'),
      if (all.isEmpty)
        _emptyState(Icons.inventory_2_outlined, 'Envanterin henüz boş.', 'Mağazadan kozmetik alabilir veya Okey Pass ödüllerinden kazanabilirsin.'),
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(_categoryName(entry.key).toUpperCase(), style: const TextStyle(fontSize: 7.5, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: .7)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: entry.value.map((item) => _card(width: widget.compact ? 175 : 215, child: Row(children: [
            _cosmeticIcon('${item['category']}'),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              Text(item['equipped'] == true ? 'Masada aktif' : 'Kullanıma hazır', style: TextStyle(fontSize: 7, color: item['equipped'] == true ? OkeyXColors.mint : Colors.white54)),
            ])),
            IconButton(
              tooltip: item['equipped'] == true ? 'Aktif' : 'Kullan',
              onPressed: item['equipped'] == true || _busy ? null : () => _equip('${item['id']}'),
              icon: Icon(item['equipped'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: item['equipped'] == true ? OkeyXColors.mint : Colors.white38, size: 19),
            ),
          ]))).toList(),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _vip() {
    final vip = _map(_hub['vip']);
    final level = _int(vip['level']);
    final accent = _vipAccent(level);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('KALICI VIP'),
      _card(
        width: double.infinity,
        child: Row(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [accent, const Color(0xFF7EE8FF)]),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: .26), blurRadius: 18)],
            ),
            child: Center(child: Text('$level', style: const TextStyle(color: Color(0xFF120C31), fontSize: 25, fontWeight: FontWeight.w900))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('VIP $level', style: TextStyle(fontSize: 17, color: accent, fontWeight: FontWeight.w900)),
              const SizedBox(width: 7),
              _Badge(_vipTierName(level)),
            ]),
            const Text('Seviyen toplam doğrulanmış alışverişine göre kalıcı olarak yükselir. VIP, oyun kurallarında avantaj sağlamaz.', style: TextStyle(fontSize: 8, color: Colors.white60)),
            const SizedBox(height: 7),
            Text('Ek çark +${_int(vip['extra_wheel'])} • Ek görev +${_int(vip['extra_tasks'])} • Profil çerçevesi ${_int(vip['frame_tier'])}. kademe', style: const TextStyle(fontSize: 8, color: OkeyXColors.mint, fontWeight: FontWeight.w900)),
          ])),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: vip['daily_claimed'] == true || _busy ? null : _claimVip,
            icon: const Icon(Icons.card_giftcard_rounded, size: 16),
            label: Text(vip['daily_claimed'] == true ? 'BUGÜN ALINDI' : 'GÜNLÜK BONUS', style: const TextStyle(fontSize: 8)),
          ),
        ]),
      ),
      const SizedBox(height: 9),
      _card(
        width: double.infinity,
        child: Row(children: [
          const Icon(Icons.verified_user_rounded, color: OkeyXColors.mint),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              level == 0
                  ? 'İlk VIP seviyesine ulaştığında özel rozet, isim rengi ve çerçeve görünümü açılır.'
                  : '${_vipTierName(level)} görünümü aktif. VIP seviyen yükseldikçe rozet, isim rengi ve profil çerçeven gelişir.',
              style: const TextStyle(fontSize: 8.2, color: Colors.white70),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _pass() {
    final pass = _map(_hub['pass']);
    final tasks = _list(pass['tasks']).map(_map).toList();
    final level = _int(pass['level']);
    final maxLevel = _int(pass['max_level']);
    final premiumActive = pass['premium'] == true;
    final claimedFree = _list(pass['claimed_free']).map(_int).toSet();
    final claimedPremium = _list(pass['claimed_premium']).map(_int).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _titleWidget('${pass['title'] ?? 'OKEY PASS'}'),
        const Spacer(),
        _Badge(premiumActive ? 'PREMIUM AKTİF' : 'ÜCRETSİZ'),
      ]),
      const SizedBox(height: 7),
      if (!premiumActive) ...[
        Container(
          width:double.infinity,
          padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF281972),Color(0xFF8A5B1D),Color(0xFF150D3C)]),borderRadius:BorderRadius.circular(16),border:Border.all(color:OkeyXColors.gold.withValues(alpha:.72))),
          child:Row(children:[
            const Icon(Icons.workspace_premium_rounded,color:OkeyXColors.gold,size:34),const SizedBox(width:10),
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('OKEY PASS PREMIUM',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900)),SizedBox(height:3),Text('Premium ödül yolunu aç • kazandığın seviyelerde iki ödülü birden topla.',maxLines:2,style:TextStyle(fontSize:7.5,color:Colors.white70))])),
            const SizedBox(width:8),
            FilledButton(onPressed:_busy?null:()=>_purchase('okeyx.pass.s1',false),child:const Text("PASS'I AÇ\n₺149,90",textAlign:TextAlign.center,style:TextStyle(fontSize:7.5,fontWeight:FontWeight.w900))),
          ]),
        ),
        const SizedBox(height:8),
      ] else ...[
        Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),decoration:BoxDecoration(color:OkeyXColors.gold.withValues(alpha:.10),borderRadius:BorderRadius.circular(12),border:Border.all(color:OkeyXColors.gold.withValues(alpha:.32))),child:const Row(children:[Icon(Icons.verified_rounded,color:OkeyXColors.gold,size:17),SizedBox(width:7),Text('Premium ödül yolu açık',style:TextStyle(fontSize:8.5,fontWeight:FontWeight.w900))])),
        const SizedBox(height:8),
      ],
      _card(width: double.infinity, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('SEVİYE $level / $maxLevel', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('${_int(pass['points'])} PASS XP', style: const TextStyle(fontSize: 8, color: OkeyXColors.gold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ((_int(pass['points']) % (_int(pass['level_points']) == 0 ? 1 : _int(pass['level_points']))) / (_int(pass['level_points']) == 0 ? 1 : _int(pass['level_points']))).clamp(0.0, 1.0).toDouble(),
            minHeight: 7,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation(Color(0xFFD58CFF)),
          ),
        ),
      ])),
      const SizedBox(height: 9),
      _title('PASS GÖREVLERİ'),
      ...tasks.map((task) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: _card(
          width: double.infinity,
          child: Row(children: [
            Icon(task['complete'] == true ? Icons.task_alt_rounded : Icons.pending_actions_rounded, color: task['complete'] == true ? OkeyXColors.mint : Colors.white38, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${task['title']}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              Text('${_int(task['progress'])}/${_int(task['target'])} • +${_int(task['points'])} Pass XP', style: const TextStyle(fontSize: 7, color: Colors.white54)),
            ])),
            FilledButton.tonal(
              onPressed: task['complete'] == true && task['claimed'] != true && !_busy ? () => _claimPassTask('${task['id']}') : null,
              child: Text(task['claimed'] == true ? 'ALINDI' : 'AL', style: const TextStyle(fontSize: 7)),
            ),
          ]),
        ),
      )),
      const SizedBox(height: 6),
      Row(children: [
        _titleWidget('SEZON ÖDÜLLERİ'),
        const Spacer(),
        const Text('Ücretsiz + Premium ödül yolu', style: TextStyle(fontSize: 7, color: Colors.white54)),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 232,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: maxLevel,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final n = i + 1;
            final free = _map(_map(pass['free_rewards'])['$n']);
            final premium = _map(_map(pass['premium_rewards'])['$n']);
            final unlocked = n <= level;
            return Container(
              width: 152,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: unlocked ? const Color(0xCC1D1351) : const Color(0xAA100A2B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: unlocked ? OkeyXColors.gold.withValues(alpha: .42) : Colors.white10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('LV $n', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: unlocked ? Colors.white : Colors.white38)),
                  const Spacer(),
                  Icon(unlocked ? Icons.lock_open_rounded : Icons.lock_rounded, size: 12, color: unlocked ? OkeyXColors.mint : Colors.white24),
                ]),
                const SizedBox(height: 6),
                _passRewardLane(
                  label: 'ÜCRETSİZ',
                  reward: free,
                  unlocked: unlocked,
                  claimed: claimedFree.contains(n),
                  enabled: true,
                  onClaim: free.isEmpty || !unlocked || claimedFree.contains(n) || _busy ? null : () => _claimPassLevel(n, false),
                ),
                const SizedBox(height: 5),
                _passRewardLane(
                  label: 'PREMIUM',
                  reward: premium,
                  unlocked: unlocked,
                  claimed: claimedPremium.contains(n),
                  enabled: premiumActive,
                  onClaim: premium.isEmpty || !unlocked || !premiumActive || claimedPremium.contains(n) || _busy ? null : () => _claimPassLevel(n, true),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }


  Widget _gameCard(String title, IconData icon, String detail, String description, VoidCallback onPlay) => _card(
        width: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0x22D58CFF), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 25, color: const Color(0xFFD58CFF))),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              Text(detail, style: const TextStyle(fontSize: 7, color: OkeyXColors.gold, fontWeight: FontWeight.w800)),
            ])),
          ]),
          const SizedBox(height: 7),
          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7, color: Colors.white54)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.tonal(onPressed: _busy ? null : onPlay, child: const Text('OYNA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900)))),
        ]),
      );

  Widget _passRewardLane({
    required String label,
    required Map<String, dynamic> reward,
    required bool unlocked,
    required bool claimed,
    required bool enabled,
    required VoidCallback? onClaim,
  }) {
    final hasReward = reward.isNotEmpty;
    final locked = !unlocked || !enabled;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: label == 'PREMIUM' ? OkeyXColors.gold.withValues(alpha: .06) : Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: label == 'PREMIUM' ? OkeyXColors.gold.withValues(alpha: .18) : Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 6.2, color: label == 'PREMIUM' ? OkeyXColors.gold : OkeyXColors.mint, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Row(children: [
          Icon(_rewardIcon(reward), size: 12, color: locked ? Colors.white24 : Colors.white70),
          const SizedBox(width: 3),
          Expanded(child: Text(hasReward ? _rewardText(reward) : '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 7.2, fontWeight: FontWeight.w800, color: locked ? Colors.white24 : Colors.white70))),
        ]),
        if (hasReward) ...[
          const SizedBox(height: 3),
          SizedBox(
            height: 27,
            width: double.infinity,
            child: TextButton(
              onPressed: onClaim,
              child: Text(claimed ? 'ALINDI' : !enabled ? 'PREMIUM' : unlocked ? 'AL' : 'KİLİTLİ', style: const TextStyle(fontSize: 6.2, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ]),
    );
  }

  IconData _rewardIcon(Map<String, dynamic> reward) {
    if (reward['item'] != null) return Icons.auto_awesome_rounded;
    if (_int(reward['diamonds']) > 0) return Icons.diamond_rounded;
    if (_int(reward['tickets']) > 0) return Icons.confirmation_number_rounded;
    return Icons.monetization_on_rounded;
  }

  Widget _emptyState(IconData icon, String title, String subtitle) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0x88170E40), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
        child: Row(children: [
          Icon(icon, color: OkeyXColors.mint, size: 25),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 7.2, color: Colors.white54)),
          ])),
        ]),
      );

  Color _vipAccent(int level) => level >= 200
      ? const Color(0xFFFF8FD8)
      : level >= 100
          ? const Color(0xFFD58CFF)
          : level >= 50
              ? const Color(0xFF7EE8FF)
              : level >= 10
                  ? OkeyXColors.gold
                  : level > 0
                      ? const Color(0xFFCF8E5B)
                      : OkeyXColors.mint;

  String _vipTierName(int level) => level >= 200
      ? 'EFSANE'
      : level >= 100
          ? 'KRALİYET'
          : level >= 50
              ? 'ELMAS'
              : level >= 10
                  ? 'ALTIN'
                  : level > 0
                      ? 'BRONZ'
                      : 'BAŞLANGIÇ';

  String _offerRemaining(int endsAtSeconds) {
    if (endsAtSeconds <= 0) return 'sınırlı';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = endsAtSeconds - now;
    if (remaining <= 0) return 'sona erdi';
    final days = remaining ~/ 86400;
    final hours = (remaining % 86400) ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    if (days > 0) return '${days}g ${hours}sa';
    if (hours > 0) return '${hours}sa ${minutes}dk';
    return '${minutes.clamp(1, 59)}dk';
  }

  Future<void> _purchase(String sku, bool consumable) async {
    final out = await _commerce.buy(sku, consumable: consumable);
    if (!out.ok) _toast(out.message);
  }

  Future<void> _buyCosmetic(String id) => _run(() async {
        final out = await widget.api.buyCosmetic(id);
        _toast(out['ok'] == true ? 'Eşya envantere eklendi.' : '${out['code'] ?? 'Satın alınamadı.'}');
        if (out['ok'] == true) unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .76));
        await _load(); widget.onWalletChanged?.call();
      });

  Future<void> _equip(String id) => _run(() async {
        final out = await widget.api.equipCosmetic(id);
        _toast(out['ok'] == true ? 'Masada kullanacağın kozmetik değişti.' : '${out['code']}');
        await _load();
      });

  Future<void> _claimVip() => _run(() async {
        final out = await widget.api.claimVipDaily();
        _toast(out['ok'] == true ? 'VIP günlük bonusu alındı.' : 'Bugünkü VIP bonusu zaten alındı.');
        if (out['ok'] == true) { unawaited(GameAudio.sfx('coin_count', enabled: widget.soundEnabled, volume: .84)); Future<void>.delayed(const Duration(milliseconds: 120), () => unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .78))); }
        await _load(); widget.onWalletChanged?.call();
      });

  Future<void> _claimPassTask(String id) => _run(() async {
        final out = await widget.api.claimPassTask(id);
        _toast(out['ok'] == true ? '+${_int(out['points'])} Pass XP' : '${out['code']}');
        if (out['ok'] == true) unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .74));
        await _load();
      });

  Future<void> _claimPassLevel(int level, bool premium) => _run(() async {
        final out = await widget.api.claimPassLevel(level, premium: premium);
        _toast(out['ok'] == true ? 'Sezon ödülü alındı.' : '${out['code']}');
        if (out['ok'] == true) { unawaited(GameAudio.sfx('coin_count', enabled: widget.soundEnabled, volume: .86)); Future<void>.delayed(const Duration(milliseconds: 120), () => unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .80))); }
        await _load(); widget.onWalletChanged?.call();
      });

  Future<void> _playGame(String game, {int? choice}) => _run(() async {
        final out = await widget.api.playSideGame(game, choice: choice);
        if (out['ok'] == true) {
          _toast(_int(out['payout_coins']) > 0 ? '${_compact(_int(out['payout_coins']))} altın kazandın!' : 'Bu tur ödül çıkmadı.');
        } else {
          _toast('${out['code']}');
        }
        await _load(); widget.onWalletChanged?.call();
      });

  Future<void> _pickAndPlay(String game, int count) async {
    final choice = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(title: Text(game == 'horse' ? 'Atını seç' : 'Kupayı seç'), content: Wrap(spacing: 7, children: [for (var i = 1; i <= count; i++) FilledButton.tonal(onPressed: () => Navigator.pop(ctx, i), child: Text('$i'))])));
    if (choice != null) await _playGame(game, choice: choice);
  }

  Future<void> _rewardAd(String kind) => _run(() async {
        final out = await _ads.showRewarded(widget.api, rewardKind: kind);
        _toast(out['ok'] == true ? 'Reklam ödülü hesabına eklendi.' : '${out['code'] ?? 'Reklam hazır değil.'}');
        if (out['ok'] == true) { unawaited(GameAudio.sfx('coin_count', enabled: widget.soundEnabled, volume: .86)); Future<void>.delayed(const Duration(milliseconds: 120), () => unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .80))); }
        await _load(); widget.onWalletChanged?.call();
      });

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      _toast('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    setState(() => _status = text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Widget _card({required double width, required Widget child}) => Container(width: width, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xCC170E40), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)]), child: child);
  Widget _wallet(IconData icon, String value, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(11), border: Border.all(color: color.withValues(alpha: .22))), child: Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(value, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w900))]));
  Widget _title(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: _titleWidget(text));
  Widget _titleWidget(String text) => Text(text, style: const TextStyle(fontSize: 9, color: Colors.white60, fontWeight: FontWeight.w900, letterSpacing: 1.1));
  Widget _cosmeticIcon(String category) => Container(width: 36, height: 36, decoration: BoxDecoration(color: OkeyXColors.mint.withValues(alpha: .09), borderRadius: BorderRadius.circular(11)), child: Icon(switch (category) { 'rack' => Icons.horizontal_rule_rounded, 'tiles' => Icons.grid_view_rounded, 'cloth' => Icons.texture_rounded, 'frame' => Icons.crop_square_rounded, 'avatar' => Icons.face_rounded, 'emoji_pack' => Icons.emoji_emotions_rounded, 'sound_pack' => Icons.surround_sound_rounded, 'music_kit' => Icons.library_music_rounded, 'victory_fx' => Icons.celebration_rounded, 'spawn_fx' => Icons.login_rounded, 'title' => Icons.workspace_premium_rounded, _ => Icons.auto_awesome_rounded }, color: OkeyXColors.mint, size: 20));

  String _grantText(Map<String, dynamic> p) {
    final bits = <String>[];
    if (_int(p['coins']) > 0) bits.add('${_compact(_int(p['coins']))} altın');
    if (_int(p['diamonds']) > 0) bits.add('${_int(p['diamonds'])} elmas');
    if (_int(p['tickets']) > 0) bits.add('${_int(p['tickets'])} bilet');
    final vouchers = _map(p['slot_vouchers']);
    final voucherCount = vouchers.values.fold<int>(0, (sum, value) => sum + _int(value));
    if (voucherCount > 0) bits.add('$voucherCount Oyun Bileti');
    if (p['premium_pass'] == true) bits.add('Premium Pass');
    return bits.isEmpty ? 'Özel paket' : bits.join(' • ');
  }

  String _rewardText(Map<String, dynamic> r) {
    if (r.isEmpty) return '—';
    if (r['item'] != null) return 'Kozmetik';
    if (_int(r['diamonds']) > 0) return '${_int(r['diamonds'])} 💎';
    if (_int(r['tickets']) > 0) return '${_int(r['tickets'])} 🎟';
    return '${_compact(_int(r['coins']))} altın';
  }

  String _categoryName(String category) => switch (category) { 'rack' => 'Istaka', 'tiles' => 'Taş tasarımı', 'cloth' => 'Masa örtüsü', 'frame' => 'Profil çerçevesi', 'avatar' => 'Avatar', 'emoji_pack' => 'Emoji paketi', 'sound_pack' => 'Ses paketi', 'music_kit' => 'Müzik kiti', 'victory_fx' => 'Bitiş efekti', 'spawn_fx' => 'Masa giriş efekti', 'title' => 'Unvan', _ => category };
  String _compact(int value) {
    final negative = value < 0;
    final abs = value.abs();
    String scaled(num divisor, String suffix) {
      var text = (abs / divisor).toStringAsFixed(2);
      while (text.contains('.') && text.endsWith('0')) {
        text = text.substring(0, text.length - 1);
      }
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
      return '${negative ? '-' : ''}$text$suffix';
    }
    if (abs >= 1000000000) return scaled(1000000000, 'B');
    if (abs >= 1000000) return scaled(1000000, 'M');
    if (abs >= 1000) return scaled(1000, 'K');
    return '$value';
  }

  String _moneyMinor(int v) => v <= 0 ? '—' : '₺${(v / 100).toStringAsFixed(2).replaceAll('.', ',')}';
  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<dynamic> _list(dynamic v) => v is List ? v : const [];
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .10), borderRadius: BorderRadius.circular(8), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .22))), child: Text(text, style: const TextStyle(fontSize: 6.3, color: OkeyXColors.gold, fontWeight: FontWeight.w900)));
}
