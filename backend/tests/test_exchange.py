"""Real-Postgres exchange tests: permissions, lifecycle, caps and concurrent retries."""
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import pytest
from app.services import ledger
from tests.conftest import needs_db, run_sql
from tests.test_social import account
pytestmark = needs_db


@pytest.fixture
def group(c):
    users = [account(c, name) for name in ('alice', 'bob', 'charlie', 'diana')]
    cid = c.post('/social/circles', headers=users[0][1], json={'name':'Garden crew'}).json()['id']
    code = c.post(f'/social/circles/{cid}/invite', headers=users[0][1]).json()['code']
    for _, h in users[1:]:
        assert c.post('/social/join', headers=h, json={'code':code}).status_code == 200
    return cid, users


def url(cid, pid=None, action=None):
    path = f'/social/circles/{cid}/exchange'
    return path if pid is None else f'{path}/{pid}/{action}'


def create(c, cid, h, **extra):
    response = c.post(url(cid), headers=h, json={'kind':'request','material_id':'dry_leaves',
        'quantity':'One small bag','details':'For my wet bin','request_id':uuid4().hex, **extra})
    assert response.status_code == 201, response.text
    return response.json()


def claim(c, cid, post, h, **extra):
    r = c.post(url(cid, post['id'], 'claim'), headers=h, json={'version':post['version'],
        'request_id':uuid4().hex, 'note':'Garden gate Saturday at noon', **extra})
    assert r.status_code == 200, r.text
    return r.json()


def confirm(c, cid, post, h):
    return c.post(url(cid, post['id'],'confirm'), headers=h, json={'reservation_id':post['reservation_id']})


def xp(c, h):
    return c.get('/social/me', headers=h).json()['progress']['total_xp']


def complete(c, cid, a, b, **extra):
    post = claim(c,cid,create(c,cid,a,**extra),b)
    assert confirm(c,cid,post,a).status_code == 200
    response = confirm(c,cid,post,b)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize('kind',['request','offer'])
def test_both_participants_earn_only_after_both_confirm(c, group, kind):
    cid, users=group; (alice,a),(bob,b)=users[:2]
    post=create(c,cid,a,kind=kind)
    assert xp(c,a)==xp(c,b)==0
    post=claim(c,cid,post,b)
    assert xp(c,a)==xp(c,b)==0
    assert confirm(c,cid,post,b).json()['status']=='reserved'
    assert xp(c,a)==xp(c,b)==0
    final=confirm(c,cid,post,a).json()
    assert final['status']=='completed' and final['creator_xp']==final['responder_xp']==10
    assert xp(c,a)==xp(c,b)==10
    board=c.get(f'/social/circles/{cid}',headers=a).json()
    assert board['team_xp']==20
    assert c.get('/social/feed',headers=a).json()[0]['kind']=='exchange_completed'
    assert c.get('/bins/bin-001/logs').json()==[]  # sharing isn't a compost addition
    assert c.get(f'/users/{alice}/game',headers=a).json()['total_xp']==10


def test_create_and_claim_receipts_reject_changed_or_delayed_retries(c,group):
    cid,users=group; _,a=users[0];_,b=users[1]
    key=uuid4().hex
    post=create(c,cid,a,request_id=key)
    assert create(c,cid,a,request_id=key)['id']==post['id']
    assert c.post(url(cid),headers=a,json={'kind':'request','material_id':'dry_leaves','quantity':'different',
        'details':'For my wet bin','request_id':key}).status_code==409
    claim_key=uuid4().hex
    reserved=claim(c,cid,post,b,request_id=claim_key)
    assert claim(c,cid,post,b,request_id=claim_key)['reservation_id']==claim_key
    assert c.post(url(cid,post['id'],'claim'),headers=b,json={'version':1,'request_id':claim_key,'note':'changed'}).status_code==409
    released=c.post(url(cid,post['id'],'release'),headers=b,json={'reservation_id':claim_key})
    assert released.json()['status']=='open'
    assert c.post(url(cid,post['id'],'claim'),headers=b,json={'version':1,'request_id':claim_key}).status_code==409
    new=claim(c,cid,released.json(),users[2][1])
    assert confirm(c,cid,reserved,a).status_code==409
    assert new['responder']['user_id']==users[2][0]


def test_notes_are_private_to_participants_and_group_access_is_required(c,group):
    cid,users=group;_,a=users[0];_,b=users[1];_,third=users[2]
    post=create(c,cid,a)
    assert c.post(url(cid,post['id'],'claim'),headers=a,json={'version':1,'request_id':uuid4().hex}).status_code==400
    post=claim(c,cid,post,b)
    response=c.post(url(cid,post['id'],'note'),headers=a,json={'reservation_id':post['reservation_id'],'note':'Private location'})
    assert response.json()['creator_note']=='Private location'
    row=c.get(url(cid),headers=third).json()['posts'][0]
    assert not {'creator_note','responder_note','reservation_id','claim_payload','create_payload'} & row.keys()
    assert c.post(url(cid,post['id'],'note'),headers=third,json={'reservation_id':post['reservation_id'],'note':'intrusion'}).status_code==403
    assert confirm(c,cid,post,third).status_code==403
    _,outsider=account(c,'outsider')
    assert c.get(url(cid),headers=outsider).status_code==404
    assert c.get(url(cid)).status_code==401
    assert confirm(c,cid,post,outsider).status_code==404


def test_simultaneous_claims_have_one_winner_and_rewards_are_once_only(c,group):
    cid,users=group;_,a=users[0]
    post=create(c,cid,a)
    def reserve(h):
        return c.post(url(cid,post['id'],'claim'),headers=h,json={'version':1,'request_id':uuid4().hex})
    with ThreadPoolExecutor(max_workers=3) as pool:
        replies=list(pool.map(reserve,[h for _,h in users[1:]]))
    assert sorted(r.status_code for r in replies)==[200,409,409]
    reserved=next(r.json() for r in replies if r.status_code==200)
    b=next(h for uid,h in users if uid==reserved['responder']['user_id'])
    with ThreadPoolExecutor(max_workers=8) as pool:
        responses=list(pool.map(lambda h:confirm(c,cid,reserved,h),[a,b]*4))
    assert all(r.status_code==200 for r in responses)
    assert xp(c,a)==xp(c,b)==10
    assert confirm(c,cid,reserved,b).json()['responder_xp']==10


def test_pair_limit_applies_to_reversed_roles_and_other_groups(c,group):
    cid,users=group;(alice,a),(_,b)=users[:2]
    complete(c,cid,a,b)
    final=complete(c,cid,b,a,kind='offer')
    assert final['creator_xp']==final['responder_xp']==0
    other=c.post('/social/circles',headers=b,json={'name':'Another group'}).json()['id']
    code=c.post(f'/social/circles/{other}/invite',headers=b).json()['code']
    c.post('/social/join',headers=a,json={'code':code})
    # Deleting the old group must not erase the pair's reward cooldown.
    assert c.delete(f'/social/circles/{cid}',headers=a).status_code==200
    final=complete(c,other,a,b)
    assert final['creator_xp']==final['responder_xp']==0
    assert xp(c,a)==xp(c,b)==10


def test_daily_exchange_limit_and_shared_action_cap(c,group):
    cid,users=group;_,a=users[0]
    for _,h in users[1:]:complete(c,cid,a,h)
    assert xp(c,a)==20
    assert all(xp(c,h)==10 for _,h in users[1:])
    # Fresh day: action headroom is only 5, even though exchange headroom is 20.
    c.portal.call(run_sql,"UPDATE point_events SET time=time-interval '2 days', dedupe_key='past:'||dedupe_key")
    c.portal.call(run_sql,"INSERT INTO point_events(user_id,kind,xp) VALUES($1,'followed_suggestion',55)",users[0][0])
    final=complete(c,cid,a,users[1][1])
    assert final['creator_xp']==5 and final['responder_xp']==10
    assert xp(c,a)==80  # 20 historical + 55 care + 5 exchange


def test_concurrent_exchanges_in_different_groups_respect_daily_cap(c,group):
    _,users=group;_,a=users[0]
    pending=[]
    for _,h in users[1:]:
        cid=c.post('/social/circles',headers=a,json={'name':'Separate exchange group'}).json()['id']
        code=c.post(f'/social/circles/{cid}/invite',headers=a).json()['code']
        c.post('/social/join',headers=h,json={'code':code})
        post=claim(c,cid,create(c,cid,a),h)
        assert confirm(c,cid,post,a).status_code==200
        pending.append((cid,post,h))
    with ThreadPoolExecutor(max_workers=3) as pool:
        replies=list(pool.map(lambda p:confirm(c,p[0],p[1],p[2]),pending))
    assert all(r.status_code==200 for r in replies)
    assert xp(c,a)==20


def test_expiry_cancel_and_release_never_reward(c,group):
    cid,users=group;_,a=users[0];_,b=users[1]
    post=claim(c,cid,create(c,cid,a),b)
    assert c.post(url(cid,post['id'],'release'),headers=a,json={'reservation_id':post['reservation_id']}).status_code==403
    assert confirm(c,cid,post,a).status_code==200
    assert c.post(url(cid,post['id'],'release'),headers=b,json={'reservation_id':post['reservation_id']}).status_code==409
    c.portal.call(run_sql,"UPDATE exchange_posts SET expires_at=now()-interval '1 second'")
    assert confirm(c,cid,post,b).status_code==409
    assert c.get(url(cid),headers=a).json()['posts']==[]
    assert c.get(url(cid)+'?view=history',headers=a).json()['posts'][0]['status']=='expired'
    assert c.post(url(cid,post['id'],'cancel'),headers=b,json={'version':post['version']}).status_code==200
    assert xp(c,a)==xp(c,b)==0


def test_removal_reopens_unconfirmed_reservation_but_cancels_partial_handoff(c,group):
    cid,users=group;(alice,a),(bob,b),(_,third)=users[:3]
    post=claim(c,cid,create(c,cid,a),b)
    assert c.delete(f'/social/circles/{cid}/members/{bob}',headers=a).status_code==200
    row=c.get(url(cid),headers=a).json()['posts'][0]
    assert row['status']=='open' and row['responder'] is None
    assert confirm(c,cid,post,b).status_code==404
    next_post=claim(c,cid,row,third)
    assert confirm(c,cid,next_post,a).status_code==200
    assert c.delete(f'/social/circles/{cid}/members/{users[2][0]}',headers=a).status_code==200
    assert c.get(url(cid)+'?view=history',headers=a).json()['posts'][0]['status']=='cancelled'
    assert xp(c,a)==0


def test_creator_leaving_cancels_their_posts(c,group):
    cid,users=group;_,a=users[0];bob,b=users[1]
    post=create(c,cid,b)
    assert c.delete(f'/social/circles/{cid}/members/{bob}',headers=b).status_code==200
    assert c.get(url(cid)+'?view=history',headers=a).json()['posts'][0]['status']=='cancelled'
    assert c.post(url(cid,post['id'],'claim'),headers=users[2][1],json={'version':1,'request_id':uuid4().hex}).status_code==409


def test_second_reward_failure_rolls_back_completion_and_both_awards(c,group,monkeypatch):
    cid,users=group;_,a=users[0];_,b=users[1]
    post=claim(c,cid,create(c,cid,a),b)
    confirm(c,cid,post,a)
    real=ledger.award;calls=0
    async def fail(*args,**kwargs):
        nonlocal calls
        calls+=1
        if calls==2:raise RuntimeError('simulated write failure')
        return await real(*args,**kwargs)
    monkeypatch.setattr(ledger,'award',fail)
    with pytest.raises(RuntimeError):confirm(c,cid,post,b)
    assert xp(c,a)==xp(c,b)==0
    row=c.get(url(cid),headers=a).json()['posts'][0]
    assert row['creator_confirmed'] and not row['responder_confirmed'] and row['status']=='reserved'
    monkeypatch.setattr(ledger,'award',real)
    assert confirm(c,cid,post,b).json()['status']=='completed'
    assert xp(c,a)==xp(c,b)==10


def test_material_validation_spoofed_rewards_limits_and_pagination(c,group):
    cid,users=group;_,a=users[0]
    for material in ('meat','cheese','oily_food','not-real'):
        r=c.post(url(cid),headers=a,json={'kind':'request','material_id':material,'quantity':'bag','request_id':uuid4().hex})
        assert r.status_code==422
    r=c.post(url(cid),headers=a,json={'kind':'offer','material_id':'cardboard','quantity':'bag','request_id':uuid4().hex,'xp':999})
    assert r.status_code==422
    for i in range(10):create(c,cid,a,material_id='help_turning' if i==0 else 'cardboard')
    assert c.post(url(cid),headers=a,json={'kind':'offer','material_id':'dry_leaves','quantity':'bag','request_id':uuid4().hex}).status_code==409
    first=c.get(url(cid)+'?limit=3',headers=a).json()
    second=c.get(url(cid)+f"?limit=3&before={first['next_before']}",headers=a).json()
    assert len(first['posts'])==len(second['posts'])==3
    assert not set(p['id'] for p in first['posts']) & set(p['id'] for p in second['posts'])
    assert xp(c,a)==0


def test_reward_rules_are_bounded():
    from app.rules.game import exchange_xp
    assert [exchange_xp(n) for n in (0,10,15,20,99)]==[10,10,5,0,0]
