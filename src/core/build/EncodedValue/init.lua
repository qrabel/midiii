--[[
	This module was modified to handle results of the 'typeof' function, to be more lightweight.
	The original source of this module can be found in the link below, as well as the license:

	https://github.com/rojo-rbx/rojo/blob/master/plugin/rbx_dom_lua/EncodedValue.lua
	https://github.com/rojo-rbx/rojo/blob/master/plugin/rbx_dom_lua/base64.lua
	https://github.com/rojo-rbx/rojo/blob/master/LICENSE.txt
--]]

local base64
do
	-- Thanks to Tiffany352 for this base64 implementation!

	local floor = math.floor
	local char = string.char

	local function encodeBase64(str)
		local out = {}
		local nOut = 0
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local strLen = #str

		-- 3 octets become 4 hextets
		for i = 1, strLen - 2, 3 do
			local b1, b2, b3 = str:byte(i, i + 3)
			local word = b3 + b2 * 256 + b1 * 256 * 256

			local h4 = word % 64 + 1
			word = floor(word / 64)
			local h3 = word % 64 + 1
			word = floor(word / 64)
			local h2 = word % 64 + 1
			word = floor(word / 64)
			local h1 = word % 64 + 1

			out[nOut + 1] = alphabet:sub(h1, h1)
			out[nOut + 2] = alphabet:sub(h2, h2)
			out[nOut + 3] = alphabet:sub(h3, h3)
			out[nOut + 4] = alphabet:sub(h4, h4)
			nOut = nOut + 4
		end

		local remainder = strLen % 3

		if remainder == 2 then
			-- 16 input bits -> 3 hextets (2 full, 1 partial)
			local b1, b2 = str:byte(-2, -1)
			-- partial is 4 bits long, leaving 2 bits of zero padding ->
			-- offset = 4
			local word = b2 * 4 + b1 * 4 * 256

			local h3 = word % 64 + 1
			word = floor(word / 64)
			local h2 = word % 64 + 1
			word = floor(word / 64)
			local h1 = word % 64 + 1

			out[nOut + 1] = alphabet:sub(h1, h1)
			out[nOut + 2] = alphabet:sub(h2, h2)
			out[nOut + 3] = alphabet:sub(h3, h3)
			out[nOut + 4] = "="
		elseif remainder == 1 then
			-- 8 input bits -> 2 hextets (2 full, 1 partial)
			local b1 = str:byte(-1, -1)
			-- partial is 2 bits long, leaving 4 bits of zero padding ->
			-- offset = 16
			local word = b1 * 16

			local h2 = word % 64 + 1
			word = floor(word / 64)
			local h1 = word % 64 + 1

			out[nOut + 1] = alphabet:sub(h1, h1)
			out[nOut + 2] = alphabet:sub(h2, h2)
			out[nOut + 3] = "="
			out[nOut + 4] = "="
		end
		-- if the remainder is 0, then no work is needed

		return table.concat(out, "")
	end

	local function decodeBase64(str)
		local out = {}
		local nOut = 0
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local strLen = #str
		local acc = 0
		local nAcc = 0

		local alphabetLut = {}
		for i = 1, #alphabet do
			alphabetLut[alphabet:sub(i, i)] = i - 1
		end

		-- 4 hextets become 3 octets
		for i = 1, strLen do
			local ch = str:sub(i, i)
			local byte = alphabetLut[ch]
			if byte then
				acc = acc * 64 + byte
				nAcc = nAcc + 1
			end

			if nAcc == 4 then
				local b3 = acc % 256
				acc = floor(acc / 256)
				local b2 = acc % 256
				acc = floor(acc / 256)
				local b1 = acc % 256

				out[nOut + 1] = char(b1)
				out[nOut + 2] = char(b2)
				out[nOut + 3] = char(b3)
				nOut = nOut + 3
				nAcc = 0
				acc = 0
			end
		end

		if nAcc == 3 then
			-- 3 hextets -> 16 bit output
			acc = acc * 64
			acc = floor(acc / 256)
			local b2 = acc % 256
			acc = floor(acc / 256)
			local b1 = acc % 256

			out[nOut + 1] = char(b1)
			out[nOut + 2] = char(b2)
		elseif nAcc == 2 then
			-- 2 hextets -> 8 bit output
			acc = acc * 64
			acc = floor(acc / 256)
			acc = acc * 64
			acc = floor(acc / 256)
			local b1 = acc % 256

			out[nOut + 1] = char(b1)
		elseif nAcc == 1 then
			error("Base64 has invalid length")
		end

		return table.concat(out, "")
	end

	base64 = {
		decode = decodeBase64,
		encode = encodeBase64,
	}
end

local function identity(...)
	return ...
end

local function unpackDecoder(f)
	return function(value)
		return f(unpack(value))
	end
end

local function serializeFloat(value)
	-- TODO: Figure out a better way to serialize infinity and NaN, neither of
	-- which fit into JSON.
	if value == math.huge or value == -math.huge then
		return 999999999 * math.sign(value)
	end

	return value
end

local ALL_AXES = {"X", "Y", "Z"}
local ALL_FACES = {"Right", "Top", "Back", "Left", "Bottom", "Front"}

local types
types = {
	boolean = {
		fromPod = identity,
		toPod = identity,
	},

	number = {
		fromPod = identity,
		toPod = identity,
	},

	string = {
		fromPod = identity,
		toPod = identity,
	},

	EnumItem = {
		fromPod = identity,

		toPod = function(roblox)
			-- FIXME: More robust handling of enums
			if typeof(roblox) == "number" then
				return roblox
			else
				return roblox.Value
			end
		end,
	},

	Axes = {
		fromPod = function(pod)
			local axes = {}

			for index, axisName in ipairs(pod) do
				axes[index] = Enum.Axis[axisName]
			end

			return Axes.new(unpack(axes))
		end,

		toPod = function(roblox)
			local json = {}

			for _, axis in ipairs(ALL_AXES) do
				if roblox[axis] then
					table.insert(json, axis)
				end
			end

			return json
		end,
	},

	BinaryString = {	
		fromPod = base64.decode,	
		toPod = base64.encode,	
	},

	Bool = {	
		fromPod = identity,	
		toPod = identity,	
	},

	BrickColor = {
		fromPod = function(pod)
			return BrickColor.new(pod)
		end,

		toPod = function(roblox)
			return roblox.Number
		end,
	},

	CFrame = {
		fromPod = function(pod)
			local pos = pod.Position
			local orient = pod.Orientation

			return CFrame.new(
				pos[1], pos[2], pos[3],
				orient[1][1], orient[1][2], orient[1][3],
				orient[2][1], orient[2][2], orient[2][3],
				orient[3][1], orient[3][2], orient[3][3]
			)
		end,

		toPod = function(roblox)
			local x, y, z,
				r00, r01, r02,
				r10, r11, r12,
				r20, r21, r22 = roblox:GetComponents()

			return {
				Position = {x, y, z},
				Orientation = {
					{r00, r01, r02},
					{r10, r11, r12},
					{r20, r21, r22},
				},
			}
		end,
	},

	Color3 = {
		fromPod = unpackDecoder(Color3.new),

		toPod = function(roblox)
			return {roblox.r, roblox.g, roblox.b}
		end,
	},

	Color3uint8 = {	
		fromPod = unpackDecoder(Color3.fromRGB),	
		toPod = function(roblox)	
			return {	
				math.round(roblox.R * 255),	
				math.round(roblox.G * 255),	
				math.round(roblox.B * 255),	
			}	
		end,	
	},

	ColorSequence = {
		fromPod = function(pod)
			local keypoints = {}

			for index, keypoint in ipairs(pod.Keypoints) do
				keypoints[index] = ColorSequenceKeypoint.new(
					keypoint.Time,
					types.Color3.fromPod(keypoint.Color)
				)
			end

			return ColorSequence.new(keypoints)
		end,

		toPod = function(roblox)
			local keypoints = {}

			for index, keypoint in ipairs(roblox.Keypoints) do
				keypoints[index] = {
					Time = keypoint.Time,
					Color = types.Color3.toPod(keypoint.Value),
				}
			end

			return {
				Keypoints = keypoints,
			}
		end,
	},

	Content = {	
		fromPod = identity,	
		toPod = identity,	
	},

	Faces = {
		fromPod = function(pod)
			local faces = {}

			for index, faceName in ipairs(pod) do
				faces[index] = Enum.NormalId[faceName]
			end

			return Faces.new(unpack(faces))
		end,

		toPod = function(roblox)
			local pod = {}

			for _, face in ipairs(ALL_FACES) do
				if roblox[face] then
					table.insert(pod, face)
				end
			end

			return pod
		end,
	},

	Float32 = {	
		fromPod = identity,	
		toPod = serializeFloat,	
	},

	Float64 = {	
		fromPod = identity,	
		toPod = serializeFloat,	
	},

	Int32 = {	
		fromPod = identity,	
		toPod = identity,	
	},

	Int64 = {	
		fromPod = identity,	
		toPod = identity,	
	},

	NumberRange = {
		fromPod = unpackDecoder(NumberRange.new),

		toPod = function(roblox)
			return {roblox.Min, roblox.Max}
		end,
	},

	NumberSequence = {
		fromPod = function(pod)
			local keypoints = {}

			for index, keypoint in ipairs(pod.Keypoints) do
				keypoints[index] = NumberSequenceKeypoint.new(
					keypoint.Time,
					keypoint.Value,
					keypoint.Envelope
				)
			end

			return NumberSequence.new(keypoints)
		end,

		toPod = function(roblox)
			local keypoints = {}

			for index, keypoint in ipairs(roblox.Keypoints) do
				keypoints[index] = {
					Time = keypoint.Time,
					Value = keypoint.Value,
					Envelope = keypoint.Envelope,
				}
			end

			return {
				Keypoints = keypoints,
			}
		end,
	},

	PhysicalProperties = {
		fromPod = function(pod)
			if pod == "Default" then
				return nil
			else
				return PhysicalProperties.new(
					pod.Density,
					pod.Friction,
					pod.Elasticity,
					pod.FrictionWeight,
					pod.ElasticityWeight
				)
			end
		end,

		toPod = function(roblox)
			if roblox == nil then
				return "Default"
			else
				return {
					Density = roblox.Density,
					Friction = roblox.Friction,
					Elasticity = roblox.Elasticity,
					FrictionWeight = roblox.FrictionWeight,
					ElasticityWeight = roblox.ElasticityWeight,
				}
			end
		end,
	},

	Ray = {
		fromPod = function(pod)
			return Ray.new(
				types.Vector3.fromPod(pod.Origin),
				types.Vector3.fromPod(pod.Direction)
			)
		end,

		toPod = function(roblox)
			return {
				Origin = types.Vector3.toPod(roblox.Origin),
				Direction = types.Vector3.toPod(roblox.Direction),
			}
		end,
	},

	Rect = {
		fromPod = function(pod)
			return Rect.new(
				types.Vector2.fromPod(pod[1]),
				types.Vector2.fromPod(pod[2])
			)
		end,

		toPod = function(roblox)
			return {
				types.Vector2.toPod(roblox.Min),
				types.Vector2.toPod(roblox.Max),
			}
		end,
	},

	Instance = {
		fromPod = function(_pod)
			error("Ref cannot be decoded on its own")
		end,

		toPod = function(_roblox)
			error("Ref can not be encoded on its own")
		end,
	},

	Ref = {
		fromPod = function(_pod)
			error("Ref cannot be decoded on its own")
		end,
		toPod = function(_roblox)
			error("Ref can not be encoded on its own")
		end,
	},

	Region3 = {
		fromPod = function(pod)
			error("Region3 is not implemented")
		end,

		toPod = function(roblox)
			error("Region3 is not implemented")
		end,
	},

	Region3int16 = {
		fromPod = function(pod)
			return Region3int16.new(
				types.Vector3int16.fromPod(pod[1]),
				types.Vector3int16.fromPod(pod[2])
			)
		end,

		toPod = function(roblox)
			return {
				types.Vector3int16.toPod(roblox.Min),
				types.Vector3int16.toPod(roblox.Max),
			}
		end,
	},	

	SharedString = {	
		fromPod = function(pod)	
			error("SharedString is not supported")	
		end,	
		toPod = function(roblox)	
			error("SharedString is not supported")	
		end,	
	},

	String = {	
		fromPod = identity,	
		toPod = identity,	
	},

	UDim = {
		fromPod = unpackDecoder(UDim.new),

		toPod = function(roblox)
			return {roblox.Scale, roblox.Offset}
		end,
	},

	UDim2 = {
		fromPod = function(pod)
			return UDim2.new(
				types.UDim.fromPod(pod[1]),
				types.UDim.fromPod(pod[2])
			)
		end,

		toPod = function(roblox)
			return {
				types.UDim.toPod(roblox.X),
				types.UDim.toPod(roblox.Y),
			}
		end,
	},

	Vector2 = {
		fromPod = unpackDecoder(Vector2.new),

		toPod = function(roblox)
			return {
				serializeFloat(roblox.X),
				serializeFloat(roblox.Y),
			}
		end,
	},

	Vector2int16 = {
		fromPod = unpackDecoder(Vector2int16.new),

		toPod = function(roblox)
			return {roblox.X, roblox.Y}
		end,
	},

	Vector3 = {
		fromPod = unpackDecoder(Vector3.new),

		toPod = function(roblox)
			return {
				serializeFloat(roblox.X),
				serializeFloat(roblox.Y),
				serializeFloat(roblox.Z),
			}
		end,
	},

	Vector3int16 = {
		fromPod = unpackDecoder(Vector3int16.new),

		toPod = function(roblox)
			return {roblox.X, roblox.Y, roblox.Z}
		end,
	},
}

local EncodedValue = {}

function EncodedValue.decode(dataType, encodedValue)
	local typeImpl = types[dataType]
	if typeImpl == nil then
		return false, "Couldn't decode value " .. tostring(dataType)
	end

	return true, typeImpl.fromPod(encodedValue)
end

function EncodedValue.setProperty(obj, property, encodedValue, dataType)
	dataType = dataType or typeof(obj[property])
	local success, result = EncodedValue.decode(dataType, encodedValue)
	if success then
		obj[property] = result
	else
		warn("Could not set property " .. property .. " of " .. obj.GetFullName() .. "; " .. result)
	end
end

function EncodedValue.setProperties(obj, properties)
	for property, encodedValue in pairs(properties) do
		EncodedValue.setProperty(obj, property, encodedValue)
	end
end

function EncodedValue.setModelProperties(obj, properties)
	for property, encodedValue in pairs(properties) do
		EncodedValue.setProperty(obj, property, encodedValue.Value, encodedValue.Type)
	end
end

return EncodedValue
