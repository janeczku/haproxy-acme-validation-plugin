-- ACME http-01 domain validation and token provisioning plugin for Haproxy 1.6+
-- copyright (C) 2015 Jan Broer
-- serves http-01 validation resources from a map-store
-- allows provisioning new validation resources via POST request

-- usage:
-- 
-- challenge endpoint example haproxy.cfg:
-- 
-- frontend public-http
-- ...
-- acl url_acme_http01 path_beg /.well-known/acme-challenge/
-- http-request use-service lua.acme-http01 if url_acme_http01
-- 
-- provision endpoint example haproxy.cfg:
-- 
-- frontend internal-http
-- bind bind *:8081
-- ...
-- acl url_acme_provision path /.well-known/provision-token
-- http-request lua.acme-provision if METH_POST url_acme_provision
--
-- Provision new http01 token/keyauth resource:
-- 
-- curl -X POST --header 'X-Auth-Secret: VERYSECRET' -d "token=123&authkey=ABC123" \
-- http://haproxy-ip:8081/.well-known/provision-token
--

-- Begin configuration

-- Client must send AUTH_SECRET in the 'X-Auth-Secret' header to provision new token
AUTH_SECRET = "042Fa8_bf0/9fb0"

-- Path to map file that stores key authorizations (dummy file must exist)
AUTH_STORE = "/etc/haproxy/acme-store.map"

-- End configuration

acme = Map.new(AUTH_STORE, Map.str);

-- http-01 token provisioning endpoint
core.register_action("acme-provision", { "tcp-req", "http-req" }, function(txn)
	local msg = ""
	local response = ""
	local src = txn.sf:src()
	local contentType = txn.sf:hdr("Content-Type")

	if contentType == "application/x-www-form-urlencoded" then
		local auth = txn.sf:hdr("X-Auth-Secret")
		if auth == AUTH_SECRET then
			local token = txn.sf:req_body_param("token")
			local authkey = txn.sf:req_body_param("authkey")
			if (token ~= nil and token ~= '' and authkey ~= nil and authkey ~= '') then
				token = sanitizeToken(token)
				core.Info("[acme] http-01 token provisioned: " .. token .. " (client-ip: " .. tostring(src) .. ")")
				core.set_map(AUTH_STORE, token, authkey)
				msg = "OK"
				response = response .. "HTTP/1.0 200 OK\r\n"
			else
				core.Warning("[acme] failed to provision http-01 token: invalid request (client-ip: " .. tostring(src) .. ")")
				msg = "invalid request"
				response = response .. "HTTP/1.0 400 Bad Request\r\n"
			end
		else
			core.Warning("[acme] failed to provision http-01 token: invalid authentication (client-ip: " .. tostring(src) .. ")")
			msg = "invalid authentication"
			response = response .. "HTTP/1.0 401 Unauthorized\r\n"
		end
	else
		core.Warning("[acme] failed to provision http-01 token: invalid content-type: " .. contentType .." (client-ip: " .. tostring(src) .. ")")
		msg = "invalid content-type: " .. contentType
		response = response .. "HTTP/1.0 400 Bad Request\r\n"
	end

	response = response .. "Server: haproxy/acme-http01-authenticator\r\n"
	response = response .. "Content-Type: text/plain\r\n"
	response = response .. "Content-Length: " .. msg:len() .. "\r\n"
	response = response .. "Connection: close\r\n"
	response = response .. "\r\n"
	response = response .. msg

	txn.res:send(response)
	txn.done(txn)
end)

-- http-01 validation endpoint
core.register_service("acme-http01", "http", function(applet)
	local response = ""
	local reqPath = applet.sf:path()
	local src = applet.sf:src()
	local token = reqPath:match( ".+/(.*)$" )

	if token then
		token = sanitizeToken(token)
	end

	if (token == nil or token == '') then
		response = "bad request\n"
		applet:set_status(400)
		core.Warning("[acme] malformed request (client-ip: " .. tostring(src) .. ")")
	else
		auth = getKeyAuth(token)
		if (auth:len() >= 1) then
			response = auth .. "\n"
			applet:set_status(200)
			core.Info("[acme] served http-01 token: " .. token .. " (client-ip: " .. tostring(src) .. ")")
			core.del_map(AUTH_STORE, token)
		else
			response = "resource not found\n"
			applet:set_status(404)
			core.Warning("[acme] http-01 token not found: " .. token .. " (client-ip: " .. tostring(src) .. ")")
		end
	end

	applet:add_header("Server", "haproxy/acme-http01-authenticator")
	applet:add_header("Content-Length", string.len(response))
	applet:add_header("Content-Type", "text/plain")
	applet:start_response()
	applet:send(response)
end)

-- strip chars that are not in the URL-safe Base64 alphabet
-- see https://github.com/letsencrypt/acme-spec/blob/master/draft-barnes-acme.md
function sanitizeToken(token)
	_strip="[^%a%d%+%-%_=]"
	token = token:gsub(_strip,'')
	return token
end

-- get key auth from token map store
function getKeyAuth(token)
	local keyAuth = ""
	local k = acme:lookup(token)
	if k ~= nil then
		keyAuth = k
	end
	return keyAuth
end