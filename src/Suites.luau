--!strict
-- Suite-Definitionen: "red" = "green" + ein absichtlich fehlschlagender Test.
local Runner = require(script.Parent.Runner)
local specs = script.Parent.specs

local Trivial = require(specs.Trivial) :: Runner.Spec
local DataStore = require(specs.DataStore) :: Runner.Spec
local Failing = require(specs.Failing) :: Runner.Spec

local Suites: { [string]: { Runner.Spec } } = {
	green = { Trivial, DataStore },
	red = { Trivial, DataStore, Failing },
}

return Suites
