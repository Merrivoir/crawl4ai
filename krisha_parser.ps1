#Requires -Version 5.1
<#
.SYNOPSIS
    Парсер объявлений krisha.kz через локальный Crawl4AI.

.DESCRIPTION
    Забирает список объявлений с krisha.kz по заданным фильтрам и сохраняет в CSV.

    Особенности:
      * сортировка по умолчанию "сначала новые" (add_date-desc) — свежие сверху;
      * порядок выдачи сайта сохраняется (Id НЕ сортируется: он не коррелирует с датой);
      * фильтры поиска игнорируют два типа блоков:
          - "реклама" — платные объявления (класс tm-click-checked-hot-adv,
            источник source=hot_advert),
          - "ЖК" — реклама застройщиков (цена «от N», класс a-card__footer user-complex).
        Оба помечаются Promoted=true, колонка «Тип» показывает что это;
        ключ -ExcludePromoted убирает их из результата;
      * ключ -NewOnly сравнивает результат с прошлым запуском и печатает только
        новые объявления (удобно для мониторинга);
      * HTTP выполняется через curl.exe, потому что Invoke-RestMethod в
        PowerShell 5.1 ломает UTF-8 (кириллица превращается в mojibake).

.PARAMETER Url
    Полный URL поиска. Если задан — параметры фильтров ниже игнорируются.

.PARAMETER Category
    Раздел сайта. По умолчанию "prodazha/kvartiry" (продажа квартир).

.PARAMETER City
    Город, например "almaty". Пустая строка — без привязки к городу.

.PARAMETER Rooms
    Количество комнат, можно несколько: -Rooms 1,2,3

.PARAMETER PriceFrom / PriceTo
    Цена в тенге.

.PARAMETER SquareFrom / SquareTo
    Общая площадь, м².

.PARAMETER OnlyOwner
    Только объявления от собственника (без агентств).

.PARAMETER OnlyWithPhoto
    Только объявления с фотографиями.

.PARAMETER Pages
    Сколько страниц выдачи забрать (по 20-23 объявления на страницу).

.PARAMETER SortBy
    Сортировка: add_date-desc (по умолчанию, новые сверху), price-asc, price-desc.

.PARAMETER OutDir
    Каталог для результата. По умолчанию — текущий.

.PARAMETER NewOnly
    Печатать и сохранять только объявления, которых не было в прошлых запусках.

.PARAMETER ExcludePromoted
    Исключить рекламные объявления и карточки ЖК (оба типа игнорируют фильтры поиска).

.EXAMPLE
    .\krisha_parser.ps1 -City almaty -Rooms 2 -PriceTo 50000000

.EXAMPLE
    .\krisha_parser.ps1 -Rooms 1,2 -OnlyOwner -Pages 3

.EXAMPLE
    .\krisha_parser.ps1 -Url "https://krisha.kz/prodazha/kvartiry/almaty/?das%5Blive.rooms%5D=2"

.EXAMPLE
    .\krisha_parser.ps1 -Rooms 2 -NewOnly -ExcludePromoted
#>
[CmdletBinding()]
param(
    [string] $Url        = '',
    [string] $Category   = 'prodazha/kvartiry',
    [string] $City       = 'almaty',
    [int[]]  $Rooms      = @(),
    [long]   $PriceFrom  = 0,
    [long]   $PriceTo    = 0,
    [double] $SquareFrom = 0,
    [double] $SquareTo   = 0,
    [switch] $OnlyOwner,
    [switch] $OnlyWithPhoto,
    [ValidateRange(1, 100)]
    [int]    $Pages      = 1,
    [string] $SortBy     = 'add_date-desc',
    [string] $OutDir     = '.',
    [string] $ApiUrl     = 'http://localhost:11235',
    [int]    $DelaySec   = 1,
    [switch] $NewOnly,
    [switch] $ExcludePromoted,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# ─────────────────────────── вспомогательное ───────────────────────────

function Write-Step($msg) { if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan } }
function Write-Ok($msg)   { if (-not $Quiet) { Write-Host $msg -ForegroundColor Green } }
function Write-Warn2($msg){ Write-Host $msg -ForegroundColor Yellow }

function Get-ApiToken {
    $envFile = Join-Path $PSScriptRoot '.env'
    if (-not (Test-Path $envFile)) { throw "Не найден $envFile — там должен быть CRAWL4AI_API_TOKEN" }
    foreach ($line in [System.IO.File]::ReadAllLines($envFile, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^\s*CRAWL4AI_API_TOKEN\s*=\s*(.+?)\s*$') { return $Matches[1].Trim('"').Trim("'") }
    }
    throw 'CRAWL4AI_API_TOKEN не найден в .env'
}

function Test-Crawl4ai {
    try {
        $r = Invoke-WebRequest "$ApiUrl/health" -TimeoutSec 10 -UseBasicParsing
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

# curl.exe обязателен: Invoke-RestMethod в PS 5.1 портит UTF-8.
function Invoke-Crawl([string] $TargetUrl, [string] $Token) {
    $schema = @{
        baseSelector = '.a-card'
        fields = @(
            @{ name = 'title';     selector = '.a-card__title';                   type = 'text' }
            @{ name = 'titleCls';  selector = '.a-card__title';                   type = 'attribute'; attribute = 'class' }
            @{ name = 'price';     selector = '.a-card__price';                   type = 'text' }
            @{ name = 'address';   selector = '.a-card__subtitle';                type = 'text' }
            @{ name = 'date';      selector = '.a-card__stats-item:nth-child(2)'; type = 'text' }
            @{ name = 'views';     selector = '.a-view-count';                    type = 'text' }
            @{ name = 'footerCls'; selector = '.a-card__footer';                  type = 'attribute'; attribute = 'class' }
            @{ name = 'url';       selector = 'a.a-card__title'; type = 'attribute'; attribute = 'href' }
        )
    }
    $payload = @{
        urls = @($TargetUrl)
        crawler_config = @{
            type = 'CrawlerRunConfig'
            params = @{
                cache_mode = 'bypass'
                page_timeout = 60000
                extraction_strategy = @{
                    type = 'JsonCssExtractionStrategy'
                    params = @{ schema = @{ type = 'dict'; value = $schema } }
                }
            }
        }
    }
    $json = $payload | ConvertTo-Json -Depth 20 -Compress
    $bodyFile = Join-Path $env:TEMP ('krisha_body_{0}.json' -f $PID)
    $respFile = Join-Path $env:TEMP ('krisha_resp_{0}.json' -f $PID)
    [System.IO.File]::WriteAllText($bodyFile, $json, $Utf8NoBom)

    & curl.exe -s -X POST "$ApiUrl/crawl" `
        -H "Authorization: Bearer $Token" `
        -H 'Content-Type: application/json' `
        --data-binary "@$bodyFile" -o "$respFile" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "curl.exe завершился с кодом $LASTEXITCODE" }

    $raw = [System.IO.File]::ReadAllText($respFile, [System.Text.Encoding]::UTF8)
    Remove-Item $bodyFile, $respFile -Force -ErrorAction SilentlyContinue

    $obj = $raw | ConvertFrom-Json
    $res = $obj.results[0]
    if (-not $res.success) { throw "Краул не удался: $($res.error_message)" }
    if (-not $res.extracted_content) { return @() }
    return @($res.extracted_content | ConvertFrom-Json)
}

function ConvertTo-Listing($card, $now) {
    $rawUrl = "$($card.url)"
    $id = ''
    if ($rawUrl -match '/a/show/(\d+)') { $id = $Matches[1] }

    $priceText   = ("$($card.price)" -replace '\s+', ' ').Trim()
    $priceDigits = ($priceText -replace '\D', '')
    $priceVal    = 0L
    if ($priceDigits) { [void][long]::TryParse($priceDigits, [ref]$priceVal) }

    $views = 0
    [void][int]::TryParse((("$($card.views)") -replace '\D', ''), [ref]$views)

    $roomsN = ''; $area = ''; $floor = ''
    if ("$($card.title)" -match '^(\d+)')          { $roomsN = $Matches[1] }
    if ("$($card.title)" -match '([\d.]+)\s*м²')   { $area   = $Matches[1] }
    if ("$($card.title)" -match '(\d+/\d+)\s*этаж'){ $floor  = $Matches[1] }

    # «Горячие» (платные) объявления помечаются классом tm-click-checked-hot-adv
    # и параметром source=hot_advert в ссылке. Они игнорируют фильтры поиска.
    $isHot = $false
    if ("$($card.titleCls)" -match 'hot-adv')      { $isHot = $true }
    if ($rawUrl -match 'hot_advert|hot_block')     { $isHot = $true }

    # Карточки ЖК (новостройки): реклама застройщика. Цена показана как «от N»,
    # количество комнат/цена не относятся к конкретной квартире, а блокируют фильтры.
    $isComplex = $false
    if ("$($card.footerCls)" -match 'user-complex') { $isComplex = $true }
    if ($priceText -match '^\s*от\s*\d')            { $isComplex = $true }

    $kind = 'объявление'
    if ($isHot)     { $kind = 'реклама' }
    if ($isComplex) { $kind = 'ЖК' }

    $cleanUrl = $rawUrl
    if ($id) { $cleanUrl = "https://krisha.kz/a/show/$id" }

    [pscustomobject]@{
        Id        = $id
        Kind      = $kind
        Promoted  = [bool]($isHot -or $isComplex)
        Title     = ("$($card.title)"   -replace '\s+', ' ').Trim()
        Price     = $priceVal
        PriceText = $priceText
        Address   = ("$($card.address)" -replace '\s+', ' ').Trim()
        Rooms     = $roomsN
        Area      = $area
        Floor     = $floor
        Date      = ("$($card.date)"    -replace '\s+', ' ').Trim()
        Views     = $views
        Url       = $cleanUrl
        FetchedAt = $now
    }
}

function Build-SearchUrl {
    $q = New-Object System.Collections.Generic.List[string]
    if ($Rooms.Count -gt 0) { foreach ($r in $Rooms) { $q.Add("das%5Blive.rooms%5D=$r") } }
    if ($PriceFrom  -gt 0) { $q.Add("das%5Bprice%5D%5Bfrom%5D=$PriceFrom") }
    if ($PriceTo    -gt 0) { $q.Add("das%5Bprice%5D%5Bto%5D=$PriceTo") }
    if ($SquareFrom -gt 0) { $q.Add("das%5Blive.square%5D%5Bfrom%5D=$SquareFrom") }
    if ($SquareTo   -gt 0) { $q.Add("das%5Blive.square%5D%5Bto%5D=$SquareTo") }
    if ($OnlyOwner)        { $q.Add("das%5Bwho%5D=1") }
    if ($OnlyWithPhoto)    { $q.Add("das%5B_sys.hasphoto%5D=1") }
    if ($SortBy)           { $q.Add("sort_by=$SortBy") }

    $path = "https://krisha.kz/$Category"
    if ($City) { $path += "/$City" }
    $path += '/'
    if ($q.Count -gt 0) { return $path + '?' + ($q -join '&') }
    return $path
}

# ─────────────────────────────── основной ───────────────────────────────

$now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

if (-not (Test-Crawl4ai)) {
    throw "Crawl4AI не отвечает на $ApiUrl. Запустите: docker compose up -d"
}

if ($Url) {
    $baseUrl = $Url
} else {
    $baseUrl = Build-SearchUrl
}

$token = Get-ApiToken
Write-Step "Поиск: $baseUrl"
Write-Step "Страниц: $Pages$([Environment]::NewLine)"

$all = New-Object System.Collections.Generic.List[object]
for ($p = 1; $p -le $Pages; $p++) {
    $target = if ($p -eq 1) { $baseUrl } else {
        $sep = if ($baseUrl -match '\?') { '&' } else { '?' }
        "$baseUrl${sep}page=$p"
    }

    Write-Step "  стр. $p — $target"
    try {
        $cards = Invoke-Crawl -TargetUrl $target -Token $token
    } catch {
        Write-Warn2 "  ошибка на стр. ${p}: $($_.Exception.Message)"
        break
    }

    if (-not $cards -or @($cards).Count -eq 0) { Write-Step "  объявлений нет, останавливаюсь"; break }

    $parsed = @($cards | ForEach-Object { ConvertTo-Listing -card $_ -now $now } | Where-Object { $_.Id })
    $all.AddRange($parsed)
    Write-Step "  получено: $($parsed.Count)"

    if ($p -lt $Pages -and $DelaySec -gt 0) { Start-Sleep -Seconds $DelaySec }
}

if ($all.Count -eq 0) { Write-Warn2 'Ничего не найдено.'; return }

# Дедупликация по Id с СОХРАНЕНИЕМ порядка выдачи сайта.
# krisha по умолчанию отдаёт свежие сверху, поэтому порядок терять нельзя:
# сортировка по Id дала бы случайный порядок (Id не коррелирует с датой).
# ВАЖНО: @($list) в PowerShell 5.1 падает с ArgumentException — нужен .ToArray().
$uniq     = New-Object System.Collections.Generic.List[object]
$seenIds  = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($r in $all) { if ($seenIds.Add("$($r.Id)")) { $uniq.Add($r) } }
$dupCount = $all.Count - $uniq.Count
$all      = $uniq.ToArray()
if ($dupCount -gt 0) { Write-Step "Убрано дублей между страницами: $dupCount" }

if ($ExcludePromoted) {
    $before = $all.Count
    $all = @($all | Where-Object { -not $_.Promoted })
    Write-Step "Исключено рекламы и ЖК: $($before - $all.Count)"
}

# ─────────────────── отслеживание новых объявлений ───────────────────

if (-not (Test-Path $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
$stateFile = Join-Path $OutDir 'krisha_seen.json'
$csvFile   = Join-Path $OutDir 'krisha_listings.csv'

$seen = @{}
if (Test-Path $stateFile) {
    $prev = [System.IO.File]::ReadAllText($stateFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($x in @($prev)) { $seen["$x"] = $true }
}

$newOnes = @($all | Where-Object { -not $seen.ContainsKey($_.Id) })

# История просмотренных Id: старые + текущие, без дублей (порядок не важен).
$stateIds = New-Object System.Collections.Generic.List[string]
$stateSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in $seen.Keys) { if ($stateSet.Add("$k")) { $stateIds.Add("$k") } }
foreach ($r in $all)       { if ($stateSet.Add("$($r.Id)")) { $stateIds.Add("$($r.Id)") } }
$stateArr = $stateIds.ToArray()
$stateJson = '[]'
if ($stateArr.Count -gt 0) { $stateJson = ConvertTo-Json -InputObject $stateArr -Compress }
[System.IO.File]::WriteAllText($stateFile, $stateJson, $Utf8NoBom)

$export = @($all)
if ($NewOnly) { $export = @($newOnes) }
$export | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

# ───────────────────────────── вывод ─────────────────────────────

Write-Host ''
Write-Ok ("Всего объявлений: {0} (новых: {1})" -f $all.Count, $newOnes.Count)
Write-Ok "CSV: $csvFile"
Write-Host ''

$show = @($all)
if ($NewOnly) { $show = @($newOnes) }
if ($show.Count -gt 0) {
    $table = $show | Select-Object -First 15 `
        @{n='Комн'; e={$_.Rooms}}, `
        @{n='Цена'; e={$_.Price.ToString('N0')}}, `
        @{n='Площадь'; e={$_.Area}}, `
        @{n='Этаж'; e={$_.Floor}}, `
        @{n='Дата'; e={$_.Date}}, `
        @{n='Просм'; e={$_.Views}}, `
        @{n='Тип'; e={$_.Kind}}, `
        @{n='Адрес'; e={ if ($_.Address.Length -gt 40) { $_.Address.Substring(0,40) + '…' } else { $_.Address } }}
    $fmt = $table | Format-Table -AutoSize | Out-String -Width 200
    Write-Host $fmt
    if ($show.Count -gt 15) { Write-Host "  ... и ещё $($show.Count - 15). Полный список — в CSV." }
} else {
    Write-Host 'Новых объявлений нет.' -ForegroundColor Yellow
}
