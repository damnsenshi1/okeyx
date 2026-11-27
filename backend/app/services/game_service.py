from __future__ import annotations
from dataclasses import dataclass
from app.domain.models import TableState, Meld, MeldType
from app.domain.rules import Rules101, RuleError

@dataclass(slots=True)
class ActionResult:
    ok: bool
    code: str='ok'
    payload: dict|None=None

class GameService:
    def __init__(self,state:TableState):
        self.state=state; self.rules=Rules101(state.joker)

    def _assert_turn(self,seat:int):
        if seat!=self.state.current_seat: raise RuleError('not_your_turn')

    @staticmethod
    def _flat_unique(groups:list[list[str]])->bool:
        ids=[x for g in groups for x in g]
        return len(ids)==len(set(ids))

    def _must_keep_finish_tile(self, hand_count:int, used_count:int)->bool:
        # 101'de bitiş son taşı atarak yapılır; açma/işleme ile 0 taş bırakılamaz.
        return hand_count-used_count >= 1

    def _clear_left_if_used(self,p, used:set[str]):
        if p.pending_left_tile_id and p.pending_left_tile_id in used:
            p.pending_left_tile_id=None; p.pending_left_from_seat=None


    def _fit_manual_series_finish_tile(self,p,resolved:list[list],threshold:int|None)->list[list]|None:
        """Keep manual rack intent while guaranteeing one final discard tile.

        The client may visually place a loose finish tile directly beside a
        3/4+ tile meld. Older parsing swallowed that loose tile into the open
        payload, so the server rejected the whole action as must_keep_finish_tile.
        Try only order-preserving trims/subsets; never run the auto solver or
        move a joker into another meld.
        """
        hand_ids={t.id for t in p.hand}
        def acceptable(groups:list[list])->bool:
            if not groups:return False
            used={t.id for g in groups for t in g}
            if len(used)>=len(hand_ids):return False
            if p.pending_left_tile_id and p.pending_left_tile_id not in used:return False
            if not p.opened:
                r=self.rules.validate_series_opening(groups,self.state.min_opening_score if threshold is None else threshold)
                return bool(r.valid)
            return all(self.rules.validate_meld(g).valid for g in groups)
        if acceptable(resolved):return resolved
        # First remove exactly one visually-adjacent loose tile. Prefer the end
        # of the last group because that most closely matches physical rack use.
        for gi in range(len(resolved)-1,-1,-1):
            g=resolved[gi]
            if len(g)<=3:continue
            for ti in range(len(g)-1,-1,-1):
                cand=[list(x) for x in resolved]
                cand[gi]=[t for j,t in enumerate(g) if j!=ti]
                if acceptable(cand):return cand
        # If the final contiguous segment was actually the loose remainder,
        # leave that whole group in hand rather than inventing a new layout.
        for gi in range(len(resolved)-1,-1,-1):
            cand=[list(x) for j,x in enumerate(resolved) if j!=gi]
            if acceptable(cand):return cand
        return None

    def _begin_table_transaction(self,p):
        """Masaya yapılan ilk hamleden önce tam tur fotoğrafını bir kez al."""
        if p.turn_table_snapshot is not None:return
        p.turn_table_snapshot={
            'hand':list(p.hand),
            'melds':[Meld(m.id,m.owner_seat,m.meld_type,list(m.tiles)) for m in self.state.melds],
            'opened':p.opened,
            'opening_mode':p.opening_mode,
            'opening_score':p.opening_score,
            'opening_pairs':p.opening_pairs,
            'min_score':self.state.min_opening_score,
            'min_pairs':self.state.min_opening_pairs,
            'pending_left_tile_id':p.pending_left_tile_id,
            'pending_left_from_seat':p.pending_left_from_seat,
        }

    def _remember_open_batch(self,p:PlayerState,meld_ids:list[str],tiles:list[Tile],prev:dict):
        p.last_open_batch={
            'meld_ids':list(meld_ids),
            'tile_ids':[t.id for t in tiles],
            'prev_opened':prev['opened'],
            'prev_mode':prev['opening_mode'],
            'prev_score':prev['opening_score'],
            'prev_pairs':prev['opening_pairs'],
            'prev_min_score':prev['min_score'],
            'prev_min_pairs':prev['min_pairs'],
        }

    def undo_last_opening(self,seat:int)->ActionResult:
        self._assert_turn(seat)
        p=self.state.player(seat)
        full=p.turn_table_snapshot
        if full is not None:
            before=len(p.hand)
            p.hand=list(full['hand'])
            self.state.melds=[Meld(m.id,m.owner_seat,m.meld_type,list(m.tiles)) for m in full['melds']]
            p.opened=bool(full['opened'])
            p.opening_mode=full['opening_mode']
            p.opening_score=int(full['opening_score'])
            p.opening_pairs=int(full['opening_pairs'])
            self.state.min_opening_score=int(full['min_score'])
            self.state.min_opening_pairs=int(full['min_pairs'])
            p.pending_left_tile_id=full['pending_left_tile_id']
            p.pending_left_from_seat=full['pending_left_from_seat']
            p.turn_table_snapshot=None
            p.last_open_batch=None
            p.last_layoff=None
            return ActionResult(True,'opening_undone',{'returned':max(0,len(p.hand)-before),'all':True})
        snap=p.last_open_batch
        if not snap:return ActionResult(False,'no_opening_to_undo')
        ids=set(snap['meld_ids'])
        owned=[m for m in self.state.melds if m.id in ids and m.owner_seat==seat]
        if len(owned)!=len(ids):return ActionResult(False,'opening_changed_cannot_undo')
        returned=[t for m in owned for t in m.tiles]
        self.state.melds=[m for m in self.state.melds if m.id not in ids]
        p.hand.extend(returned)
        p.opened=bool(snap['prev_opened'])
        p.opening_mode=snap['prev_mode']
        p.opening_score=int(snap['prev_score'])
        p.opening_pairs=int(snap['prev_pairs'])
        self.state.min_opening_score=int(snap['prev_min_score'])
        self.state.min_opening_pairs=int(snap['prev_min_pairs'])
        p.last_open_batch=None
        p.last_layoff=None
        return ActionResult(True,'opening_undone',{'returned':len(returned)})

    def open_series(self,seat:int, groups:list[list[str]], min_score:int|None=None)->ActionResult:
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not groups or not self._flat_unique(groups):return ActionResult(False,'duplicate_or_empty_groups')
        byid={t.id:t for t in p.hand}
        try: resolved=[[byid[x] for x in g] for g in groups]
        except KeyError:return ActionResult(False,'tile_not_in_hand')
        threshold=self.state.min_opening_score if min_score is None else min_score
        fitted=self._fit_manual_series_finish_tile(p,resolved,threshold)
        if fitted is not None:resolved=fitted
        used={t.id for g in resolved for t in g}
        if not self._must_keep_finish_tile(len(p.hand),len(used)):return ActionResult(False,'must_keep_finish_tile')

        prev={'opened':p.opened,'opening_mode':p.opening_mode,'opening_score':p.opening_score,
              'opening_pairs':p.opening_pairs,'min_score':self.state.min_opening_score,'min_pairs':self.state.min_opening_pairs}

        if not p.opened:
            r=self.rules.validate_series_opening(resolved,threshold)
            if not r.valid:return ActionResult(False,r.reason,{'score':r.score,'required':threshold})
            if p.pending_left_tile_id and p.pending_left_tile_id not in used:
                return ActionResult(False,'left_tile_must_be_in_opening')
            self._begin_table_transaction(p)
            p.opened=True;p.opening_mode='series';p.opening_score=r.score
            if self.state.variant=='fold': self.state.min_opening_score=max(self.state.min_opening_score,r.score+1)
            payload={'score':r.score,'opening':True,'next_min_score':self.state.min_opening_score}
        else:
            if p.opening_mode!='series':return ActionResult(False,'wrong_opening_mode')
            score=0
            for g in resolved:
                vr=self.rules.validate_meld(g)
                if not vr.valid:return ActionResult(False,'invalid_meld')
                score+=vr.score
            if p.pending_left_tile_id and p.pending_left_tile_id not in used:
                return ActionResult(False,'left_tile_must_be_used')
            self._begin_table_transaction(p)
            payload={'score':score,'opening':False,'added_melds':len(resolved)}

        p.hand=[t for t in p.hand if t.id not in used]
        created=[]
        for g in resolved:
            vr=self.rules.validate_meld(g)
            kind=vr.meld_type or MeldType.RUN
            # Masa üstü daima mantıklı okunur: 9-7-8 gibi dağınık açılmaz.
            # Gerçek okey de temsil ettiği eksik pozisyona yerleşir.
            ordered=self.rules.canonical_meld_order(g,kind)
            mid=f'{seat}-series-{len(self.state.melds)}'
            self.state.melds.append(Meld(mid,seat,kind,ordered));created.append(mid)
        self._clear_left_if_used(p,used)
        self._remember_open_batch(p,created,[t for g in resolved for t in g],prev)
        return ActionResult(True,payload=payload)


    def open_pairs(self,seat:int,pairs:list[list[str]])->ActionResult:
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not pairs or not self._flat_unique(pairs):return ActionResult(False,'duplicate_or_empty_groups')
        byid={t.id:t for t in p.hand}
        try: resolved=[[byid[x] for x in g] for g in pairs]
        except KeyError:return ActionResult(False,'tile_not_in_hand')
        used={x for g in pairs for x in g}
        if not self._must_keep_finish_tile(len(p.hand),len(used)):return ActionResult(False,'must_keep_finish_tile')

        prev={'opened':p.opened,'opening_mode':p.opening_mode,'opening_score':p.opening_score,
              'opening_pairs':p.opening_pairs,'min_score':self.state.min_opening_score,'min_pairs':self.state.min_opening_pairs}

        if not p.opened:
            minimum=self.state.min_opening_pairs
            r=self.rules.validate_pair_opening(resolved,minimum)
            if not r.valid:return ActionResult(False,r.reason,{'required':minimum})
            if p.pending_left_tile_id and p.pending_left_tile_id not in used:
                return ActionResult(False,'left_tile_must_be_in_opening')
            self._begin_table_transaction(p)
            p.opened=True;p.opening_mode='pairs';p.opening_score=r.score;p.opening_pairs=len(resolved)
            if self.state.variant=='fold': self.state.min_opening_pairs=max(self.state.min_opening_pairs,len(resolved)+1)
            payload={'pairs':len(resolved),'score':r.score,'opening':True,'next_min_pairs':self.state.min_opening_pairs}
        else:
            if p.opening_mode!='pairs':return ActionResult(False,'wrong_opening_mode')
            for pair in resolved:
                if not self.rules.validate_pair(pair).valid:return ActionResult(False,'pair_mismatch')
            if p.pending_left_tile_id and p.pending_left_tile_id not in used:
                return ActionResult(False,'left_tile_must_be_used')
            self._begin_table_transaction(p)
            payload={'pairs':len(resolved),'opening':False,'added_pairs':len(resolved)}

        p.hand=[t for t in p.hand if t.id not in used]
        created=[]
        for g in resolved:
            mid=f'{seat}-pair-{len(self.state.melds)}'
            self.state.melds.append(Meld(mid,seat,MeldType.PAIR,list(g)));created.append(mid)
        self._clear_left_if_used(p,used)
        self._remember_open_batch(p,created,[t for g in resolved for t in g],prev)
        return ActionResult(True,payload=payload)


    def _same_team(self,a:int,b:int)->bool:
        mode=getattr(self.state,'team_mode','solo')
        return mode=='paired' and (a%2)==(b%2)

    def replace_table_okey(self,seat:int,tile_id:str,meld_id:str)->ActionResult:
        """Masadaki gerçek okeyi, temsil ettiği gerçek taşla değiştirip okeyi ele alma."""
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not p.opened:return ActionResult(False,'must_open_first')
        tile=next((t for t in p.hand if t.id==tile_id),None)
        meld=next((m for m in self.state.melds if m.id==meld_id),None)
        if not tile or not meld:return ActionResult(False,'missing_tile_or_meld')
        # A tile taken from the left discard is a turn obligation: the first
        # table move must consume that exact physical tile. Do not let a client
        # process another rack tile first and keep the left tile pending.
        if p.pending_left_tile_id and p.pending_left_tile_id!=tile_id:
            return ActionResult(False,'must_use_left_tile')
        if self.rules._is_joker(tile):return ActionResult(False,'cannot_replace_okey_with_okey')
        joker_positions=[i for i,t in enumerate(meld.tiles) if self.rules._is_joker(t)]
        if not joker_positions:return ActionResult(False,'no_okey_on_meld')
        for i in joker_positions:
            candidate=list(meld.tiles);reclaimed=candidate[i];candidate[i]=tile
            vr=self.rules.validate_meld(candidate)
            # Gruplarda okey ancak dört renk tamamlanınca alınır (ör. 12'lerde okey varsa grup 4'lü olmalı).
            if meld.meld_type==MeldType.SET and len(candidate)<4:continue
            if vr.valid and (vr.meld_type==meld.meld_type or meld.meld_type in (MeldType.RUN,MeldType.SET)):
                # Sıra korunur: taş tam okeyin bulunduğu yuvaya girer.
                self._begin_table_transaction(p)
                meld.tiles=self.rules.canonical_meld_order(candidate,meld.meld_type)
                p.hand=[t for t in p.hand if t.id!=tile_id]
                p.hand.append(reclaimed)
                self._clear_left_if_used(p,{tile_id})
                p.last_layoff=None
                p.last_open_batch=None
                # Okeyi yere koyan rakip 101 ceza yer (kendi ya da eşinin okeyi cezasız).
                owner=getattr(meld,'owner_seat',None)
                penalized=None
                if owner is not None and owner!=seat and not self._same_team(owner,seat):
                    self.state.player(owner).penalty+=101;penalized=owner
                return ActionResult(True,'okey_reclaimed',{'reclaimed_okey_id':reclaimed.id,'meld_id':meld_id,'replacement_tile_id':tile_id,'position':i,'penalized_seat':penalized})
        return ActionResult(False,'tile_does_not_replace_okey')

    def _pair_area_open(self)->bool:
        return any(m.meld_type==MeldType.PAIR for m in self.state.melds)

    def _find_exact_pair_mate(self,p:PlayerState,tile:Tile)->Tile|None:
        for other in p.hand:
            if other.id==tile.id:continue
            if self.rules.validate_pair([tile,other]).valid:return other
        return None

    def _matching_open_pair(self,tile:Tile)->Meld|None:
        """Return an already-open pair that accepts this exact tile.

        OkeyX treats a tile matching an exposed pair as an işler taşı. This is
        intentionally separate from opening a brand-new pair from two rack
        tiles.
        """
        # Gerçek okey açık çift şeridini büyütemez (jokerli çift yalnız iki
        # taştır). Sonuç şeridin kurallara uygun kalacağı da önceden doğrulanır;
        # aksi hâlde masa geçersiz duruma düşüp sonraki her hamle reddediliyordu.
        if self.rules._is_joker(tile):return None
        nt=self.rules._norm(tile)
        if nt.color is None or nt.number is None:return None
        for meld in self.state.melds:
            if meld.meld_type!=MeldType.PAIR or not meld.tiles:continue
            if any(self.rules._is_joker(t) for t in meld.tiles):continue
            base=self.rules._norm(meld.tiles[0])
            if base.color==nt.color and base.number==nt.number:
                if self.rules.validate_pair(list(meld.tiles)+[tile]).valid:return meld
        return None

    def is_useful_table_tile(self,p:PlayerState,tile:Tile)->bool:
        """Return True only when *this exact rack tile* can be used on the table.

        The red dot is a table-layoff hint/penalty marker, not a generic
        "this tile participates in something in your hand" helper.  In the
        previous build, merely owning the mate of a pair caused both tiles to
        be marked whenever any pair lane existed; on pair-heavy tables that
        could make almost the whole rack look like an işler taşı.
        """
        if self.rules._is_joker(tile):
            return True
        # A third matching tile can be processed onto an already exposed pair.
        if self._matching_open_pair(tile) is not None:
            return True
        for meld in self.state.melds:
            if meld.meld_type==MeldType.PAIR:
                continue
            # Normal legal layoff.
            if self.rules.can_layoff(meld,tile)[0]:
                return True
            # Replacing a real okey already sitting inside an exposed meld is
            # also a real table-processing move.  Check it without mutating.
            if not self.rules._is_joker(tile) and any(self.rules._is_joker(x) for x in meld.tiles):
                for i,current in enumerate(meld.tiles):
                    if not self.rules._is_joker(current):
                        continue
                    candidate=list(meld.tiles);candidate[i]=tile
                    vr=self.rules.validate_meld(candidate)
                    if vr.valid and (vr.meld_type==meld.meld_type or meld.meld_type in (MeldType.RUN,MeldType.SET)):
                        return True
        return False

    def can_auto_layoff(self,seat:int)->bool:
        """Return exactly whether TAŞLARI İŞLE can make at least one move.

        This mirrors auto_layoff without mutating the table, including the
        special case where a real okey on a meld can be reclaimed.
        """
        p=self.state.player(seat)
        if not p.opened or len(p.hand)<=1:return False
        for tile in p.hand:
            if self._matching_open_pair(tile) is not None:return True
            if self._pair_area_open() and self._find_exact_pair_mate(p,tile) is not None:return True
            for meld in self.state.melds:
                if meld.meld_type==MeldType.PAIR:continue
                if any(self.rules._is_joker(x) for x in meld.tiles) and not self.rules._is_joker(tile):
                    for i,current in enumerate(meld.tiles):
                        if not self.rules._is_joker(current):continue
                        candidate=list(meld.tiles);candidate[i]=tile
                        vr=self.rules.validate_meld(candidate)
                        if vr.valid and (vr.meld_type==meld.meld_type or meld.meld_type in (MeldType.RUN,MeldType.SET)):
                            return True
                if self.rules.can_layoff(meld,tile)[0]:return True
        return False

    def layoff_pair(self,seat:int,tile_id:str)->ActionResult:
        """Masada çift alanı açıksa eldeki TAM çifti çift alanına işler."""
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not p.opened:return ActionResult(False,'must_open_first')
        if not self._pair_area_open():return ActionResult(False,'pair_area_not_open')
        tile=next((t for t in p.hand if t.id==tile_id),None)
        if not tile:return ActionResult(False,'tile_not_in_hand')
        existing=self._matching_open_pair(tile)
        if existing is not None:
            if len(p.hand)<=1:return ActionResult(False,'must_keep_finish_tile')
            if p.pending_left_tile_id and p.pending_left_tile_id!=tile.id:
                return ActionResult(False,'must_use_left_tile')
            self._begin_table_transaction(p)
            existing.tiles.append(tile);p.hand.remove(tile);p.last_layoff=(tile.id,existing.id)
            self._clear_left_if_used(p,{tile.id});self._apply_turbo(tile)
            return ActionResult(True,'pair_tile_processed',{'tile_ids':[tile.id],'meld_id':existing.id})
        mate=self._find_exact_pair_mate(p,tile)
        if not mate:return ActionResult(False,'no_matching_pair')
        if len(p.hand)<=2:return ActionResult(False,'must_keep_finish_tile')
        if p.pending_left_tile_id and p.pending_left_tile_id not in {tile.id,mate.id}:
            return ActionResult(False,'must_use_left_tile')
        self._begin_table_transaction(p)
        p.hand=[t for t in p.hand if t.id not in {tile.id,mate.id}]
        self.state.melds.append(Meld(
            f'{seat}-pair-layoff-{len(self.state.melds)}',
            seat,MeldType.PAIR,[tile,mate]
        ))
        self._clear_left_if_used(p,{tile.id,mate.id})
        p.last_layoff=None
        return ActionResult(True,'pair_processed',{'tile_ids':[tile.id,mate.id]})

    def layoff(self,seat:int,tile_id:str,meld_id:str)->ActionResult:
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not p.opened:return ActionResult(False,'must_open_first')
        if len(p.hand)<=1:return ActionResult(False,'must_keep_finish_tile')
        tile=next((t for t in p.hand if t.id==tile_id),None); meld=next((m for m in self.state.melds if m.id==meld_id),None)
        if not tile or not meld:return ActionResult(False,'missing_tile_or_meld')
        if p.pending_left_tile_id and p.pending_left_tile_id!=tile_id:
            return ActionResult(False,'must_use_left_tile')
        if meld.meld_type==MeldType.PAIR:return self.layoff_pair(seat,tile_id)
        # Önce masadaki gerçek okeyi bu taşla değiştirip okeyi alma ihtimalini dene.
        if any(self.rules._is_joker(x) for x in meld.tiles):
            swap=self.replace_table_okey(seat,tile_id,meld_id)
            if swap.ok:return swap
        ok,newtiles=self.rules.can_layoff(meld,tile)
        if not ok:return ActionResult(False,'illegal_layoff')
        # Normal işleme için de kullanıcının mevcut masa sırasını mümkün olduğunca koru.
        # can_layoff sonucu valid sırayı verir.
        self._begin_table_transaction(p)
        meld.tiles=self.rules.canonical_meld_order(newtiles,meld.meld_type);p.hand=[t for t in p.hand if t.id!=tile_id]
        p.last_layoff=(tile_id,meld_id)
        self._clear_left_if_used(p,{tile_id})
        self._apply_turbo(tile)
        return ActionResult(True)

    def auto_layoff(self,seat:int,max_moves:int|None=None)->ActionResult:
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not p.opened:return ActionResult(False,'must_open_first')
        count=0
        # A left-discard pickup is not just a hint: it is a hard obligation.
        # While it is pending, auto-process may try ONLY that exact tile. Once
        # it has legally reached the table, the remaining rack may be processed.
        progress=True
        while progress and len(p.hand)>1 and (max_moves is None or count<max_moves):
            progress=False
            pending=p.pending_left_tile_id
            current=list(p.hand)
            if pending:
                current=[t for t in current if t.id==pending]
                if not current:
                    return ActionResult(False,'left_tile_missing_from_hand')
            for tile in current:
                pair_move=self.layoff_pair(seat,tile.id) if self._matching_open_pair(tile) is not None else None
                if pair_move is not None and pair_move.ok:
                    count+=1;progress=True;break
                for meld in self.state.melds:
                    if meld.meld_type==MeldType.PAIR:continue
                    if any(self.rules._is_joker(x) for x in meld.tiles):
                        swap=self.replace_table_okey(seat,tile.id,meld.id)
                        if swap.ok:
                            count+=1;progress=True;break
                    ok,newtiles=self.rules.can_layoff(meld,tile)
                    if ok:
                        self._begin_table_transaction(p)
                        meld.tiles=self.rules.canonical_meld_order(newtiles,meld.meld_type);p.hand.remove(tile);p.last_layoff=(tile.id,meld.id);self._clear_left_if_used(p,{tile.id});self._apply_turbo(tile);count+=1;progress=True;break
                if progress:break
            # If the mandatory left tile cannot be used, do not touch any other
            # tile. The player can still use GERI BIRAK to return it.
            if pending and not progress:
                break
        return ActionResult(True,payload={'processed':count,'left_obligation_cleared':p.pending_left_tile_id is None})

    def undo_last_layoff(self,seat:int)->ActionResult:
        self._assert_turn(seat)
        p=self.state.player(seat)
        if not p.last_layoff:return ActionResult(False,'no_layoff_to_undo')
        tile_id,meld_id=p.last_layoff
        meld=next((m for m in self.state.melds if m.id==meld_id),None)
        if not meld:return ActionResult(False,'meld_not_found')
        tile=next((t for t in meld.tiles if t.id==tile_id),None)
        if not tile:return ActionResult(False,'layoff_tile_not_found')
        candidate=[t for t in meld.tiles if t.id!=tile_id]
        vr=self.rules.validate_meld(candidate)
        if not vr.valid:return ActionResult(False,'cannot_undo_breaks_meld')
        meld.tiles=self.rules.canonical_meld_order(candidate,meld.meld_type)
        p.hand.append(tile);p.last_layoff=None
        return ActionResult(True,payload={'tile_id':tile_id,'meld_id':meld_id})

    def discard(self,seat:int,tile_id:str)->ActionResult:
        self._assert_turn(seat);p=self.state.player(seat);tile=next((t for t in p.hand if t.id==tile_id),None)
        if not tile:return ActionResult(False,'tile_not_in_hand')
        if p.pending_left_tile_id:return ActionResult(False,'must_use_left_tile_first')
        penalty=0
        is_finish_discard=(len(p.hand)==1)
        # Gerçek okey tek bir +101 okey cezasıdır; aynı taş bir pere uyuyor diye
        # ikinci kez "işler taş" cezası yazılmaz.
        useful_discard=(not is_finish_discard and not self.rules._is_joker(tile) and self.is_useful_table_tile(p,tile))
        okey_discard=(not is_finish_discard and self.rules._is_joker(tile))
        if useful_discard:
            penalty+=101;p.penalty+=101
        if okey_discard:
            penalty+=101;p.penalty+=101
        p.hand.remove(tile);p.last_layoff=None;p.last_open_batch=None;p.turn_table_snapshot=None;self.state.discard_piles[seat].append(tile);self.state.current_seat=(seat+1)%4
        return ActionResult(True,payload={'penalty':penalty,'useful_discard':useful_discard,'okey_discard':okey_discard})

    def _apply_turbo(self,tile):
        """Count a physical turbo-star tile once when it is committed to a meld.

        Turbo is additive: x1 base + one multiplier step per unique star tile.
        A star is any colour of the indicator+1 number, the real okey, or the
        fake okey. The authoritative full-table recalculation in Room uses the
        same rule after each accepted action.
        """
        if not self.state.turbo:
            return
        is_star = (
            self.rules._is_joker(tile)
            or self.rules.is_fake_okey(tile)
            or int(self.rules._norm(tile).number or 0) == int(self.state.multiplier_tile_number or 0)
        )
        if not is_star:
            return
        committed=set(self.state.turbo_committed_star_ids or [])
        if tile.id in committed:
            return
        committed.add(tile.id)
        self.state.turbo_committed_star_ids=sorted(committed)
        self.state.turbo_stars_on_table=len(committed)
        self.state.multiplier=1 + len(committed)
