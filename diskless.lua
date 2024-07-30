local diskless = {}

-- TODO LIST:
-- add out of space error -- kinda done
-- enforce limitations for labels
-- properly check if file path is valid (there is a parent folder) -- kinda done

diskless.pools = {}

diskless.components = {}

diskless.uuidchars = "0123456789abcdef"

diskless.filesystemDoc = { -- directly yoinked from the actual one
	size = [[function(path:string):number -- Returns the size of the object at the specified absolute path in the file system.]],
	close = [[function(handle:userdata) -- Closes an open file descriptor with the specified handle.]],
	rename = [[function(from:string, to:string):boolean -- Renames/moves an object from the first specified absolute path in the file system to the second.]],
	lastModified = [[function(path:string):number -- Returns the (real world) timestamp of when the object at the specified absolute path in the file system was modified.]],
	setLabel = [[function(value:string):string -- Sets the label of the drive. Returns the new value, which may be truncated.]],
	read = [[function(handle:userdata, count:number):string or nil -- Reads up to the specified amount of data from an open file descriptor with the specified handle. Returns nil when EOF is reached.]],
	isDirectory = [[function(path:string):boolean -- Returns whether the object at the specified absolute path in the file system is a directory.]],
	spaceTotal = [[function():number -- The overall capacity of the file system, in bytes.]],
	isReadOnly = [[function():boolean -- Returns whether the file system is read-only.]],
	exists = [[function(path:string):boolean -- Returns whether an object exists at the specified absolute path in the file system.]],
	open = [[function(path:string[, mode:string='r']):userdata -- Opens a new file descriptor and returns its handle.]],
	list = [[function(path:string):table -- Returns a list of names of objects in the directory at the specified absolute path in the file system.]],
	makeDirectory = [[function(path:string):boolean -- Creates a directory at the specified absolute path in the file system. Creates parent directories, if necessary.]],
	seek = [[function(handle:userdata, whence:string, offset:number):number -- Seeks in an open file descriptor with the specified handle. Returns the new pointer position.]],
	getLabel = [[function():string -- Get the current label of the drive.]],
	remove = [[function(path:string):boolean -- Removes the object at the specified absolute path in the file system.]],
	spaceUsed = [[function():number -- The currently used capacity of the file system, in bytes.]],
	write = [[function(handle:userdata, value:string):boolean -- Writes the specified data to an open file descriptor with the specified handle.]]
}

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

local function list_contains(list, val)
	for i = 1,#list do
		if val == list[i] then return true end
	end
	return false
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

-- apparently you can setlabel even when readonly, so it's on purpose that i don't check
diskless.funcs.setLabel = function (uuid, newval)
	if diskless.pools[uuid] then
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

		if not diskless.pathHasParent(path2) then
			return false
		end

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

		if not pool[path] then
			if not diskless.pathHasParent(uuid, path) then return nil end -- has to have a parent dir
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

			if pool[handle.path] then
				if pool[handle.path].type == "file" then
					pool[handle.path] = nil -- erase old file
				end
			end

			if (not pool[handle.path]) then
				local size = diskless.funcs.spaceUsed(uuid)

				local fulldata = table.concat(handle.buf or {})

				if diskless.pools[uuid].sizeLimit and size + #fulldata > diskless.pools[uuid].sizeLimit then
					return "out of space" -- TODO: potentially properly do shit while writing instead of erroring on close lol
				end

				pool[handle.path] = {type = "file"}
				local file = pool[handle.path]

				file.lastModified = os.time()
				file.data = fulldata
			end

		end

		handles[handleID] = nil
	end
end

function diskless.pathHasParent(uuid, path)
	if diskless.pools[uuid] then
		path = diskless.fixPath(path)
		local pool = diskless.pools[uuid].pool

		local parts = string_split(path,"/")

		for k,v in pairs(pool) do
			if string_startswith(path, k) then
				local parts2 = string_split(k, "/")

				if #parts2 == #parts-1 then
					return true
				end
			end
		end

		return false
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

function diskless.makeRamFS(readonly, sizeLimit, isComponent)
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

	if isComponent then
		diskless.components[#diskless.components+1] = uuid
	end

	return uuid
end

function diskless.makeSimpleProxy(uuid) -- takes WAY less ram, but is  way more detectable
	if diskless.pools[uuid] then
		local prox = {}

		for k,v in pairs(diskless.funcs) do
			prox[k] = function (...)
				return v(uuid, ...)
			end
		end

		return prox
	end
end

function diskless.makeProxy(uuid)
	if diskless.pools[uuid] then
		local prox = {}

		for k,v in pairs(diskless.funcs) do
			prox[k] = setmetatable({},
				{
					__tostring = function (t)
						return diskless.filesystemDoc[k]
					end,
					__call = function (t, ...)
						diskless.funcs[k](uuid, ...)
					end
				}
			)
		end

		prox.address = uuid
		prox.type = "filesystem"
		prox.slot = -1 -- -1 is the value used for floppies that are outside the computer, in a disk drive, and also for raids
		               -- this means that, even though -1 looks weird as a slot, it's fairly undetectable.

		return prox
	end
end

-- this function does not check for readonly filesystems. this is on purpose.
function diskless.forceWrite(uuid, path, data)
	if diskless.pools[uuid] then
		path = diskless.fixPath(path)

		local pool = diskless.pools[uuid].pool

		if pool[path] then
			if pool[path].type ~= "file" then
				return "There's already a non-file in the path!"
			end
		end

		pool[path] = nil -- if there was alr a file

		if not diskless.pathHasParent(uuid,path) then return "The path doesn't have a parent directory!" end

		local spaceused = diskless.funcs.spaceUsed(uuid)

		if (diskless.pools[uuid].sizeLimit) and (spaceused + #data > diskless.pools[uuid].sizeLimit) then
			return "out of space"
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
		if list_contains(diskless.components,addr) then
			return diskless.funcs[func](addr, ...)
		end
	else
		return ci(addr,func,...)
	end
end

local cl = component.list
function component.list(filter, exact)
	local vals = cl(filter,exact)

	local add = false

	if not filter then
		add = true
	elseif exact and filter == "filesystem" then
		add = true
	elseif (not exact) and string_contains("filesystem", filter) then
		add = true
	elseif (not exact) and (#filter == 0) then
		add = true
	end

	if add then
		for i = 1,#diskless.components do
			local comp = diskless.components[i]
			vals[comp] = "filesystem"
		end
	end

	return vals
end

local compProx = component.proxy
function component.proxy(addr)
	if list_contains(diskless.components,addr) then
		return diskless.makeProxy(addr)
	else
		return compProx(addr)
	end
end

local cd = component.doc
function component.doc(addr, func)
	if list_contains(diskless.components,addr) then
		return filesystemDoc[func]
	else
		return cd(addr,func)
	end
end

return diskless