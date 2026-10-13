read -r -s -p "Enter API secret (leave blank if none): " MIHOMO_SECRET
printf '\n'

python -c '
import json
print(json.dumps({"name": "\U0001f530 \u9009\u62e9\u8282\u70b9"}))
' |
	curl --noproxy '*' -fsS -X PUT \
	    -H "Authorization: Bearer $MIHOMO_SECRET" \
	        -H 'Content-Type: application/json' \
		    --data-binary @- \
		        -w '\nHTTP: %{http_code}\n' \
			    http://127.0.0.1:9090/proxies/GLOBAL
