--!strict
-- Tests 59-62: einziger Eingang fuer Client-Anfragen mit Schema-Pruefung und Rate Limit.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local RemoteGateway = require(FactoryCore.server.RemoteGateway)
local Log = require(FactoryCore.shared.Log)

local A = { userId = 101 }
local B = { userId = 202 }

type Env = {
	now: number,
	handled: { { any } },
	rejections: { { any } },
	warnings: { string },
	gateway: RemoteGateway.RemoteGateway,
}

local function newEnv(): Env
	local env = {} :: Env
	env.now = 0
	env.handled = {}
	env.rejections = {}
	env.warnings = {}
	local function clock()
		return env.now
	end
	env.gateway = RemoteGateway.new({
		clock = clock,
		log = Log.new({
			clock = clock,
			sink = function(message: string)
				table.insert(env.warnings, message)
			end,
		}),
		onRejected = function(ctx, name, err)
			table.insert(env.rejections, { ctx.userId, name, err })
		end,
	})
	local function record(name: string)
		return function(ctx, ...)
			table.insert(env.handled, { name, ctx.userId, ... })
		end
	end
	local relaxed = { max = 5, windowSeconds = 1 }
	env.gateway:register("collectAt", {
		args = { { type = "vector3", maxMagnitude = 1000 } },
		rateLimit = relaxed,
		handler = record("collectAt"),
	})
	env.gateway:register("buyUpgrade", {
		args = {
			{
				type = "id",
				isKnown = function(id: string): boolean
					return id == "range_boost"
				end,
			},
		},
		rateLimit = relaxed,
		handler = record("buyUpgrade"),
	})
	env.gateway:register("setOption", {
		args = {
			{ type = "string", maxLength = 8, oneOf = { "low", "high" } },
			{ type = "number", min = 0, max = 10, integer = true },
			{ type = "boolean" },
		},
		rateLimit = relaxed,
		handler = record("setOption"),
	})
	env.gateway:register("ping", { args = {}, rateLimit = { max = 3, windowSeconds = 1 }, handler = record("ping") })
	env.gateway:register("explode", {
		args = {},
		rateLimit = relaxed,
		handler = function()
			error("handler bug")
		end,
	})
	env.gateway:seal()
	return env
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("remote gateway", function()
		t.it("59 a valid call reaches the handler with the correct arguments", function()
			local env = newEnv()
			t.expect({ env.gateway:dispatch(A, "buyUpgrade", "range_boost") }).toEqual({ true })
			t.expect({ env.gateway:dispatch(A, "setOption", "high", 7, true) }).toEqual({ true })
			t.expect({ env.gateway:dispatch(A, "collectAt", Vector3.new(1, 2, 3)) }).toEqual({ true })
			t.expect(env.handled).toEqual({
				{ "buyUpgrade", 101, "range_boost" },
				{ "setOption", 101, "high", 7, true },
				{ "collectAt", 101, Vector3.new(1, 2, 3) },
			})
			t.expect(env.gateway:rejectedCount(A)).toBe(0)
		end)

		t.it(
			"60 unknown remote, extra price argument, wrong types, out of range, NaN, inf, unknown id rejected",
			function()
				local env = newEnv()
				local cases: { { any } } = {
					{ "sellAll", "UNKNOWN_REMOTE" },
					{ "buyUpgrade", "BAD_ARGS", "range_boost", 999999 },
					{ "buyUpgrade", "BAD_ARGS" },
					{ "buyUpgrade", "BAD_ARGS", 42 },
					{ "buyUpgrade", "BAD_ARGS", "unknown_dimension" },
					{ "setOption", "BAD_ARGS", "low", 11, true },
					{ "setOption", "BAD_ARGS", "low", 0 / 0, true },
					{ "setOption", "BAD_ARGS", "low", 1.5, true },
					{ "setOption", "BAD_ARGS", "medium", 1, true },
					{ "setOption", "BAD_ARGS", "low", 1, "yes" },
					{ "collectAt", "BAD_ARGS", Vector3.new(math.huge, 0, 0) },
					{ "collectAt", "BAD_ARGS", Vector3.new(5000, 0, 0) },
					{ "collectAt", "BAD_ARGS", { X = 1, Y = 2, Z = 3 } },
				}
				for index, case in cases do
					local name, expected = case[1], case[2]
					local ok, err = env.gateway:dispatch(A, name, table.unpack(case, 3))
					t.expect({ index, ok, err }).toEqual({ index, false, expected })
				end
				t.expect(#env.handled).toBe(0)
				t.expect(env.gateway:rejectedCount(A)).toBe(#cases)
				t.expect(#env.rejections).toBe(#cases)
				t.expect(env.rejections[1]).toEqual({ 101, "sellAll", "UNKNOWN_REMOTE" })
				t.expect(env.gateway:rejectedCount(B)).toBe(0)
			end
		)

		t.it("61 flood: more than max calls per window are RATE_LIMITED; separate per player and remote", function()
			local env = newEnv()
			for _ = 1, 3 do
				t.expect((env.gateway:dispatch(A, "ping"))).toBe(true)
			end
			local ok, err = env.gateway:dispatch(A, "ping")
			t.expect({ ok, err }).toEqual({ false, "RATE_LIMITED" })
			t.expect((env.gateway:dispatch(B, "ping"))).toBe(true)
			t.expect((env.gateway:dispatch(A, "buyUpgrade", "range_boost"))).toBe(true)

			env.now = 1
			t.expect((env.gateway:dispatch(A, "ping"))).toBe(true)
			t.expect(env.gateway:rejectedCount(A)).toBe(1)
			env.gateway:clearPlayer(A)
			t.expect(env.gateway:rejectedCount(A)).toBe(0)
		end)

		t.it("62 throwing handler gives HANDLER_ERROR and the gateway keeps working; seal is enforced", function()
			local env = newEnv()
			local ok, err = env.gateway:dispatch(A, "explode")
			t.expect({ ok, err }).toEqual({ false, "HANDLER_ERROR" })
			t.expect(#env.warnings).toBe(1)
			t.expect((env.gateway:dispatch(A, "ping"))).toBe(true)

			local registerAfterSeal = pcall(env.gateway.register, env.gateway, "late", {
				args = {},
				rateLimit = { max = 1, windowSeconds = 1 },
				handler = function() end,
			})
			t.expect(registerAfterSeal).toBe(false)
			local unsealed = RemoteGateway.new()
			t.expect((pcall(unsealed.dispatch, unsealed, A, "ping"))).toBe(false)
		end)
	end)
end
