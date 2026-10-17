"""Inventory and account scoring integration tests using isolated Postgres."""
from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
import pytest
from tests.conftest import needs_db, run_sql
from tests.test_drops import arm, report, JPEG
from tests.test_social import account
pytestmark = needs_db


def add(c, grams=110, pieces=1, **extra):
    return c.post('/bins/bin-001/logs', json={'item':'Banana peel','catalog_id':'banana_peel',
        'quantity_g':grams,'piece_count':pieces, **extra})


def inventory(c, **kwargs):
    r = c.get('/bins/bin-001/inventory', **kwargs)
    assert r.status_code == 200, r.text
    return r.json()


def test_confirmed_grouped_inventory_and_scores(c):
    assert inventory(c)['items'] == []
    for _ in range(2):
        assert add(c,90,2,request_id='same-banana').status_code == 201
    add(c,30,1)
    add(c,80,2,item='Apple core',catalog_id='apple_core')
    add(c,100,3,item='Cheese',catalog_id='cheese')
    add(c,110,1,action='skipped')
    add(c,0,9)
    did = report(c,arm(c)).json()['drop_id']
    before = inventory(c)
    c.post(f'/drops/{did}/dismiss')
    assert inventory(c) == before
    assert (before['grams'],before['pieces'],before['entries']) == (200,5,3)
    assert before['volume_xp'] == before['total_xp'] == 10
    banana = next(i for i in before['items'] if i['catalog_id']=='banana_peel')
    assert banana['label']=='Banana peel' and banana['pieces']==3 and banana['grams']==120


def test_legacy_unknown_counts_and_custom_name_normalization(c):
    add(c,100,None)
    for label in ['Pineapple skin','  pineapple   skin  ']:
        c.post('/bins/bin-001/logs',json={'item':label,'category':'green','piece_count':2,'quantity_g':50})
    data=inventory(c)
    assert data['pieces']==4 and data['uncounted_entries']==1 and len(data['items'])==2
    pineapple=next(i for i in data['items'] if i['catalog_id'] is None)
    assert pineapple['pieces']==4 and pineapple['entries']==2


def test_camera_counts_weights_and_concurrent_confirmation_retries(c):
    did=report(c,arm(c),items=[{'label':'banana peel','catalog_id':'banana_peel',
        'confidence':.9,'piece_count':9,'est_grams':900}]).json()['drop_id']
    assert inventory(c)['pieces']==0
    body={'items':[
        {'label':'Banana peel','catalog_id':'banana_peel','piece_count':2,'quantity_g':120,'amount':'handful'},
        {'label':'Apple core','catalog_id':'apple_core','piece_count':2,'quantity_g':80,'amount':'small'},
        {'label':'Cheese','category':'green','piece_count':1,'quantity_g':50,'removed':True}]}
    with ThreadPoolExecutor(max_workers=3) as pool:
        replies=list(pool.map(lambda _:c.post(f'/drops/{did}/confirm',json=body),range(3)))
    assert all(r.status_code==200 for r in replies)
    assert all(r.json()==replies[0].json() for r in replies)
    assert replies[0].json()['corrected']
    data=inventory(c)
    assert (data['grams'],data['pieces'],data['entries'])==(200,4,2)
    assert sum(i['vision_entries'] for i in data['items'])==2
    assert (data['volume_xp'],data['care_xp'],data['total_xp'])==(10,5,15)
    assert len(c.get('/bins/bin-001/logs').json())==3
    assert c.post(f'/drops/{did}/confirm',json={'items':[{**body['items'][0],'piece_count':3}]}).status_code==409
    stored=c.get(f'/drops/{did}').json()
    assert stored['items'][0]['piece_count']==9 and stored['final_items'][0]['piece_count']==2


def test_period_boundaries(c):
    add(c,80,2)
    now=datetime.now(timezone.utc)
    sunday=(now-timedelta(days=(now.weekday()+1)%7)).replace(hour=0,minute=0,second=0,microsecond=0)
    for time,grams,pieces in [(sunday-timedelta(seconds=1),100,5),(sunday,40,1),(now+timedelta(days=1),300,9)]:
        c.portal.call(run_sql,"""INSERT INTO add_log(time,bin_id,user_id,item,catalog_id,category,action,quantity_g,piece_count,source)
            VALUES($1,'bin-001','demo-user','Banana peel','banana_peel','green','added',$2,$3,'camera')""",time,grams,pieces)
    week=inventory(c,params={'period':'week'})
    assert week['grams']==120 and week['pieces']==3
    assert inventory(c)['grams']==220
    assert c.get('/bins/bin-001/inventory?period=month').status_code==422
    assert c.get('/bins/missing/inventory').status_code==404


def test_owned_camera_inventory_and_private_leaderboard(c):
    add(c,100,7)  # Pairing must not transfer the demo owner's history.
    uid,h=account(c,'inventory_alice'); _,other=account(c,'inventory_bob')
    assert c.post('/social/bin',headers=h,json={'device_token':c.device_token}).status_code==200
    assert inventory(c,headers=h)['pieces']==0
    assert c.get('/bins/bin-001/inventory').status_code==403
    assert c.get('/bins/bin-001/inventory',headers=other).status_code==403
    device={'X-Device-Token':c.device_token}
    assert c.post('/bins/bin-001/drops/session',headers=device).status_code==403
    sid=c.post('/bins/bin-001/drops/session',headers=h).json()['session_id']
    assert c.get('/bins/bin-001/drops/session/active',headers=device).status_code==200
    response=c.post('/bins/bin-001/drops',headers=device,json={'session_id':sid,'latency_ms':100,'gemini_ok':True,
        'items':[{'label':'banana peel','catalog_id':'banana_peel','confidence':.9,'piece_count':2,'est_grams':100}]})
    assert response.status_code==201,response.text
    did=response.json()['drop_id']
    body={'items':[{'label':'Banana peel','catalog_id':'banana_peel','piece_count':2,'quantity_g':100}]}
    assert c.post(f'/drops/{did}/confirm',headers=device,json=body).status_code==403
    assert c.post(f'/drops/{did}/confirm',headers=other,json=body).status_code==403
    assert c.get('/bins/bin-001/drops/pending',headers=h).status_code==200
    assert c.post(f'/drops/{did}/confirm',headers=h,json=body).status_code==200
    saved=inventory(c,headers=h)
    assert (saved['grams'],saved['pieces'],saved['volume_xp'])==(100,2,5)
    assert c.get('/bins/bin-001/inventory',headers=device).status_code==403
    assert c.get('/bins/another-bin/drops/session/active',headers=device).status_code==403
    c.post('/social/check-in',headers=h)
    cid=c.post('/social/circles',headers=h,json={'name':'Compost crew'}).json()['id']
    board=c.get(f'/social/circles/{cid}',headers=h).json()['members'][0]
    assert (board['grams'],board['pieces'],board['volume_xp'],board['care_xp'])==(100,2,5,5)
    assert board['xp']==board['volume_xp']+board['care_xp']==10
    assert 'items' not in board
    # A new manual account log shares the same inventory, without fresh sensors.
    r=c.post('/social/care-log',headers=h,json={'catalog_id':'apple_core','action':'added',
        'quantity_g':80,'piece_count':2,'request_id':'inventory-manual-001'})
    assert r.status_code==200,r.text
    assert inventory(c,headers=h)['pieces']==4


def test_photo_fallback_manual_confirmation(c):
    response=c.post('/bins/bin-001/drops/photo',json={'image_jpeg_b64':JPEG})
    assert response.status_code==201,response.text
    drop=response.json()
    assert inventory(c)['entries']==0
    r=c.post(f"/drops/{drop['id']}/confirm",json={'items':[
        {'label':'Apple core','catalog_id':'apple_core','piece_count':2,'quantity_g':80}]})
    assert r.status_code==200,r.text
    item=inventory(c)['items'][0]
    assert item['pieces']==2 and item['vision_entries']==1


@pytest.mark.parametrize('count',[0,-1,1000,1.5,True,'2'])
def test_invalid_counts_never_write(c,count):
    assert add(c,pieces=count).status_code==422
    did=report(c,arm(c)).json()['drop_id']
    assert c.post(f'/drops/{did}/confirm',json={'items':[{'label':'Banana peel','piece_count':count}]}).status_code==422
    assert inventory(c)['entries']==0


def test_counts_do_not_multiply_mass_or_bypass_xp_cap(c):
    assert add(c,100,999).json()['xp_awarded']==5
    assert add(c,5000,1).json()['xp_awarded']==55
    assert add(c,100,2).json()['xp_awarded']==0
    data=inventory(c)
    assert (data['grams'],data['pieces'],data['volume_xp'])==(5200,1002,60)


def test_weight_only_correction_is_retained(c):
    did=report(c,arm(c),items=[{'label':'Banana peel','catalog_id':'banana_peel','confidence':.9,
        'piece_count':2,'est_grams':110,'amount':'handful'}]).json()['drop_id']
    response=c.post(f'/drops/{did}/confirm',json={'items':[{'label':'Banana peel','catalog_id':'banana_peel',
        'piece_count':2,'quantity_g':85,'amount':'handful'}]})
    assert response.status_code==200 and response.json()['corrected']
    assert inventory(c)['grams']==85


def test_supplying_an_unknown_model_count_is_not_a_wrong_guess(c):
    did=report(c,arm(c)).json()['drop_id']
    response=c.post(f'/drops/{did}/confirm',json={'items':[{'label':'banana peel','catalog_id':'banana_peel',
        'piece_count':1,'quantity_g':110,'amount':'handful'}]})
    assert response.status_code==200 and not response.json()['corrected']
