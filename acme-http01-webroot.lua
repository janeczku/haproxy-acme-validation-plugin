-- ACME http-01 domain validation plugin for Haproxy 1.6+
-- copyright (C) 2015 Jan Broer
--
-- usage:
--
-- 1) copy acme-webroot.lua in your haproxy config dir
-- 
-- 2) Invoke the plugin by adding in the 'global' section of haproxy.cfg:
-- 
--    lua-load /etc/haproxy/acme-webroot.lua
-- 
-- 3) insert these two lines in every http frontend that is
--    serving domains for which you want to create certificates:
-- 
--    acl url_acme_http01 path_beg /.well-known/acme-challenge/
--    http-request use-service lua.acme-http01 if METH_GET url_acme_http01
--
-- 4) reload haproxy
--
-- 5) create a certificate:
--
-- ./letsencrypt-auto certonly --text --webroot --webroot-path /var/tmp -d blah.example.com --renew-by-default --agree-tos --email my@email.com
--

--
-- Configuration begin
--

-- Path passed to letsencrypt via the '--webroot-path' parameter must match this
WEBROOT = "/var/tmp"

--
-- Configuration end
--

VERSION = "0.1.0"

core.Info("[acme] http-01 plugin v." .. VERSION .. " loaded");

--
-- ACME http-01 validation endpoint
--
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

--
-- strip chars that are not in the URL-safe Base64 alphabet
-- see https://github.com/letsencrypt/acme-spec/blob/master/draft-barnes-acme.md
--
function sanitizeToken(token)
	_strip="[^%a%d%+%-%_=]"
	token = token:gsub(_strip,'')
	return token
end

--
-- get key auth from token file
--
function getKeyAuth(token)
	local keyAuth = ""
	local f = io.open(WEBROOT .. "/.well-known/acme-challenge/" .. token, "rb")
	if f ~= nil then
		keyAuth = f:read("*all")
		f:close()
	end
	return keyAuth
end