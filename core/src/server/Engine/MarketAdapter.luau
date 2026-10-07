--!strict
-- Duenner Adapter um MarketplaceService.
--
-- Kauf-Handler: MarketplaceService.ProcessReceipt. Der Developer-Products-Leitfaden schreibt ProcessReceipt vor
-- ("must use ProcessReceipt"), Roblox prueft genau diese Implementierung fuer Produkte, die auch ausserhalb des
-- Spiels verkauft werden, und Enum.ProductPurchaseDecision ist dort der dokumentierte Rueckgabewert.
-- BindReceiptHandler (Enum.ReceiptDecision) ist als Alternative dokumentiert; ein Wechsel betrifft nur
-- setReceiptHandler und toDecision.
-- ownsPass: UserOwnsGamePassAsync (yieldet, kann werfen; Aufrufer kapseln in pcall).
-- onPassPromptFinished: PromptGamePassPurchaseFinished(player, gamePassId, wasPurchased) - nur Ausloeser einer
-- serverseitigen Besitzpruefung, nie selbst ein Kaufnachweis.
-- onProductPromptFinished: PromptProductPurchaseFinished(userId, productId, isPurchased) - laut Doku nie zum
-- Vergeben verwenden; hier nur fuer das Analytics-Event purchase_attempt.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/MarketplaceService
--       https://create.roblox.com/docs/production/monetization/developer-products
local PlayersAdapter = require(script.Parent.PlayersAdapter)

export type Decision = "PurchaseGranted" | "NotProcessedYet"

export type MarketAdapter = {
	setReceiptHandler: (self: MarketAdapter, handler: (receipt: any) -> Decision) -> (),
	ownsPass: (self: MarketAdapter, userId: number, passId: number) -> boolean,
	onPassPromptFinished: (
		self: MarketAdapter,
		callback: (player: any, passId: number, wasPurchased: boolean) -> ()
	) -> PlayersAdapter.Connection,
	onProductPromptFinished: (
		self: MarketAdapter,
		callback: (userId: number, productId: number, wasPurchased: boolean) -> ()
	) -> PlayersAdapter.Connection,
	clearReceiptHandler: (self: MarketAdapter) -> (),
}

local MarketAdapter = {}

-- Bildet die Entscheidung des Cores auf das Roblox-Enum ab; alles ausser "PurchaseGranted" ist NotProcessedYet.
function MarketAdapter.toDecision(decision: any): Enum.ProductPurchaseDecision
	if decision == "PurchaseGranted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MarketAdapter.new(marketplaceService: any?): MarketAdapter
	local service: any = marketplaceService or game:GetService("MarketplaceService")

	local adapter: MarketAdapter = {
		setReceiptHandler = function(_self, handler: (receipt: any) -> Decision)
			service.ProcessReceipt = function(receiptInfo: any): Enum.ProductPurchaseDecision
				local ok, decision = pcall(handler, receiptInfo)
				if not ok then
					warn("[MarketAdapter] receipt handler failed: " .. tostring(decision))
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				return MarketAdapter.toDecision(decision)
			end
		end,

		ownsPass = function(_self, userId: number, passId: number): boolean
			return service:UserOwnsGamePassAsync(userId, passId) == true
		end,

		onPassPromptFinished = function(_self, callback): PlayersAdapter.Connection
			return service.PromptGamePassPurchaseFinished:Connect(callback)
		end,

		onProductPromptFinished = function(_self, callback): PlayersAdapter.Connection
			return service.PromptProductPurchaseFinished:Connect(callback)
		end,

		clearReceiptHandler = function(_self)
			pcall(function()
				service.ProcessReceipt = nil
			end)
		end,
	}
	return adapter
end

return MarketAdapter
