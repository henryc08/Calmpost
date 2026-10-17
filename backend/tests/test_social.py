"""Multi-client tests against isolated Postgres, never production data."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import pytest
from .conftest import needs_db, run_sql, ingest_series
pytestmark = needs_db


def account(c, handle):
    r = c.post('/social/register', json={'handle':handle,'password':'compost-test-password','display_name':handle.title()})
    assert r.status_code == 201, r.text
    return r.json()['user_id'], {'Authorization':'Bearer '+r.json()['token']}


def test_identity_sessions_and_legacy_impersonation(c):
    alice,a=account(c,'alice'); bob,b=account(c,'bob')
    assert c.get('/social/me').status_code==401
    assert c.get('/social/me',headers=a).json()['handle']=='alice'
    assert c.post('/social/register',json={'handle':'ALICE','password':'compost-test-password','display_name':'other'}).status_code==409
    assert c.post('/social/login',json={'handle':'alice','password':'wrong-password'}).status_code==401
    login=c.post('/social/login',json={'handle':'ALICE','password':'compost-test-password'})
    assert login.status_code==200
    assert c.post(f'/users/{alice}/check-in').status_code==403
    assert c.post(f'/users/{alice}/check-in',headers=b).status_code==403
    assert c.get(f'/users/{alice}/game').status_code==403
    assert c.post('/social/logout',headers=a).status_code==200
    assert c.get('/social/me',headers=a).status_code==401
    assert c.get('/social/me',headers={'Authorization':'Bearer '+login.json()['token']}).status_code==200


def test_private_follows_feed_and_revocation(c):
    alice,a=account(c,'alice'); bob,b=account(c,'bob')
    c.post('/social/check-in',headers=a)
    p=c.get(f'/social/people/{alice}',headers=b).json()
    assert not p['can_view'] and 'progress' not in p
    assert c.get('/social/feed',params={'target':alice},headers=b).status_code==403
    assert c.post(f'/social/people/{alice}/follow',headers=b).json()['relationship']=='requested'
    assert c.get('/social/feed',headers=b).json()==[]
    assert c.get('/social/connections',headers=a).json()[0]['incoming']
    c.post(f'/social/requests/{bob}',headers=a,json={'accept':True})
    assert c.get(f'/social/people/{alice}',headers=b).json()['progress']['total_xp']==5
    event=c.get('/social/feed',headers=b).json()[0]
    for _ in range(2): assert c.post(f"/social/events/{event['id']}/cheer",headers=b).status_code==200
    assert c.get('/social/feed',headers=b).json()[0]['cheers']==1
    c.delete(f'/social/followers/{bob}',headers=a)
    assert c.get('/social/feed',headers=b).json()==[]
    assert c.post(f"/social/events/{event['id']}/cheer",headers=b).status_code==404
    assert c.post(f'/social/people/{alice}/follow',headers=a).status_code==400


def test_friend_invites_rotate_and_expire(c):
    alice,a=account(c,'alice'); bob,b=account(c,'bob')
    old=c.post('/social/invites',headers=a).json()['code']
    code=c.post('/social/invites',headers=a).json()['code']
    assert c.post('/social/join',headers=b,json={'code':old}).status_code==404
    for _ in range(2): assert c.post('/social/join',headers=b,json={'code':code}).status_code==200
    assert c.get(f'/social/people/{bob}',headers=a).json()['relationship']=='following'
    assert c.get(f'/social/people/{alice}',headers=b).json()['relationship']=='following'
    c.portal.call(run_sql,"UPDATE social_invites SET expires_at=now()-interval '1 day'")
    assert c.post('/social/join',headers=b,json={'code':code}).status_code==404


def test_private_group_permissions_ties_and_care_scores(c):
    alice,a=account(c,'alice'); bob,b=account(c,'bob'); eve,e=account(c,'eve')
    cid=c.post('/social/circles',headers=a,json={'name':'Garden crew'}).json()['id']
    assert c.get(f'/social/circles/{cid}',headers=b).status_code==404
    code=c.post(f'/social/circles/{cid}/invite',headers=a).json()['code']
    for _ in range(2): c.post('/social/join',headers=b,json={'code':code})
    assert c.post(f'/social/circles/{cid}/invite',headers=b).status_code==403
    c.post('/social/check-in',headers=a);c.post('/social/check-in',headers=b)
    board=c.get(f'/social/circles/{cid}',headers=a).json()
    assert len(board['members'])==2 and [p['rank'] for p in board['members']]==[1,1]
    assert board['team_xp']==10
    assert not c.get(f'/social/people/{alice}',headers=b).json()['can_view']
    assert c.delete(f'/social/circles/{cid}/members/{alice}',headers=b).status_code==400
    assert c.delete(f'/social/circles/{cid}',headers=b).status_code==403
    assert c.get(f'/social/circles/{cid}',headers=e).status_code==404
    c.delete(f'/social/circles/{cid}/members/{bob}',headers=a)
    assert c.get(f'/social/circles/{cid}',headers=b).status_code==404
    assert c.post('/social/join',headers=b,json={'code':code}).status_code==404
    assert c.delete(f'/social/circles/{cid}',headers=a).status_code==200


def test_check_in_idempotent_concurrent_and_week_reset(c):
    alice,a=account(c,'alice')
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses=list(pool.map(lambda _:c.post('/social/check-in',headers=a),range(4)))
    assert all(r.status_code==200 for r in responses)
    assert sum(r.json()['xp_awarded'] for r in responses)==5
    assert c.post('/social/check-in',headers=a,json={'xp':9999}).json()['xp_awarded']==0
    c.portal.call(run_sql,"INSERT INTO point_events(time,user_id,kind,xp) VALUES($1,$2,'check_in',50)",datetime.now(timezone.utc)-timedelta(days=9),alice)
    p=c.get('/social/me',headers=a).json()['progress']
    assert p['total_xp']==55 and p['week_xp']==5
    cid=c.post('/social/circles',headers=a,json={'name':'Test'}).json()['id']
    assert c.get(f'/social/circles/{cid}?period=all',headers=a).json()['team_xp']==55
    assert c.get(f'/social/circles/{cid}',headers=a).json()['team_xp']==5


def test_pairing_and_care_log_are_account_scoped(c):
    alice,a=account(c,'alice'); bob,b=account(c,'bob')
    assert c.post('/social/bin',headers=a,json={'device_token':'incorrect-token'}).status_code==404
    assert c.post('/social/bin',headers=a,json={'device_token':c.device_token}).status_code==200
    assert c.post('/social/bin',headers=b,json={'device_token':c.device_token}).status_code==409
    assert c.get('/bins/bin-001/live',headers=b).status_code==403
    assert c.get('/bins/bin-001/live').status_code==403
    assert c.post('/bins',json={'bin_id':'bin-001','owner_id':'demo-user'}).status_code==403
    assert c.get('/bins').json()==[]
    ingest_series(c,moisture_raw=380,probe_temp=30,co2=900)
    assert c.get('/bins/bin-001/live',headers=a).status_code==200
    payload={'catalog_id':'cardboard','action':'added','request_id':'test-care-log-001'}
    r=c.post('/social/care-log',headers=a,json=payload)
    assert r.status_code==200,r.text
    assert r.json()['xp_awarded']==17  # 40 g volume plus following advice
    assert c.post('/social/care-log',headers=a,json=payload).json()['duplicate']
    assert c.post('/social/care-log',headers=b,json=payload).status_code==409
    assert c.get('/social/me',headers=a).json()['progress']['total_xp']==17
    assert c.post('/social/care-log',headers=a,json={**payload,'xp':9999}).status_code==422


def test_public_profile_and_input_validation(c):
    alice,a=account(c,'alice');bob,b=account(c,'bob')
    c.patch('/social/me',headers=a,json={'display_name':'Alice','bio':'Balcony composter','is_private':False})
    assert c.get(f'/social/people/{alice}',headers=b).json()['can_view']
    assert c.post(f'/social/people/{alice}/follow',headers=b).json()['relationship']=='following'
    assert c.get('/social/people?q=al',headers=b).json()[0]['user_id']==alice
    assert c.post('/social/circles',headers=a,json={'name':'  '}).status_code==422
    assert c.post('/social/register',json={'handle':'bad!','password':'short','display_name':'Bad'}).status_code==422



def test_removed_follower_cannot_reuse_old_friend_invitation(c):
    alice, a = account(c, 'alice')
    bob, b = account(c, 'bob')
    code = c.post('/social/invites', headers=a).json()['code']
    c.post('/social/join', headers=b, json={'code': code})
    c.delete(f'/social/followers/{bob}', headers=a)
    assert c.post('/social/join', headers=b, json={'code': code}).status_code == 404
    assert not c.get(f'/social/people/{alice}', headers=b).json()['can_view']


def test_expired_sessions_and_declined_requests(c):
    alice, a = account(c, 'alice')
    bob, b = account(c, 'bob')
    c.post(f'/social/people/{alice}/follow', headers=b)
    c.post(f'/social/requests/{bob}', headers=a, json={'accept': False})
    assert c.get(f'/social/people/{alice}', headers=b).json()['relationship'] == 'none'
    c.portal.call(run_sql, "UPDATE social_sessions SET expires_at=now()-interval '1 second' WHERE user_id=$1", bob)
    assert c.get('/social/me', headers=b).status_code == 401


def test_sensorless_care_logs_work_but_demo_routes_cannot_award_player_xp(c):
    alice, a = account(c, 'alice')
    c.post('/social/bin', headers=a, json={'device_token': c.device_token})
    payload = {'catalog_id': 'cardboard', 'action': 'added', 'request_id': 'stale-test-12345'}
    advice = c.post('/bins/bin-001/advice/check', headers=a, json={'item': 'Cardboard'})
    assert advice.status_code == 200, advice.text
    assert advice.json()['verdict'] == 'careful'
    assert advice.json()['input_snapshot']['measured_at'] is None
    assert not advice.json()['input_snapshot']['layers']['top']['measured']
    saved = c.post('/social/care-log', headers=a, json=payload)
    assert saved.status_code == 200, saved.text
    assert saved.json() == {'xp_awarded': 2, 'duplicate': False}
    ingest_series(c, moisture_raw=380, probe_temp=30, co2=900)
    assert c.post('/bins/bin-001/logs', headers=a, json={'item':'cardboard','category':'brown','was_advised':True}).status_code == 403
    assert c.post('/bins/bin-001/harvest', headers=a, json={'layer': 'top', 'yield_g': 1000}).status_code == 403
    assert c.get(f'/users/{alice}/game').status_code == 403  # shared key cannot read players
    assert c.post('/quests/checkin/claim', headers=a, params={'user_id': alice}).status_code == 409
    c.portal.call(run_sql, "UPDATE readings SET time=time-interval '1 day'")
    assert c.post('/social/care-log', headers=a, json=payload).json() == {'xp_awarded': 2, 'duplicate': True}
    stale = c.post('/social/care-log', headers=a, json={**payload, 'request_id': 'stale-new-12345'})
    assert stale.status_code == 200, stale.text
    assert stale.json()['xp_awarded'] == 2  # volume only, no +15 care bonus
    assert c.get('/social/me', headers=a).json()['progress']['total_xp'] == 4


def test_sensorless_advice_keeps_harmful_items_out(c):
    _, headers = account(c, 'sensorless')
    c.post('/social/bin', headers=headers, json={'device_token': c.device_token})
    advice = c.post('/bins/bin-001/advice/check', headers=headers, json={'item': 'Meat'})
    assert advice.status_code == 200, advice.text
    assert advice.json()['verdict'] == 'avoid'
    assert not advice.json()['bottom_ready']
    whole = c.get('/bins/bin-001/advice', headers=headers)
    assert whole.status_code == 200, whole.text
    assert whole.json()['suggest_add'] == []
    assert whole.json()['verdict'] == 'careful'
    assert 'unavailable' in whole.json()['reason']
    assert c.post('/bins/missing/advice/check', json={'item': 'Cardboard'}).status_code == 404


def test_concurrent_pairing_cannot_claim_two_bins(c):
    alice, a = account(c, 'alice')
    second = c.post('/bins', json={'bin_id': 'bin-002', 'owner_id': 'demo-user'}).json()['device_token']
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda token: c.post('/social/bin', headers=a, json={'device_token': token}), [c.device_token, second]))
    assert sorted(r.status_code for r in responses) == [200, 409]


def test_concurrent_invites_and_removal_do_not_restore_revoked_access(c):
    alice, a = account(c, 'alice')
    bob, b = account(c, 'bob')
    acode = c.post('/social/invites', headers=a).json()['code']
    bcode = c.post('/social/invites', headers=b).json()['code']
    with ThreadPoolExecutor(max_workers=2) as pool:
        requests = [(a, bcode), (b, acode)]
        replies = list(pool.map(lambda args: c.post('/social/join', headers=args[0], json={'code': args[1]}), requests))
    assert all(r.status_code == 200 for r in replies)
    cid = c.post('/social/circles', headers=a, json={'name': 'Concurrent crew'}).json()['id']
    code = c.post(f'/social/circles/{cid}/invite', headers=a).json()['code']
    def act(i):
        if i % 2:
            return c.delete(f'/social/circles/{cid}/members/{bob}', headers=a)
        return c.post('/social/join', headers=b, json={'code': code})
    with ThreadPoolExecutor(max_workers=4) as pool:
        replies = list(pool.map(act, range(12)))
    assert all(r.status_code in (200, 404) for r in replies)
    assert c.get(f'/social/circles/{cid}', headers=b).status_code == 404
    assert c.post('/social/join', headers=b, json={'code': code}).status_code == 404
