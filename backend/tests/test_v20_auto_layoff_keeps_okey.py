import inspect

from app.services.game_service import GameService


def test_auto_layoff_never_places_hand_joker():
    assert '_is_joker(tile) and tile.id!=pending' in inspect.getsource(GameService.auto_layoff)
    assert 'if self.rules._is_joker(tile):continue' in inspect.getsource(GameService.can_auto_layoff)
