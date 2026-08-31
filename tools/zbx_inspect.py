import json, os, ssl, urllib.request

url = 'https://127.0.0.1/api_jsonrpc.php'
def call(method, params, auth=None):
    payload = {'jsonrpc':'2.0','method':method,'params':params,'id':1}
    if auth: payload['auth'] = auth
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={'Content-Type':'application/json-rpc'})
    result = json.load(urllib.request.urlopen(req, context=ssl._create_unverified_context()))
    if 'error' in result: raise SystemExit(result['error'])
    return result['result']

auth = call('user.login', {'username':'Admin','password':os.environ['ZABBIX_ADMIN_PASSWORD']})
print(json.dumps({'media':call('mediaType.get', {'output':'extend'}, auth), 'users':call('user.get', {'output':['userid','username','name','surname'], 'selectMedias':'extend'}, auth), 'actions':call('action.get', {'output':['actionid','name','status','eventsource'], 'selectOperations':'extend'}, auth)}, indent=2))
