--!strict
-- Minimaler Testrunner ohne externe Pakete: describe/it/expect mit toBe und toEqual.

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
}

export type Api = {
	describe: (name: string, body: () -> ()) -> (),
	it: (name: string, body: () -> ()) -> (),
	expect: (actual: any) -> Expectation,
}

export type Context = {
	runId: string,
}

export type Spec = (t: Api, ctx: Context) -> ()

export type Result = {
	name: string,
	ok: boolean,
	err: string?,
}

type TestCase = {
	name: string,
	body: () -> (),
}

local Runner = {}

local function describeValue(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		for k, v in value do
			table.insert(parts, string.format("[%s]=%s", describeValue(k), describeValue(v)))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function expect(actual: any): Expectation
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(string.format("expected %s to be %s", describeValue(actual), describeValue(expected)), 0)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				error(string.format("expected %s to equal %s", describeValue(actual), describeValue(expected)), 0)
			end
		end,
	}
end

-- Sammelt alle Tests der Specs und fuehrt sie isoliert per pcall aus.
function Runner.run(specs: { Spec }, ctx: Context): { Result }
	local cases: { TestCase } = {}
	local prefix: { string } = {}

	local api: Api = {
		describe = function(name: string, body: () -> ())
			table.insert(prefix, name)
			body()
			table.remove(prefix)
		end,
		it = function(name: string, body: () -> ())
			local path = table.clone(prefix)
			table.insert(path, name)
			table.insert(cases, { name = table.concat(path, " > "), body = body })
		end,
		expect = expect,
	}

	for _, spec in specs do
		spec(api, ctx)
	end

	local results: { Result } = {}
	for _, case in cases do
		local ok, err = pcall(case.body)
		table.insert(results, { name = case.name, ok = ok, err = if ok then nil else tostring(err) })
	end
	return results
end

return Runner
