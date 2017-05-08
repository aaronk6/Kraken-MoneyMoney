-- Inofficial Kraken Extension (www.kraken.com) for MoneyMoney
-- Fetches balances from Kraken API and returns them as securities
--
-- Username: Kraken API Key
-- Password: Kraken API Secret
--
-- Copyright (c) 2017 aaronk6
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

WebBanking{
  version = 1.01,
  url = "https://api.kraken.com",
  description = "Fetch balances from Kraken API and list them as securities",
  services= { "Kraken Account" },
}

local apiKey
local apiSecret
local apiVersion = 0
local currency = "EUR" -- fixme: Don't hardcode
local currencyName = "ZEUR" -- fixme: Don't hardcode
local market = "Kraken"
local accountName = "Balances"
local accountNumber = "Main"
local balances

-- These cannot be retrieved via the API, therefore hardcoding them (could use
-- web scraping instead) Source: https://www.kraken.com/help/fees
local currencyNames = {
  DASH = "Dash",
  GNO = "Gnosis",
  USDT = "Tether USD",
  XETC = "Ether Classic",
  XETH = "Ether",
  XICN = "Iconomi",
  XLTC = "Litecoin",
  XMLN = "Melon",
  XREP = "Augur",
  XXBT = "Bitcoin",
  XXDG = "Dogecoin",
  XXLM = "Lumen",
  XXMR = "Monero",
  XXRP = "Ripple",
  XZEC = "Zcash",
  ZEUR = "Euro",
  ZUSD = "US Dollar",
  ZCAD = "Canadian Dollar",
  ZGBP = "Great British Pound",
  ZJPY = "Japanese Yen"
}

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Kraken Account"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  apiKey = username
  apiSecret = password

  balances = queryPrivate("Balance")
  assetPairs = queryPublic("AssetPairs")
  prices = queryPublic("Ticker", { pair = buildPairs(balances, assetPairs) })
end

function ListAccounts (knownAccounts)
  local account = {
    name = accountName,
    accountNumber = accountNumber,
    currency = currency,
    portfolio = true,
    type = "AccountTypePortfolio"
  }

  return {account}
end

function RefreshAccount (account, since)
  local name
  local pair
  local s = {}

  for key, value in pairs(balances) do
    pair = key .. currencyName
    name = currencyNames[key] ~= nil and currencyNames[key] or key
    if prices[pair] ~= nil then
      s[#s+1] = {
        name = name,
        market = market,
        currency = nil,
        quantity = value,
        price = prices[pair]["b"][1]
      }
    end
  end

  return {securities = s}
end

function EndSession ()
end

function queryPrivate(method, request)
  if request == nil then
    request = {}
  end

  local path = string.format("/%s/private/%s", apiVersion, method)
  local nonce = string.format("%d", math.floor(MM.time() * 1000000))
  request["nonce"] = nonce
  local postData = httpBuildQuery(request)
  local apiSign = MM.hmac512(MM.base64decode(apiSecret), path .. hex2str(MM.sha256(nonce .. postData)))
  local headers = {}

  headers["API-Key"] = apiKey
  headers["API-Sign"] = MM.base64(apiSign)

  connection = Connection()
  content = connection:request("POST", url .. path, postData, nil, headers)

  json = JSON(content)

  return json:dictionary()["result"]
end

function queryPublic(method, request)
  if request == nil then
    request = {}
  end

  local path = string.format("/%s/public/%s", apiVersion, method)
  local postData = httpBuildQuery(request)

  connection = Connection()
  content = connection:request("POST", url .. path, postData)
  json = JSON(content)

  return json:dictionary()["result"]
end

function hex2str(hex)
 return (hex:gsub("..", function (byte)
   return string.char(tonumber(byte, 16))
 end))
end

function httpBuildQuery(params)
  local str = ''
  for key, value in pairs(params) do
    str = str .. key .. "=" .. value .. "&"
  end
  return str.sub(str, 1, -2)
end

function buildPairs(balances, assetPairs)
  local str = ''
  for key, value in pairs(assetPairs) do
    if balances[value["base"]] ~= nil or balances[value["quote"]] ~= nil then
      str = str .. key .. ","
    end
  end
  return str.sub(str, 1, -2)
end
