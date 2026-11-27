from app.services.selftest import run_games, play_one, _CONFIGS


def test_selftest_bot_games_all_finish():
    r = run_games(24, time_budget_s=60, seed_base=892000)
    assert r['played'] == 24 and r['failed'] == 0, r['failures']


def test_klasik_bots_do_not_loop_on_left_tile():
    # Bu tohum önceden botların sonsuza dek soldan alıp attığı eli üretiyordu.
    assert play_one(892296, _CONFIGS[2])['ok'] is True
