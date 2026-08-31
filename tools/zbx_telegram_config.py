import json, os, ssl, urllib.request

URL = 'https://127.0.0.1/api_jsonrpc.php'
def call(method, params, auth=None):
    p = {'jsonrpc':'2.0','method':method,'params':params,'id':1}
    if auth: p['auth'] = auth
    req = urllib.request.Request(URL, data=json.dumps(p).encode(), headers={'Content-Type':'application/json-rpc'})
    out = json.load(urllib.request.urlopen(req, context=ssl._create_unverified_context()))
    if 'error' in out: raise SystemExit(out['error'])
    return out['result']

auth = call('user.login', {'username':'Admin','password':os.environ['ZABBIX_ADMIN_PASSWORD']})
mt = call('mediaType.get', {'mediatypeids':['65'], 'output':'extend'}, auth)[0]
params = mt['parameters']
for p in params:
    if p['name'] == 'api_token': p['value'] = os.environ['ZABBIX_TELEGRAM_BOT_TOKEN']
    elif p['name'] == 'api_chat_id': p['value'] = '{ALERT.SENDTO}'
    elif p['name'] == 'api_parse_mode': p['value'] = ''
call('mediaType.update', {'mediatypeid':'65','status':0,'parameters':params}, auth)
admin = call('user.get', {'userids':['1'], 'selectMedias':'extend'}, auth)[0]
medias = [m for m in admin.get('medias', []) if m['mediatypeid'] != '65']
medias.append({'mediatypeid':'65','sendto':[os.environ['ZABBIX_TELEGRAM_CHAT_ID']], 'active':0, 'severity':63, 'period':'1-7,00:00-24:00'})
call('user.update', {'userid':'1','medias':medias}, auth)
action = call('action.get', {'actionids':['3'], 'selectOperations':'extend'}, auth)[0]
ops = action.get('operations', [])
for o in ops:
    for key in ('operationid', 'actionid', 'esc_period', 'esc_step_from', 'esc_step_to', 'evaltype', 'opconditions'):
        o.pop(key, None)
    if 'opmessage' in o:
        for key in ('operationid', 'actionid', 'subject', 'message'):
            o['opmessage'].pop(key, None)
if not any(o.get('opmessage', {}).get('mediatypeid') == '65' for o in ops):
    ops.append({'operationtype':0, 'opmessage':{'default_msg':1,'mediatypeid':'65'}, 'opmessage_grp':[{'usrgrpid':'7'}]})
call('action.update', {'actionid':'3','status':0,'operations':ops}, auth)
print('zabbix_telegram_configured')
