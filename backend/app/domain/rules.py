from __future__ import annotations
from dataclasses import dataclass
from itertools import combinations
from typing import Iterable, Sequence
from .models import Tile, JokerContext, MeldType, Meld, Color

class RuleError(ValueError): pass

@dataclass(frozen=True, slots=True)
class ValidationResult:
    valid: bool
    score: int=0
    reason: str=''
    meld_type: MeldType | None=None

class Rules101:
    """Canonical OkeyX 101 rules.

    Important locked choices:
    - run cannot wrap: 12-13-1 is INVALID.
    - opening by series/sets requires >=101 points.
    - pair opening requires >=5 exact pairs (same color+number).
    - a pair-opener cannot later open a new run/set, but can lay off onto existing melds.
    - only players who have opened may lay off.
    """
    def __init__(self, joker: JokerContext): self.joker = joker

    def __getstate__(self):
        # Önbellek kalıcı oda görüntüsüne (pickle) girmesin.
        return {'joker': self.joker}

    def __setstate__(self, state):
        self.joker = state['joker']

    def _norm(self, t:Tile)->Tile: return self.joker.normalized(t)
    def _is_joker(self,t:Tile)->bool: return self.joker.is_real_joker(t)
    def is_fake_okey(self,t:Tile)->bool: return bool(t.fake_joker)
    def represented(self,t:Tile)->Tile:
        # Gerçek okey wildcard'dır. Sahte okey wildcard DEĞİLDİR;
        # sabit olarak gerçek okeyin renk/sayı yüzünü temsil eder.
        return self._norm(t)

    def validate_set(self, tiles: Sequence[Tile]) -> ValidationResult:
        if len(tiles) not in (3,4): return ValidationResult(False, reason='set_size')
        non_j = [self._norm(t) for t in tiles if not self._is_joker(t)]
        if not non_j: return ValidationResult(False, reason='all_jokers')
        nums={t.number for t in non_j}; colors=[t.color for t in non_j]
        if len(nums)!=1: return ValidationResult(False, reason='set_number_mismatch')
        if len(set(colors))!=len(colors): return ValidationResult(False, reason='set_duplicate_color')
        n=next(iter(nums)); score=int(n or 0)*len(tiles)
        return ValidationResult(True, score, meld_type=MeldType.SET)

    def validate_run(self, tiles: Sequence[Tile]) -> ValidationResult:
        if len(tiles)<3: return ValidationResult(False, reason='run_size')
        non_j=[self._norm(t) for t in tiles if not self._is_joker(t)]
        if not non_j: return ValidationResult(False, reason='all_jokers')
        if len({t.color for t in non_j})!=1: return ValidationResult(False, reason='run_color_mismatch')
        nums=sorted(int(t.number) for t in non_j if t.number is not None)
        if len(nums)!=len(set(nums)): return ValidationResult(False, reason='run_duplicate_number')
        jokers=len(tiles)-len(non_j)
        # Find a non-wrapping consecutive window inside 1..13 that can host all natural tiles + jokers.
        L=len(tiles)
        candidates=[]
        for start in range(1, 15-L):
            seq=list(range(start,start+L))
            if all(n in seq for n in nums) and len(set(seq)-set(nums))==jokers:
                candidates.append(seq)
        if not candidates: return ValidationResult(False, reason='run_not_consecutive')
        # A real okey can legally sit on more than one edge. Automatic opening
        # and its preview must use the highest legal represented sequence.
        seq=max(candidates,key=sum)
        return ValidationResult(True, sum(seq), meld_type=MeldType.RUN)

    def validate_pair(self, tiles: Sequence[Tile])->ValidationResult:
        if len(tiles)<2: return ValidationResult(False, reason='pair_size')
        # Açılışta çift her zaman iki taştır. Masadaki açık çifte daha sonra aynı
        # taşın işlenebilmesi için pair lane 3+ birebir aynı doğal taşı da kabul
        # eder. Jokerli çift genişletilmez; joker yalnız iki taşlık çiftte eksik
        # eşin yerine geçebilir.
        if len(tiles)>2:
            if any(self._is_joker(t) for t in tiles):return ValidationResult(False, reason='pair_mismatch')
            norms=[self._norm(t) for t in tiles]
            first=norms[0]
            ok=all(n.color==first.color and n.number==first.number for n in norms[1:])
            score=sum(n.face_value for n in norms) if ok else 0
            return ValidationResult(ok, score, reason='' if ok else 'pair_mismatch', meld_type=MeldType.PAIR if ok else None)
        a,b=tiles
        # 101 çift oyununda gerçek okey eksik eşin yerine kullanılabilir. Sahte
        # okey wildcard değildir; normalize edilen gerçek renk/sayısıyla eşleşir.
        na,nb=self._norm(a),self._norm(b)
        if self._is_joker(a) or self._is_joker(b):
            ok=True
        else:
            ok=na.color==nb.color and na.number==nb.number
        if ok and self._is_joker(a) != self._is_joker(b):
            natural=nb if self._is_joker(a) else na
            score=natural.face_value*2
        else:
            score=na.face_value+nb.face_value if ok else 0
        return ValidationResult(ok, score, reason='' if ok else 'pair_mismatch', meld_type=MeldType.PAIR if ok else None)

    def validate_meld(self, tiles: Sequence[Tile])->ValidationResult:
        # Taş kimliği renk/sayıyı, okey bağlamı da bu kural nesnesini sabitler;
        # aynı dizilimin sonucu değişmez. Çözücü aynı grupları binlerce kez
        # sorduğu için sonuçlar önbelleğe alınır (sonuç nesnesi değişmezdir).
        cache=self.__dict__.setdefault('_meld_cache',{})
        key=tuple(t.id for t in tiles)
        hit=cache.get(key)
        if hit is not None: return hit
        candidates=[self.validate_set(tiles), self.validate_run(tiles)]
        valid=[x for x in candidates if x.valid]
        out=ValidationResult(False, reason='invalid_meld') if not valid else max(valid, key=lambda x:x.score)
        if len(cache)>50000: cache.clear()
        cache[key]=out
        return out

    def opening_score(self, groups: Sequence[Sequence[Tile]])->int:
        total=0
        for g in groups:
            r=self.validate_meld(g)
            if not r.valid: raise RuleError(r.reason)
            total+=r.score
        return total

    def validate_series_opening(self, groups: Sequence[Sequence[Tile]], minimum:int=101)->ValidationResult:
        try: score=self.opening_score(groups)
        except RuleError as e: return ValidationResult(False, reason=str(e))
        return ValidationResult(score>=minimum, score, '' if score>=minimum else 'below_opening_threshold')

    def validate_pair_opening(self, pairs: Sequence[Sequence[Tile]], minimum_pairs:int=5)->ValidationResult:
        if len(pairs)<minimum_pairs: return ValidationResult(False, reason='not_enough_pairs')
        if any(len(pair)!=2 for pair in pairs): return ValidationResult(False, reason='pair_size')
        score=0
        for p in pairs:
            r=self.validate_pair(p)
            if not r.valid:return ValidationResult(False, reason=r.reason)
            score+=r.score
        return ValidationResult(True, score, meld_type=MeldType.PAIR)

    def can_layoff(self, meld: Meld, tile: Tile)->tuple[bool,list[Tile]]:
        # Try every insertion position; server returns canonical order.
        for i in range(len(meld.tiles)+1):
            candidate=meld.tiles[:i]+[tile]+meld.tiles[i:]
            if meld.meld_type==MeldType.RUN:
                r=self.validate_run(candidate)
            elif meld.meld_type==MeldType.SET:
                r=self.validate_set(candidate)
            else:
                r=self.validate_pair(candidate)
            if r.valid:
                return True,self.canonical_meld_order(candidate,meld.meld_type)
        return False,meld.tiles


    def canonical_meld_order(self, tiles: Sequence[Tile], meld_type: MeldType)->list[Tile]:
        """Canonical visual/logic order for a valid meld."""
        arr=list(tiles)
        if meld_type==MeldType.SET:
            order={Color.RED:0,Color.YELLOW:1,Color.BLACK:2,Color.BLUE:3}
            return sorted(arr,key=lambda t:(9 if self._is_joker(t) else order.get(self._norm(t).color,8), t.id))
        if meld_type!=MeldType.RUN:
            return arr
        natural=[t for t in arr if not self._is_joker(t)]
        jokers=[t for t in arr if self._is_joker(t)]
        nums={int(self._norm(t).number or 0):t for t in natural}
        L=len(arr)
        candidates=[]
        for start in range(1, 15-L):
            seq=list(range(start,start+L))
            missing=[n for n in seq if n not in nums]
            if all(n in seq for n in nums) and len(missing)==len(jokers):candidates.append(seq)
        if candidates:
            seq=max(candidates,key=sum);ji=iter(jokers)
            return [nums[n] if n in nums else next(ji) for n in seq]
        return sorted(arr,key=lambda t:(99 if self._is_joker(t) else int(self._norm(t).number or 0),t.id))

    def find_all_legal_layoffs(self, hand: Sequence[Tile], melds: Sequence[Meld])->list[tuple[str,str,list[Tile]]]:
        # deterministic greedy plan used by AUTO-İŞLE; backend still validates each commit.
        remaining=list(hand); plan=[]
        for tile in list(remaining):
            for meld in melds:
                ok,new_tiles=self.can_layoff(meld,tile)
                if ok:
                    plan.append((tile.id,meld.id,new_tiles)); remaining.remove(tile); meld=Meld(meld.id,meld.owner_seat,meld.meld_type,new_tiles); break
        return plan

    def is_useful_discard(self, tile:Tile, melds:Sequence[Meld])->bool:
        return any(self.can_layoff(m,tile)[0] for m in melds)

class RulesNormalOkey:
    def __init__(self,joker:JokerContext): self.base=Rules101(joker)
    def is_winning_hand(self, tiles:Sequence[Tile])->bool:
        # 14 tiles must partition completely into valid runs/sets, or 7 exact pairs.
        if len(tiles)!=14:return False
        # exact 7-pair path
        unused=list(tiles); pairs=0
        while unused:
            a=unused.pop(0); found=None
            for i,b in enumerate(unused):
                if self.base.validate_pair([a,b]).valid: found=i; break
            if found is None: break
            unused.pop(found); pairs+=1
        if pairs==7 and not unused:return True
        # exhaustive memoized partition search
        ids={t.id:t for t in tiles}
        from functools import lru_cache
        @lru_cache(None)
        def rec(rem:tuple[str,...])->bool:
            if not rem:return True
            arr=[ids[x] for x in rem]; first=arr[0]
            for size in (3,4,5,6,7,8,9,10,11,12,13):
                if size>len(arr):break
                for combo in combinations(arr[1:],size-1):
                    group=(first,)+combo
                    if self.base.validate_meld(group).valid:
                        used={t.id for t in group}; nr=tuple(x for x in rem if x not in used)
                        if rec(nr):return True
            return False
        return rec(tuple(t.id for t in tiles))


class NormalOkeyScoring:
    """Altınstar Düz Okey puan sözleşmesi.
    Normal bitiş: diğer oyunculardan -2.
    Çift veya okey ile bitiş: diğer oyunculardan -4.
    Yanlış bitiş / okey atma: -2 ceza.
    """
    @staticmethod
    def win_delta(*, pair_finish:bool=False, okey_finish:bool=False)->int:
        return -4 if (pair_finish or okey_finish) else -2

    @staticmethod
    def invalid_finish_penalty()->int: return -2

    @staticmethod
    def discarded_okey_penalty()->int: return -2
