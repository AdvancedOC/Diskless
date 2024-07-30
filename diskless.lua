local diskless = {}

-- TODO LIST:
-- add out of space error

diskless.pools = {}

diskless.uuidchars = "abcdefghijklmnopqrstuvwxyz0123456789"

local function string_escape_pattern(text)
	return text:gsub("([^%w])", "%%%1")
end

local function string_contains(s, sub)
	return string.find(s, sub, nil, true) ~= nil
end

local function string_startswith(s,sub)
	return s:sub(1,#sub) == sub
end

local function string_endswith(s,sub)
	return s:sub(#s-#sub+1) == sub
end

local function string_split(inputstr, sep)
	sep=string_escape_pattern(sep)
	local t={}
	for field,s in string.gmatch(inputstr, "([^"..sep.."]*)("..sep.."?)") do
		table.insert(t,field)
		if s=="" then
			return t
		end
	end
	return t
end

diskless.funcs = {}

diskless.funcs.spaceUsed = function(uuid)
	if diskless.pools[uuid] then
		local spaceused = 0
		local pool = diskless.pools[uuid].pool

		for k,v in pairs(pool) do
			if v.type == "file" then
				spaceused = spaceused + #v.data
			end
		end

		return spaceused
	end
end

diskless.funcs.spaceTotal = function(uuid)
	if diskless.pools[uuid] then
		if diskless.pools[uuid].sizeLimit then
			return diskless.pools[uuid].sizeLimit
		else
			return computer.freeMemory() + diskless.funcs.spaceUsed(uuid) -- technically kinda correct-ish
		end
	end
end

diskless.funcs.getLabel = function(uuid)
	if diskless.pools[uuid] then
		return diskless.pools[uuid].label
	end
end

diskless.funcs.isReadOnly = function(uuid)
	if diskless.pools[uuid] then
		return diskless.pools[uuid].readonly == true
	end
end

diskless.funcs.setLabel = function (uuid, newval)
	if diskless.pools[uuid] then
		-- TODO: enforce length limit & other limitations

		if type(newval) == "string" then
			diskless.pools[uuid].label = newval

			return newval
		end
	end
end

diskless.funcs.makeDirectory = function(uuid, path)
	if diskless.pools[uuid] then
		if diskless.pools[uuid].readonly then return false end

		local pool = diskless.pools[uuid].pool

		path = diskless.fixPath(path)
		local segs = string_split(path,"/")

		local cur = ""
		for i = 1,#segs-1 do
			cur = cur .. segs[i]
			if pool[cur] and pool[cur].type ~= "folder" then return false end -- there's a file in the folder path, can't do it
			if not pool[cur] then pool[cur] = {type="folder"} end
			cur = cur .. "/"
		end

		cur = cur .. segs[#segs]

		pool[cur] = {type="folder"} -- define it as a folder
		return true
	end
end

diskless.funcs.exists = function (uuid,path)
	if diskless.pools[uuid] then
		local pool = diskless.pools[uuid].pool

		path = diskless.fixPath(path)

		return pool[path] ~= nil
	end
end

diskless.funcs.list = function (uuid, path)
	if diskless.pools[uuid] then
		local pool = diskless.pools[uuid].pool
		path = diskless.fixPath(path)

		local parts = string_split(path,"/")

		if (not pool[path]) or (pool[path].type ~= "folder") then return nil end

		local startcheck = path .. "/"

		local items = {}

		for k,v in pairs(pool) do
			if string_startswith(k,startcheck) then
				local newparts = string_split(k,"/")

				if #newparts == #parts+1 then
					items[#items+1] = k:sub(#startcheck+1)
				end
			end
		end

		return items
	end
end

diskless.funcs.isDirectory = function (uuid, path)
	if diskless.pools[uuid] then
		local pool = diskless.pools[uuid].pool
		path = diskless.fixPath(path)

		return pool[path] and pool[path].type == "folder" or false
	end
end

diskless.funcs.lastModified = function (uuid, path)
	if diskless.pools[uuid] then
		local pool = diskless.pools[uuid].pool
		path = diskless.fixPath(path)

		if not pool[path] then return 0 end

		return pool[path].lastModified or 0
	end
end

diskless.funcs.rename = function (uuid, path1, path2)
	if diskless.pools[uuid] then
		if diskless.pools[uuid].readonly then return false end

		local pool = diskless.pools[uuid].pool

		path1 = diskless.fixPath(path1)
		path2 = diskless.fixPath(path2)

		if pool[path2] then return false end

		if not pool[path1] then return false end

		local tomove = {}

		if pool[path1].type == "folder" then
			for k,v in pairs(pool) do
				if string_startswith(k, path1 .. "/") then
					tomove[#tomove+1] = k
				end
			end
		end

		tomove[#tomove+1] = path1

		for i,v in ipairs(tomove) do
			local curpath = v
			local newpath = path2 .. "/" .. v:sub(#path1 + 1)

			if pool[newpath] then return false end

			pool[newpath] = pool[curpath]

			pool[curpath] = nil
		end

		return true
	end
end

diskless.funcs.size = function (uuid, path)
	if diskless.pools[uuid] then
		if diskless.pools[uuid].readonly then return false end

		local pool = diskless.pools[uuid].pool

		path = diskless.fixPath(path)

		if not pool[path] then return nil end

		if pool[path].type == "folder" then
			local size = 0

			for k,v in pairs(pool) do
				if string_startswith(k, path .. "/") then
					if v.type == "file" then
						size = size + #v.data
					end
				end
			end

			return size
		elseif pool[path].type == "file" then
			return #pool[path].data
		end
	end
end

diskless.funcs.remove = function (uuid, path)
	if diskless.pools[uuid] then
		if diskless.pools[uuid].readonly then return false end

		local pool = diskless.pools[uuid].pool
		path = diskless.fixPath(path)

		local succ = true

		if pool[path] then
			if pool[path].type == "folder" then
				local children = diskless.funcs.list(uuid,path)

				for i,v in ipairs(children) do
					if not diskless.funcs.remove(path .. "/" .. v) then succ = false end
				end

				if succ then pool[path] = nil end
			elseif pool[path].type == "file" then
				pool[path] = nil
			end
		end

		return succ
	end
end

diskless.funcs.open = function (uuid, path, mode)
	if diskless.pools[uuid] then
		mode = mode or "r"
		if string_contains(mode, "w") and diskless.pools[uuid].readonly then return nil end

		local pool = diskless.pools[uuid].pool
		path = diskless.fixPath(path)

		local handles = diskless.pools[uuid].handles

		if string_contains(mode, "r") then
			if not pool[path] then return nil end
			if pool[path].type ~= "file" then return nil end
		end

		local handleID = diskless.pools[uuid].handleID

		handles[handleID] = {
			mode = mode,
			path = path
		}

		diskless.pools[uuid].handleID = diskless.pools[uuid].handleID + 1

		return handleID
	end
end

diskless.funcs.write = function (uuid, handleID, data)
	if diskless.pools[uuid] then
		local handles = diskless.pools[uuid].handles
		local handle = handles[handleID]

		if not string_contains(handle.mode, "w") then return false end

		handle.buf = handle.buf or {}

		handle.buf[#handle.buf+1] = data
	end
end

diskless.funcs.read = function (uuid, handleID, amount)
	if diskless.pools[uuid] then
		local handles = diskless.pools[uuid].handles
		local handle = handles[handleID]

		if not string_contains(handle.mode, "r") then return nil end

		local pool = diskless.pools[uuid].pool
		local file = pool[handle.path]

		handle.i = handle.i or 0

		amount = math.min(amount, #file.data - handle.i) -- to fix issues with math.huge & also reading too far

		if handle.i < #file.data then
			local data = file.data:sub(handle.i+1,handle.i+amount)
			handle.i = handle.i + amount

			handle.i = math.min(math.max(handle.i,0),#file.data)

			return data
		end

		return nil
	end
end

diskless.funcs.seek = function (uuid, handleID, whence, offset)
	if diskless.pools[uuid] then
		local handles = diskless.pools[uuid].handles
		local handle = handles[handleID]

		if not string_contains(handle.mode, "r") then return nil end

		local pool = diskless.pools[uuid].pool
		local file = pool[handle.path]

		if whence == "set" then
			handle.i = offset
		elseif whence == "cur" then
			handle.i = handle.i + offset
		elseif whence == "end" then
			handle.i = #file.data + offset
		end

		handle.i = math.min(math.max(handle.i,0),#file.data)

		return handle.i
	end
end

diskless.funcs.close = function (uuid, handleID)
	if diskless.pools[uuid] then
		local handles = diskless.pools[uuid].handles
		local handle = handles[handleID]

		if string_contains(handle.mode, "w") then
			local pool = diskless.pools[uuid].pool
			if not pool[handle.path] then pool[handle.path] = {type = "file", lastModified = os.time()} end
			local file = pool[handle.path]


			file.data = table.concat(handle.buf or {})
		end

		handles[handleID] = nil
	end
end

function diskless.fixPath(path)
	if not string_startswith(path,"/") then path = "/" .. path end
	if string_endswith(path,"/") then
		path = path:sub(1,#path-1)
	end
	return path
end

function diskless.generateUUIDSegment(len)
	local buf = {}

	for i = 1,len do
		local pos = math.random(1,#diskless.uuidchars)
		buf[#buf+1] = diskless.uuidchars:sub(pos,pos)
	end

	return table.concat(buf)
end

function diskless.generateUUID()
	return diskless.generateUUIDSegment(8) .. "-"
	.. diskless.generateUUIDSegment(4) .. "-"
	.. diskless.generateUUIDSegment(4) .. "-"
	.. diskless.generateUUIDSegment(4) .. "-"
	.. diskless.generateUUIDSegment(12)
end

function diskless.makeRamFS(readonly, sizeLimit)
	local uuid = diskless.generateUUID()

	diskless.pools[uuid] = {
		label = nil,
		pool = {},
		readonly = not not readonly, -- if it's a string or any other bullshit it'll be a boolean anyway
		sizeLimit = tonumber(sizeLimit),
		handles = {},
		handleID = 1
	}

	diskless.funcs.makeDirectory(uuid, "/") -- make sure there's a root, probably a good idea

	return uuid
end

function diskless.forceWrite(uuid, path, data)
	if diskless.pools[uuid] then
		path = diskless.fixPath(path)

		local pool = diskless.pools[uuid].pool

		if pool[path] then
			if pool[path].type ~= "file" then
				return "There's already a non-file in the path!"
			end
		end

		pool[path] = {type = "file", data = data, lastModified = os.time()}
	end
end

function diskless.forceRead(uuid, path)
	if diskless.pools[uuid] then
		path = diskless.fixPath(path)

		local pool = diskless.pools[uuid].pool

		if pool[path] then
			if pool[path].type == "file" then
				return pool[path].data
			end
		end
	end
end

-- it's time to become components

local ci = component.invoke
function component.invoke(addr, func, ...)
	if diskless.pools[addr] then
		if diskless.funcs[func] then
			diskless.funcs[func](addr, ...)
		end
	else
		return ci(addr,func,...)
	end
end

local cl = component.list
function component.list(filter, exact)
	local vals = cl(filter,exact)

	if exact and filter == "filesystem" then
		for k,v in pairs(diskless.pools) do
			vals[k] = "filesystem"
		end
	elseif (not exact) and string_contains("filesystem", filter) then
		for k,v in pairs(diskless.pools) do
			vals[k] = "filesystem"
		end
	elseif (not exact) and #filter == 0 then
		for k,v in pairs(diskless.pools) do
			vals[k] = "filesystem"
		end
	end

	return vals
end

local compProx = component.proxy
function component.proxy(addr)
	if diskless.pools[addr] then
		local prox = {}

		for k,v in pairs(diskless.funcs) do
			prox[k] = function (...)
				v(addr, ...)
			end
		end

		return prox
	else
		return compProx(addr)
	end
end

return diskless