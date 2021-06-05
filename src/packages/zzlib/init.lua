-- zzlib - zlib decompression in Lua - Implementation-independent code

-- Copyright (c) 2016-2020 Francois Galea <fgalea at free.fr>
-- This program is free software. It comes without any warranty, to
-- the extent permitted by applicable law. You can redistribute it
-- and/or modify it under the terms of the Do What The Fuck You Want
-- To Public License, Version 2, as published by Sam Hocevar. See
-- the COPYING file or http://www.wtfpl.net/ for more details.


local unpack = unpack
local result

local infl do
	local inflate = {}
	
	local bit = getfenv(0).bit32
	
	inflate.band = bit.band
	inflate.rshift = bit.rshift
	
	function inflate.bitstream_init(file)
		local bs = {
			file = file,  -- the open file handle
			buf = nil,    -- character buffer
			len = nil,    -- length of character buffer
			pos = 1,      -- position in char buffer
			b = 0,        -- bit buffer
			n = 0,        -- number of bits in buffer
		}
		-- get rid of n first bits
		function bs:flushb(n)
			self.n = self.n - n
			self.b = bit.rshift(self.b,n)
		end
		-- peek a number of n bits from stream
		function bs:peekb(n)
			while self.n < n do
				if self.pos > self.len then
					self.buf = self.file:read(4096)
					self.len = self.buf:len()
					self.pos = 1
				end
				self.b = self.b + bit.lshift(self.buf:byte(self.pos),self.n)
				self.pos = self.pos + 1
				self.n = self.n + 8
			end
			return bit.band(self.b,bit.lshift(1,n)-1)
		end
		-- get a number of n bits from stream
		function bs:getb(n)
			local ret = bs:peekb(n)
			self.n = self.n - n
			self.b = bit.rshift(self.b,n)
			return ret
		end
		-- get next variable-size of maximum size=n element from stream, according to Huffman table
		function bs:getv(hufftable,n)
			local e = hufftable[bs:peekb(n)]
			local len = bit.band(e,15)
			local ret = bit.rshift(e,4)
			self.n = self.n - len
			self.b = bit.rshift(self.b,len)
			return ret
		end
		function bs:close()
			if self.file then
				self.file:close()
			end
		end
		if type(file) == "string" then
			bs.file = nil
			bs.buf = file
		else
			bs.buf = file:read(4096)
		end
		bs.len = bs.buf:len()
		return bs
	end
	
	local function hufftable_create(depths)
		local nvalues = #depths
		local nbits = 1
		local bl_count = {}
		local next_code = {}
		for i=1,nvalues do
			local d = depths[i]
			if d > nbits then
				nbits = d
			end
			bl_count[d] = (bl_count[d] or 0) + 1
		end
		local table = {}
		local code = 0
		bl_count[0] = 0
		for i=1,nbits do
			code = (code + (bl_count[i-1] or 0)) * 2
			next_code[i] = code
		end
		for i=1,nvalues do
			local len = depths[i] or 0
			if len > 0 then
				local e = (i-1)*16 + len
				local code2 = next_code[len]
				local rcode = 0
				for j=1,len do
					rcode = rcode + bit.lshift(bit.band(1,bit.rshift(code2,j-1)),len-j)
				end
				for j=0,2^nbits-1,2^len do
					table[j+rcode] = e
				end
				next_code[len] = next_code[len] + 1
			end
		end
		return table,nbits
	end
	
	local function block_loop(out,bs,nlit,ndist,littable,disttable)
		local lit
		repeat
			lit = bs:getv(littable,nlit)
			if lit < 256 then
				table.insert(out,lit)
			elseif lit > 256 then
				local nbits = 0
				local size = 3
				local dist = 1
				if lit < 265 then
					size = size + lit - 257
				elseif lit < 285 then
					nbits = bit.rshift(lit-261,2)
					size = size + bit.lshift(bit.band(lit-261,3)+4,nbits)
				else
					size = 258
				end
				if nbits > 0 then
					size = size + bs:getb(nbits)
				end
				local v = bs:getv(disttable,ndist)
				if v < 4 then
					dist = dist + v
				else
					nbits = bit.rshift(v-2,1)
					dist = dist + bit.lshift(bit.band(v,1)+2,nbits)
					dist = dist + bs:getb(nbits)
				end
				local p = #out-dist+1
				while size > 0 do
					table.insert(out,out[p])
					p = p + 1
					size = size - 1
				end
			end
		until lit == 256
	end
	
	local function block_dynamic(out,bs)
		local order = { 17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16 }
		local hlit = 257 + bs:getb(5)
		local hdist = 1 + bs:getb(5)
		local hclen = 4 + bs:getb(4)
		local depths = {}
		for i=1,hclen do
			local v = bs:getb(3)
			depths[order[i]] = v
		end
		for i=hclen+1,19 do
			depths[order[i]] = 0
		end
		local lengthtable,nlen = hufftable_create(depths)
		local i=1
		while i<=hlit+hdist do
			local v = bs:getv(lengthtable,nlen)
			if v < 16 then
				depths[i] = v
				i = i + 1
			elseif v < 19 then
				local nbt = {2,3,7}
				local nb = nbt[v-15]
				local c = 0
				local n = 3 + bs:getb(nb)
				if v == 16 then
					c = depths[i-1]
				elseif v == 18 then
					n = n + 8
				end
				for _=1,n do
					depths[i] = c
					i = i + 1
				end
			else
				error("wrong entry in depth table for literal/length alphabet: "..v);
			end
		end
		local litdepths = {}
		for _=1,hlit do
			table.insert(litdepths,depths[i])
		end
		local littable,nlit = hufftable_create(litdepths)
		local distdepths = {}
		for _=hlit+1,#depths do
			table.insert(distdepths,depths[i])
		end
		local disttable,ndist = hufftable_create(distdepths)
		block_loop(out,bs,nlit,ndist,littable,disttable)
	end
	
	local function block_static(out,bs)
		local cnt = { 144, 112, 24, 8 }
		local dpt = { 8, 9, 7, 8 }
		local depths = {}
		for i=1,4 do
			local d = dpt[i]
			for _=1,cnt[i] do
				table.insert(depths,d)
			end
		end
		local littable,nlit = hufftable_create(depths)
		depths = {}
		for i=1,32 do
			depths[i] = 5
		end
		local disttable,ndist = hufftable_create(depths)
		block_loop(out,bs,nlit,ndist,littable,disttable)
	end
	
	local function block_uncompressed(out,bs)
		bs:flushb(bit.band(bs.n,7))
		local len = bs:getb(16)
		if bs.n > 0 then
			error("Unexpected.. should be zero remaining bits in buffer.")
		end
		local nlen = bs:getb(16)
		if bit.bxor(len,nlen) ~= 65535 then
			error("LEN and NLEN don't match")
		end
		for i=bs.pos,bs.pos+len-1 do
			table.insert(out,bs.buf:byte(i,i))
		end
		bs.pos = bs.pos + len
	end
	
	function inflate.main(bs)
		local last,type
		local output = {}
		repeat
			last = bs:getb(1)
			type = bs:getb(2)
			if type == 0 then
				block_uncompressed(output,bs)
			elseif type == 1 then
				block_static(output,bs)
			elseif type == 2 then
				block_dynamic(output,bs)
			else
				error("unsupported block type")
			end
		until last == 1
		bs:flushb(bit.band(bs.n,7))
		return output
	end
	
	local crc32_table
	function inflate.crc32(s,crc)
		if not crc32_table then
			crc32_table = {}
			for i=0,255 do
				local r=i
				for _=1,8 do
					r = bit.bxor(bit.rshift(r,1),bit.band(0xedb88320,bit.bnot(bit.band(r,1)-1)))
				end
				crc32_table[i] = r
			end
		end
		crc = bit.bnot(crc or 0)
		for i=1,#s do
			local c = s:byte(i)
			crc = bit.bxor(crc32_table[bit.bxor(c,bit.band(crc,0xff))],bit.rshift(crc,8))
		end
		crc = bit.bnot(crc)
		if crc<0 then
			-- in Lua < 5.2, sign extension was performed
			crc = crc + 4294967296
		end
		return crc
	end
	
	infl = inflate
end

local zzlib = {}

local function arraytostr(array)
	local tmp = {}
	local size = #array
	local pos = 1
	local imax = 1
	while size > 0 do
		local bsize = size>=2048 and 2048 or size
		local s = string.char(unpack(array,pos,pos+bsize-1))
		pos = pos + bsize
		size = size - bsize
		local i = 1
		while tmp[i] do
			s = tmp[i]..s
			tmp[i] = nil
			i = i + 1
		end
		if i > imax then
			imax = i
		end
		tmp[i] = s
	end
	local str = ""
	for i=1,imax do
		if tmp[i] then
			str = tmp[i]..str
		end
	end
	return str
end

local function inflate_gzip(bs)
	local id1,id2,cm,flg = bs.buf:byte(1,4)
	if id1 ~= 31 or id2 ~= 139 then
		error("invalid gzip header")
	end
	if cm ~= 8 then
		error("only deflate format is supported")
	end
	bs.pos=11
	if infl.band(flg,4) ~= 0 then
		local xl1,xl2 = bs.buf.byte(bs.pos,bs.pos+1)
		local xlen = xl2*256+xl1
		bs.pos = bs.pos+xlen+2
	end
	if infl.band(flg,8) ~= 0 then
		local pos = bs.buf:find("\0",bs.pos)
		bs.pos = pos+1
	end
	if infl.band(flg,16) ~= 0 then
		local pos = bs.buf:find("\0",bs.pos)
		bs.pos = pos+1
	end
	if infl.band(flg,2) ~= 0 then
		-- TODO: check header CRC16
		bs.pos = bs.pos+2
	end
	local newResult = arraytostr(infl.main(bs))
	local crc = bs:getb(8)+256*(bs:getb(8)+256*(bs:getb(8)+256*bs:getb(8)))
	bs:close()
	if crc ~= infl.crc32(newResult) then
		error("checksum verification failed")
	end
	return newResult
end

-- compute Adler-32 checksum
local function adler32(s)
	local s1 = 1
	local s2 = 0
	for i=1,#s do
		local c = s:byte(i)
		s1 = (s1+c)%65521
		s2 = (s2+s1)%65521
	end
	return s2*65536+s1
end

local function inflate_zlib(bs)
	local cmf = bs.buf:byte(1)
	local flg = bs.buf:byte(2)
	if (cmf*256+flg)%31 ~= 0 then
		error("zlib header check bits are incorrect")
	end
	if infl.band(cmf,15) ~= 8 then
		error("only deflate format is supported")
	end
	if infl.rshift(cmf,4) ~= 7 then
		error("unsupported window size")
	end
	if infl.band(flg,32) ~= 0 then
		error("preset dictionary not implemented")
	end
	bs.pos=3
	local newResult = arraytostr(infl.main(bs))
	local adler = ((bs:getb(8)*256+bs:getb(8))*256+bs:getb(8))*256+bs:getb(8)
	bs:close()
	if adler ~= adler32(newResult) then
		error("checksum verification failed")
	end
	return newResult
end

function zzlib.gunzipf(filename)
	local file,err = io.open(filename,"rb")
	if not file then
		return nil,err
	end
	return inflate_gzip(infl.bitstream_init(file))
end

function zzlib.gunzip(str)
	return inflate_gzip(infl.bitstream_init(str))
end

function zzlib.inflate(str)
	return inflate_zlib(infl.bitstream_init(str))
end

local function int2le(str,pos)
	local a,b = str:byte(pos,pos+1)
	return b*256+a
end

local function int4le(str,pos)
	local a,b,c,d = str:byte(pos,pos+3)
	return ((d*256+c)*256+b)*256+a
end

function zzlib.unzip(buf)
	local p = #buf-21 - #("00bd21b8cc3a2e233276f5a70b57ca7347fdf520")
	local fileMap = {}
	if int4le(buf,p) ~= 0x06054b50 then
		-- not sure there is a reliable way to locate the end of central directory record
		-- if it has a variable sized comment field
		error(".ZIP file comments not supported")
	end
	local cdoffset = int4le(buf,p+16)
	local nfiles = int2le(buf,p+10)
	p = cdoffset+1
	for _=1,nfiles do
		if int4le(buf,p) ~= 0x02014b50 then
			error("invalid central directory header signature")
		end
		local method = int2le(buf,p+10)
		local crc = int4le(buf,p+16)
		local namelen = int2le(buf,p+28)
		local name = buf:sub(p+46,p+45+namelen)
		if true then
			local headoffset = int4le(buf,p+42)
			local p2 = 1+headoffset
			if int4le(buf,p2) ~= 0x04034b50 then
				error("invalid local header signature")
			end
			local csize = int4le(buf,p2+18)
			local extlen = int2le(buf,p2+28)
			p2 = p2+30+namelen+extlen
			if method == 0 then
				-- no compression
				result = buf:sub(p2,p2+csize-1)
				fileMap[name] = result
			else
				-- DEFLATE compression
				local bs = infl.bitstream_init(buf)
				bs.pos = p2
				result = arraytostr(infl.main(bs))
				fileMap[name] = result
			end
			if crc ~= infl.crc32(result) then
				error("checksum verification failed")
			end
		end
		p = p+46+namelen+int2le(buf,p+30)+int2le(buf,p+32)
	end
	return fileMap
end

return zzlib
