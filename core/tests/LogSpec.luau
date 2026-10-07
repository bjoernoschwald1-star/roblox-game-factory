--!strict
-- Tests 46-47: gedrosselte Warnungen.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Log = require(FactoryCore.shared.Log)
local Modifiers = require(FactoryCore.server.Modifiers)

type Env = {
	now: number,
	messages: { string },
	log: Log.Log,
}

local function newEnv(): Env
	local env = {} :: Env
	env.now = 0
	env.messages = {}
	env.log = Log.new({
		clock = function()
			return env.now
		end,
		intervalSeconds = 60,
		sink = function(message: string)
			table.insert(env.messages, message)
		end,
	})
	return env
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("log", function()
		t.it("46 same key once per interval, then with (+N suppressed); different keys independent", function()
			local env = newEnv()
			env.log:warnThrottled("a", "first a")
			env.log:warnThrottled("a", "second a")
			env.log:warnThrottled("b", "first b")
			env.now = 30
			env.log:warnThrottled("a", "third a")
			t.expect(env.messages).toEqual({ "first a", "first b" })

			env.now = 60
			env.log:warnThrottled("a", "fourth a")
			env.log:warnThrottled("b", "second b")
			t.expect(env.messages).toEqual({ "first a", "first b", "fourth a (+2 suppressed)", "second b" })

			env.now = 200
			env.log:warnThrottled("a", "fifth a")
			t.expect(env.messages[5]).toBe("fifth a")
		end)

		t.it("47 Modifiers with a failing source: 100 queries within 1 second produce exactly one warning", function()
			local env = newEnv()
			local modifiers = Modifiers.new({ base = { range = 10 }, log = env.log })
			modifiers:registerSource("broken", function(): { [string]: any }
				error("source down")
			end)
			for _ = 1, 100 do
				t.expect(modifiers:value({ userId = 101 }, "range")).toBe(10)
				env.now += 0.01
			end
			t.expect(#env.messages).toBe(1)
			t.expect(string.find(env.messages[1], "[Modifiers] source broken failed", 1, true) ~= nil).toBe(true)
		end)
	end)
end
