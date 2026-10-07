--!strict
-- Wiederkehrende Aufgaben. Echte Implementierung mit task.spawn/task.wait; Fake mit manuellem advance(seconds)
-- fuer Tests ohne Warten. Fehler einer Aufgabe beenden die Schleife nicht (pcall, gedrosselte Warnung).
local Log = require(script.Parent.Parent.Parent.shared.Log)

export type Scheduler = {
	every: (self: Scheduler, intervalSeconds: number, fn: () -> ()) -> () -> (),
}

export type FakeScheduler = Scheduler & {
	advance: (self: FakeScheduler, seconds: number) -> (),
	now: number,
}

type Job = {
	interval: number,
	nextAt: number,
	fn: () -> (),
	active: boolean,
}

local Scheduler = {}

local function run(log: Log.Log, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		log:warnThrottled("scheduler", "[Scheduler] task failed: " .. tostring(err))
	end
end

function Scheduler.new(log: Log.Log?): Scheduler
	local warnLog = log or Log.new()
	local scheduler: Scheduler = {
		every = function(_self, intervalSeconds: number, fn: () -> ()): () -> ()
			assert(intervalSeconds > 0, "Scheduler: interval must be > 0")
			local running = true
			task.spawn(function()
				while running do
					task.wait(intervalSeconds)
					if running then
						run(warnLog, fn)
					end
				end
			end)
			return function()
				running = false
			end
		end,
	}
	return scheduler
end

function Scheduler.fake(log: Log.Log?): FakeScheduler
	local warnLog = log or Log.new()
	local jobs: { Job } = {}
	local fake = {} :: FakeScheduler
	fake.now = 0
	fake.every = function(_self, intervalSeconds: number, fn: () -> ()): () -> ()
		assert(intervalSeconds > 0, "Scheduler: interval must be > 0")
		local job: Job = { interval = intervalSeconds, nextAt = fake.now + intervalSeconds, fn = fn, active = true }
		table.insert(jobs, job)
		return function()
			job.active = false
		end
	end
	-- Stellt die Zeit vor und fuehrt alle faelligen Aufgaben in zeitlicher Reihenfolge aus.
	fake.advance = function(_self, seconds: number)
		local target = fake.now + seconds
		while true do
			local due: Job? = nil
			for _, job in jobs do
				if job.active and job.nextAt <= target and (due == nil or job.nextAt < (due :: Job).nextAt) then
					due = job
				end
			end
			if due == nil then
				break
			end
			fake.now = due.nextAt
			due.nextAt += due.interval
			run(warnLog, due.fn)
		end
		fake.now = target
	end
	return fake
end

return Scheduler
