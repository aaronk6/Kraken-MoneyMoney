-- Inofficial Kraken Extension (www.kraken.com) for MoneyMoney
-- Fetches balances from Kraken API and returns them as securities
--
-- Username: Kraken API Key
-- Password: Kraken API Secret
--
-- Copyright (c) 2024 aaronk6, zacczakk
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
  version = 1.11,
  url = "https://api.kraken.com",
  description = "Fetch balances from Kraken API and list them as securities",
  services= { "Kraken Account" },
}

local apiKey
local apiSecret
local apiVersion = 0
local currency = "EUR" -- fixme: Don't hardcode
local currencyName = "ZEUR" -- fixme: Don't hardcode
local stakeSuffix = '.S'
local optInRewardsSuffix = '.M'
local bitcoin = 'XXBT'
local ethereum = 'XETH'
local market = "Kraken"
local accountName = "Balances"
local accountNumber = "Main"
local balances

-- The currency names cannot be retrieved via the API, therefore hardcoding them (could use
-- web scraping instead).

-- Source: https://support.kraken.com/hc/en-us/articles/201893658-Currency-pairs-available-for-trading-on-Kraken
-- Retrieved on: May 7, 2019

-- Further currency names added on July 19, 2022 and on February 9, 2023, but the list is still incomplete.

local currencyNames = {

  -- crypto
  ADA = "Cardano",
  APE = "ApeCoin",
  ASTR = "Astar",
  ATOM = "Cosmos",
  AVAX = "Avalanche",
  BCH = "Bitcoin Cash",
  DAI = "Dai",
  DASH = "Dash",
  DOT = "Polkadot",
  DOT28 = "Polkadot Fixed 28",
  EOS = "EOS",
  ETH2 = "Ethereum 2.0",
  ETHW = "Ethereum (PoW)",
  FTM = "Fantom",
  GNO = "Gnosis",
  LINK = "Chainlink",
  LUNA = "Terra Classic",
  LUNA2 = "Terra 2.0",
  MATIC = "Polygon",
  MINA = "Mina",
  QTUM = "QTUM",
  SHIB = "Shiba Inu",
  SOL = "Solana",
  TRX = "Tron",
  UNI = "Uniswap",
  USDC = "USD Coin",
  USDT = "Tether (Omni Layer)",
  WBTC = "Wrapped Bitcoin",
  XETC = "Ethereum Classic",
  XETH = "Ethereum",
  XLTC = "Litecoin",
  XMLN = "Watermelon",
  XREP = "Augur",
  XTZ = "Tezos",
  XXBT = "Bitcoin",
  XBT = "Bitcoin",
  XXDG = "Dogecoin",
  XXLM = "Stellar Lumens",
  XXMR = "Monero",
  XXRP = "Ripple",
  XZEC = "Zcash",

  -- fiat
  ZCAD = "Canadian Dollar",
  ZEUR = "Euro",
  ZGBP = "Great British Pound",
  ZJPY = "Japanese Yen",
  ZUSD = "US Dollar"
}

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Kraken Account"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  apiKey = username
  apiSecret = password

  balances = queryPrivate("Balance")
  assetPairs = queryPublic("AssetPairs")
  prices = queryPublic("Ticker", { pair = table.concat(buildPairs(balances, assetPairs), ',') })
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
  local pair, bitcoinPair, targetCurrency, price
  local s = {}

  for key, value in pairs(balances) do
    pair, targetCurrency = getPairInfo(key)
    name = resolveCurrencyName(key)
    if prices[pair] ~= nil or key == currencyName then
      price = prices[pair] ~= nil and prices[pair]["b"][1] or 1

      -- If this currency pair cannot be changed to fiat directly, we get the price
      -- in Bitcoin or Ethereum here and need to convert it to the correct fiat amount.
      if targetCurrency == bitcoin then
        price = price * prices[getPairInfo(bitcoin)]["b"][1]
      elseif targetCurrency == ethereum then
        price = price * prices[getPairInfo(ethereum)]["b"][1]
      end
      if tonumber(value) > 0 then
        s[#s+1] = {
          name = name,
          market = market,
          currency = nil,
          quantity = value,
          price = price
        }
      end
    end
  end

  return {securities = s}
end

function EndSession ()
end

function resolveCurrencyName(key)

  local keyWithoutSuffix = removeSuffix(removeSuffix(key, stakeSuffix), optInRewardsSuffix)
  local isStaked = key ~= keyWithoutSuffix

  if isStaked and currencyNames[keyWithoutSuffix] ~=nil then
    return currencyNames[keyWithoutSuffix] ..  ' (staked)'
  elseif currencyNames[key] then
    return currencyNames[key]
  end

  -- If we cannot resolve the key to a name, return the unmodified key.
  return key
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
  json = JSON(applyFillerWorkaround(content))

  return json:dictionary()["result"]
end

function queryPublic(method, request)
  local path = string.format("/%s/public/%s", apiVersion, method)
  local queryParams = ""

  if request ~= nil and next(request) ~= nil then
    queryParams = "?" .. httpBuildQuery(request)
  end
  
  local urlWithParams = url .. path .. queryParams
  local content = connection:request("GET", urlWithParams, "")
  local json = JSON(applyFillerWorkaround(content))
  
  return json:dictionary()["result"]
end

function applyFillerWorkaround(content)
  local fixVersion = '2.3.4'
  if versionCompare(MM.productVersion, fixVersion) == -1 then
    print("Adding filler to work around bug in product versions earlier than " .. fixVersion)
    return '{"filler":"' .. string.rep('x', 2048) .. '",' .. string.sub(content, 2)
  end
  return content
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
  local pair = ''
  local defaultPair = bitcoin .. currencyName
  local t = {}

  -- Always add default pair (i.e. XXBTZEUR)
  -- If we don't add it, fiat price calculation for currencies that don't have a fiat
  -- trading pair (such as Dogecoin) will fail in accounts that don't own Bitcoin.
  table.insert(t, defaultPair)

  for key, value in pairs(assetPairs) do
    if balances[value["base"]] ~= nil or balances[value["quote"]] ~= nil then
      if (key ~= defaultPair) then
        table.insert(t, key)
      end
    end
  end

  return t
end

function getPairInfo(base)


  -- support for staked coins (cut off stakeSuffix so that the currency can be found in asset pairs)
  base = removeSuffix(base, stakeSuffix)

  -- support for Opt-In Rewards, e.g. Bitcoin "staking" (XBT.M)
  base = removeSuffix(base, optInRewardsSuffix)

  -- rename "staked" XBT to XXBT so it can be found in the asset pair list
  if base == 'XBT' then
    base = 'XXBT'
  end

  local opt1 = base .. currency
  local opt2 = base .. currencyName
  local opt3 = base .. bitcoin
  local opt4 = base .. ".SETH"

  if assetPairs[opt1] ~= nil then return opt1, currency
  elseif assetPairs[opt2] ~= nil then return opt2, currencyName
  -- opt3: currency cannot be changed to fiat directly, only to Bitcoin (applies to Lumen, Dogecoin)
  elseif assetPairs[opt3] ~= nil then return opt3, bitcoin
  -- opt4: currency cannot be changed to fiat or Bitcoin, only to Ethereum (applies to staked Ethereum 2.0)
  elseif assetPairs[opt4] then return opt4, ethereum
  end

  return nil
end

function removeSuffix(str, suffix)
  if ends_with(str, suffix) then
    return str:sub(1, -#suffix-1)
  end
  return str
end

function versionCompare(version1, version2)
  -- based on https://helloacm.com/how-to-compare-version-numbers-in-c/

  local v1 = split(version1, '.')
  local v2 = split(version2, '.')

  if #v1 ~= #v2 then error("version1 and version2 need to have the same number of fields") end

  for i = 1, #v1 do
    local n1 = tonumber(v1[i])
    local n2 = tonumber(v2[i])
    if n1 > n2 then return 1
    elseif n1 < n2 then return -1
    end
  end

  return 0
end

function split(str, delimiter)
  -- from http://lua-users.org/wiki/SplitJoin
  local t, ll
  t = {}
  ll = 0
  if #str == 1 then return {str} end
  while true do
    l = string.find(str, delimiter, ll, true)
    if l ~= nil then
      table.insert(t, string.sub(str, ll, l-1))
      ll = l + 1
    else
      table.insert(t, string.sub(str, ll))
      break
    end
  end
  return t
end

function ends_with(str, ending)
  -- from http://lua-users.org/wiki/StringRecipes
  return ending == "" or str:sub(-#ending) == ending
end
