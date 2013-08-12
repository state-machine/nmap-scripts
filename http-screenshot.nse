-- Copyright (C) 2012 Trustwave
-- http://www.trustwave.com
-- 
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; version 2 dated June, 1991 or at your option
-- any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
-- 
-- A copy of the GNU General Public License is available in the source tree;
-- if not, write to the Free Software Foundation, Inc.,
-- 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


-- -*- mode: lua -*-
-- vim: set filetype=lua :

description = [[
Gets a screenshot from the host
]]

author = "Ryan Linn <rlinn at trustwave.com>"

license = "GPLv2"

categories = {"discovery", "safe"}

local stdnse = require "stdnse"
local nsedebug = require "nsedebug"
local shortport = require "shortport"
local table = require "table"
local io = require "io"
local http = require "http"

portrule = shortport.http
postrule = function() return (nmap.registry.screenshot ~= nil) end

-- helper function, adds screenshots to registry
-- called by portaction, that writes screenshot image
-- used by postaction, that creates preview html
local function add_screenshot_to_registry(url, filename, headers)
	--stdnse.print_debug(1, "=== add_screenshot_to_registry ===")
	--stdnse.print_debug(1, "url: %s", url)
	--stdnse.print_debug(1, "filename: %s", filename )
	nmap.registry.screenshot = nmap.registry.screenshot or {}
	nmap.registry.screenshot[url] = nmap.registry.screenshot[url] or {}
	table.insert( nmap.registry.screenshot[url], {filename = filename, headers = headers})

	stdnse.print_debug(1, "============= adding ==============")
	stdnse.print_debug(1, nsedebug.tostr(headers))
end

local function do_request(host, port, path)
	-- Try using HEAD first
	status, result = http.can_use_head(host, port, nil, path)

	-- If head failed, try using GET
	if(status == false) then
		stdnse.print_debug(1, "http-headers.nse: HEAD request failed, falling back to GET")
		result = http.get(host, port, path)
		request_type = "GET"
	end

	if(result == nil) then
		if(nmap.debugging() > 0) then
			return "ERROR: Header request failed"
		else
			return nil
		end
	end

	if(result.rawheader == nil) then
		if(nmap.debugging() > 0) then
			return "ERROR: Header request didn't return a proper header"
		else
			return nil
		end
	end

	return result
end

-- Capture the screenshot for each host and store a reference to use in the preview file
-- action = function(host, port)
local function portaction(host, port)
	-- Check to see if ssl is enabled, if it is, set ssl to true
	local ssl = false
	if port.version.service_tunnel == "ssl" or port.service == "https" or port.version.name == "https" then
		ssl = true
	else
		ssl = false
	end


	stdnse.print_debug(1, "==================================")
	stdnse.print_debug(1, "ssl: %s", ssl )
	local p
	p = nsedebug.tostr(port)
	stdnse.print_debug(1, "port: %s", p )
	stdnse.print_debug(1, "service: %s", port.service )
	stdnse.print_debug(1, "name: %s", port.version.name )
	stdnse.print_debug(1, "==================================")



	-- The default URLs will start with http://
	local prefix = "http"

	-- If SSL is set on the port, switch the prefix to https
	if ssl then
		prefix = "https"	
	end

	-- Screenshots will be called http|https--hostname:port--hostip.png
	local name = stdnse.get_hostname(host)
    local filename = prefix .. "--" .. name .. "--port--" .. port.number .. "--" .. host.ip .. ".png"

	-- Execute the shell command wkhtmltoimage-i386 <url> <filename>
	local cmd = "timeout 20 wkhtmltoimage-amd64 --quality 20 -n " .. prefix .. "://" .. name .. ":" .. port.number .. " " .. filename .. " 2> /dev/null   >/dev/null"
	
	local ret = false
	ret = os.execute(cmd)

	-- make and HTTP request and stash the response
    http_response = do_request(host, port, '/')

	-- If the command was successful, print the saved message, otherwise print the fail message
	local result = ""
	if ret then
		result = "Saved to " .. filename	
	else
		-- sometimes ret is false but image file was still written.
		result = "failed (verify wkhtmltoimage binary is in your path)"
	end
	-- add header to registry regardless of whether screenshot worked (segfauls on nginx sometimes)
	add_screenshot_to_registry( prefix .. "://" .. name .. ":" ..port.number, filename, http_response.rawheader )	

	-- Return the output message
	return stdnse.format_output(true,  result)
end

-- Create the preview.html file, runs after screenshots have been captured
local function postaction()
stdnse.print_debug(1, "=== postaction ===" )
stdnse.print_debug(1, nsedebug.tostr(nmap.registry.screenshot))

	local header = "<html><body><br>"
	local footer = "</body></html>"
	local items = ""
	local filename = ""
	local headers = ""
--	for url, filenames in pairs(nmap.registry.screenshot) do
--		for _, filename in ipairs(filenames) do
	for url, details in pairs(nmap.registry.screenshot) do
		for _, detail in ipairs(details) do
			for name, item in pairs(detail) do
				if name == 'filename' then
					stdnse.print_debug(1, "zz filename: %s", item )
					filename = item
				else
					headers = ""
					for _, header in ipairs(item) do
							stdnse.print_debug(1, "zz header: %s", header )
							headers = headers .. header .. '<br>'
					end
				end
			end
			--stdnse.print_debug(1, "=== postaction ===" )

			--local d = nsedebug.tostr(detail)
			-- stdnse.print_debug(1, "detail: %s", d )

			items = items ..  "<a href='" .. url  .. "'>" .. url .. "</a><br><br>".. headers .."</div><br><a href='" .. url  .. "'><img src='" .. filename .. "' width=400></a> <br>\n"
		end
	end

	out = header .. items .. footer
	local file	
	file = io.open("preview.html", "w")
	if file then
		file:write(out)
		file:close()
	else
			stdnse.print_debug(1, "Failed to open file" )
	end
end

local ActionsTable = {
  -- portrule: create screenshot file for each host
  portrule = portaction,
  -- postrule: write html preview page showing all screenshots
  postrule = postaction
}

-- execute the action function corresponding to the current rule
action = function(...) return ActionsTable[SCRIPT_TYPE](...) end
