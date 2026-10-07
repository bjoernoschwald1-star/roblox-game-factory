--!strict
-- Einstiegspunkt fuer den Luau-Execution-Task: fuehrt eine Suite aus, schreibt eine
-- Zusammenfassung in die Logs und bricht mit error() ab, wenn ein Test fehlschlaegt.
local Runner = require(script.Parent.Runner)
local Suites = require(script.Parent.Suites)

export type Summary = {
	suite: string,
	runId: string,
	passed: number,
	failed: number,
	total: number,
}

return function(suiteName: string, runId: string): Summary
	local specs = Suites[suiteName]
	if specs == nil then
		error(string.format("[spike] unknown suite %q", suiteName), 0)
	end

	local results = Runner.run(specs, { runId = runId })
	local passed, failed = 0, 0
	for _, result in results do
		if result.ok then
			passed += 1
			print(string.format("[spike] PASS %s", result.name))
		else
			failed += 1
			print(string.format("[spike] FAIL %s: %s", result.name, result.err or "?"))
		end
	end

	print(
		string.format(
			"[spike] SUMMARY suite=%s run=%s passed=%d failed=%d total=%d",
			suiteName,
			runId,
			passed,
			failed,
			#results
		)
	)

	if failed > 0 then
		error(string.format("[spike] suite %s failed: %d of %d tests failed", suiteName, failed, #results), 0)
	end

	return { suite = suiteName, runId = runId, passed = passed, failed = failed, total = #results }
end
