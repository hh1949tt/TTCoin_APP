import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// ======================================================================
// TTCoin 主视图
//
// Watch App 版：主页面展示价格 + 24h 涨跌，Start 呼出设置菜单，
// Up/Down 手动翻页。数据仍来自自建 PHP 接口（见 api/lib.php）。
// ======================================================================

class TTCoinView extends WatchUi.View {

    // 行情接口地址：可在手机端 Garmin Connect 的应用设置里改（属性 apiUrl）。
    // 这里只是兜底默认值——手机端没填或填了非法值时用它，见 apiEndpoint()。
    const DEFAULT_API = "https://api.example.com/ttcoin/api/coin.php";

    // 兜底候选表：只在"还没成功拿到过接口数据"（首次启动且离线）时，
    // 用来撑起菜单和默认顺序。正常运行时候选与顺序一律以接口返回为准
    // （服务端 lib.php 的 ttcoin_symbols() 顺序），客户端不再维护第二份真相。
    const COINS = [
        "BTC", "ETH", "DOGE", "SHIB", "SOL", "BNB",
        "XRP", "ADA", "LINK", "LTC", "AVAX"
    ];

    // 默认显示前几个（按接口顺序数）。用户没动过任何勾选时生效。
    const DEFAULT_COUNT = 3;

    // properties.xml 里的编译期初始勾选。只用于判断"用户到底动没动过设置"：
    // 全部与这张表一致 → 认为没动过 → 按接口顺序取前 DEFAULT_COUNT 个；
    // 只要有一项不一致 → 认为用户配过了 → 完全按属性值来。
    const BUILTIN_ON = ["BTC", "ETH", "DOGE"];

    const PAGE_ROWS = 2;     // 一屏显示几个币种（每个币种占两行：价格 + 涨跌）
    const PAGE_MS = 8000;    // 轮播间隔：币种超过一屏时每页停留时长

    // 轮播与抓取共用一个 Timer：每 PAGE_MS 走一拍，
    // 每 FETCH_TICKS 拍真正发一次行情请求（8 × 8s ≈ 64s），
    // 中间的拍只用来翻页，不再需要第二个定时器实例。
    const FETCH_TICKS = 8;

    // 配置存储
    const PROP_PREFIX = "enabled";          // 手机端设置的布尔项：enabledBTC...
    const ORDER_KEY = "ttcoin_order";       // 手表菜单写的顺序表（Storage 数组）

    // ---------------- 布局基准 ----------------
    // 所有坐标以 176×176（Instinct 2X）为参考设计，绘制时按实际屏幕宽高等比缩放。
    //
    // ⚠️ 这张表的屏幕不是矩形，真正能画的区域比 176×176 小很多
    //    （见 SDK 里 resources/device-reference/instinct2x/layout0.svg 的 mask）：
    //      1) 四角被切掉，是个八边形：左上斜边满足 x + y = 39.6；
    //      2) 右上角是手电筒灯孔：圆心 (144, 31)、r=31 的"内径"；
    //         设备皮肤上那圈金属环再往外一圈，实测：可见内径 x 113..175、y 0..62，
    //         环本身宽约 6px（x 107..113），环外下沿到 y≈68。
    //    关键结论（逐像素扫模拟器截图得到）：环"内部"是能画的，被吃掉的
    //    只是环带本身。所以灯孔里可以放 TT 标，而压低到 y≈68 以下才能整行宽。
    //    踩过的两次坑：
    //      · 第一版把标题放 y=8、首行价格放 y≈35，价格尾数整段被环带盖住，
    //        显示成 "BTC 7560____.49"；
    //      · 第二版按 r=31 只让到 64，首行仍然蹭到环的下沿。
    //    所以：整行宽的内容从 y=76 起排，标题和页码挤进左上角斜边与灯孔之间的空档。
    const REF_WIDTH = 176;
    const REF_HEIGHT = 176;

    // 标题区：左侧从八边形斜边（x≈2）到灯孔外环左沿（x≈107），取中点
    const TITLE_CX = 55;        // 副标题的水平中心（不是左边界）
    const TITLE_Y = 26;         // 副标题 cell 顶部（字面约落在 31..44）
    const PAGE_DY = 18;         // 页码行相对副标题 cell 的下移量（字面 50..62，与标题留 4px）

    // 时钟：画在副标题正上方，与它共用同一条垂直轴（TITLE_CX）。
    // 这里用 FONT_TINY 而不是 FONT_SMALL：副标题从 y=26 起排，上面只剩 26px，
    // FONT_SMALL 的字高约 21px，一放就把左上角的八边形斜边（x+y=39.6）蹭掉一笔。
    const CLOCK_Y = 8;          // 时钟 cell 顶部（字面约 12..24，与副标题留 2px）

    // 灯孔里放 TT 标（实测：灯孔内部是可绘的，只有那圈 6px 宽的金属环盖住屏幕）
    const BADGE_CX = 144;
    const BADGE_CY = 31;

    const CONTENT_TOP = 69;     // 第一个币种价格 cell 顶部（字面约落在 76..91）
    const BLOCK_PITCH = 50;     // 一组（价格 + 涨跌）占的高度（组内留 8px，组间留 13px）
    const PRICE_TO_CHANGE = 25; // 价格 cell 顶部 → 涨跌 cell 顶部（cell 自带留白，字面间留 8px）
    const MAX_TEXT_W = 168;     // 单行价格的上限宽度，超了就整体降一档字体

    // 涨跌前面的手绘三角（内置字体里没有 ▲/▼，见 drawArrow 的注释）
    const ARROW_W = 7;
    const ARROW_H = 6;
    const ARROW_GAP = 3;        // 三角与百分比文本的间距
    const ARROW_TOP = 8;        // 三角相对涨跌行 cell 顶部的偏移（与 13px 数字居中对齐）

    // v3：新增 changes 数组；旧版缓存没有涨跌字段，换键名自然失效
    const CACHE_KEY = "ttcoin_cache_v3";

    // 实测连不通的接口地址（属性值跨安装保留，可能一直是条死地址）
    const BAD_URL_KEY = "ttcoin_api_bad";

    const STATE_LOADING = 0;   // 还没拿到过任何数据
    const STATE_OK = 1;        // 有数据可显示（可能是缓存）
    const STATE_ERROR = 2;     // 彻底失败，且无任何可显示的数据

    // 请求多久没回调就认定卡死（毫秒）。SDK 一般 30 秒内会回调，
    // 但断网 / DNS 卡住时可能迟迟不回调，界面会一直停在 "- Cache -"。
    const REQUEST_TIMEOUT_MS = 45000;

    var timer as Timer.Timer?;
    var clockTimer as Timer.Timer?;             // 走时用，1 秒一拍
    var lastMinute as Lang.Number = -1;         // 上次画出来的"分钟序号"，相同就不重绘
    var marketData as Lang.Array? = null;
    var state as Lang.Number = STATE_LOADING;
    var subtitle as Lang.String = "- Coin -";   // 副标题：区分实时 / 缓存 / 离线
    var pageIndex as Lang.Number = 0;           // 当前轮播页码
    var tickCount as Lang.Number = 0;           // Timer 拍数计数（轮播/抓取分频用）
    var blockCount as Lang.Number = 0;          // 最近一次 onUpdate 实际绘制的币种数

    // 失败诊断：把 SDK 给的响应码显示出来，便于区分
    //   负数 / -104 之类 → 连不上；
    //   403 / 503        → 服务端或 CDN 拒绝；
    //   200 但解析失败    → 返回体不是 JSON 数组。
    var lastCode as Lang.Number = 0;
    var requestUrl as Lang.String = "";         // 本次请求实际用的地址
    var retriedFallback as Lang.Boolean = false; // 是否已用 DEFAULT_API 重试过
    var pendingSince as Lang.Number = 0;         // 请求发出时刻（ms），0 = 没有在飞的请求

    var requestOptions as Lang.Dictionary = {
        :method => Communications.HTTP_REQUEST_METHOD_GET,
        :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
    };

    // Monkey C 的 Array 没有 contains()， indexOf() 找不到时的返回值
    // 在不同固件上有 null / -1 两种实现，这里统一用自写遍历最稳。
    function arrayHasString(arr as Lang.Array, text as Lang.String) as Lang.Boolean {
        for (var i = 0; i < arr.size(); i++) {
            var v = arr[i];
            if (v instanceof Lang.String && (v as Lang.String).equals(text)) {
                return true;
            }
        }
        return false;
    }

    // 同上，返回下标；找不到返回 -1
    function indexOfString(arr as Lang.Array, text as Lang.String) as Lang.Number {
        for (var i = 0; i < arr.size(); i++) {
            var v = arr[i];
            if (v instanceof Lang.String && (v as Lang.String).equals(text)) {
                return i;
            }
        }
        return -1;
    }

    function initialize() {
        View.initialize();

        // 先恢复上次成功抓到的价格，避免一进页面就是空白或 Loading
        loadCache();
    }

    // App 每次进入都会走 onShow：
    // 在这里接管"起定时器 + 拉数据"，比放在 initialize 更符合组件语义
    function onShow() as Void {
        startTimer();
        startClock();
        fetchPrice();
    }

    // 离开时必须停掉定时器，否则反复进出会堆积多个 Timer 实例
    function onHide() as Void {
        stopTimer();
        stopClock();
    }

    // 一条行情对应的"币种简称"：优先 base（服务端给的原始简称，如 SHIB），
    // 没有 base 的旧缓存就从 symbol 里剥掉 "10000*" 这类倍数前缀。
    // 菜单、勾选项、属性键统统用简称，不用带倍数的显示名。
    function labelOf(dict as Lang.Dictionary) as Lang.String? {

        var base = dict["base"];

        if (base instanceof Lang.String && (base as Lang.String).length() > 0) {
            return base as Lang.String;
        }

        var symbol = dict["symbol"];

        if (!(symbol instanceof Lang.String)) {
            return null;
        }

        var text = symbol as Lang.String;
        var star = text.find("*");

        if (star instanceof Lang.Number) {
            return text.substring((star as Lang.Number) + 1, text.length()) as Lang.String;
        }

        return text;
    }

    // 接口顺序：最近一次拿到的行情里币种的排列，也就是服务端 ttcoin_symbols()
    // 的顺序。默认顺序、默认勾选前几个，都以它为准 —— 客户端不写死。
    //
    // 还没拿到过任何数据（首次启动且没缓存/没网）时退回 COINS 兜底表，
    // 保证设置菜单至少能列出来。
    function apiOrder() as Lang.Array {

        var order = [] as Lang.Array;

        if (marketData instanceof Lang.Array) {

            var list = marketData as Lang.Array;

            for (var i = 0; i < list.size(); i++) {

                var item = list[i];

                if (!(item instanceof Lang.Dictionary)) {
                    continue;
                }

                var label = labelOf(item as Lang.Dictionary);

                if (label != null && !arrayHasString(order, label as Lang.String)) {
                    order.add(label);
                }
            }
        }

        if (order.size() == 0) {
            for (var j = 0; j < COINS.size(); j++) {
                order.add(COINS[j]);
            }
        }

        return order;
    }

    // 候选表给菜单用（顺序 = 接口顺序，菜单和行情列表保持一致）
    function catalog() as Lang.Array {
        return apiOrder();
    }

    // ---------------- 用户配置：选币 + 排序 ----------------

    // 读取某个币种是否显示。手机端（Garmin Connect 的应用设置）和手表菜单
    // 都会写同一个 Properties 布尔项，两边实时同步。
    //
    // "默认显示前 N 个"是**按接口顺序**算出来的，不是一个写死的名单：
    // 用户一次都没动过勾选时，属性值和 BUILTIN_ON 完全一致，这时忽略属性值，
    // 直接按接口顺序取前 DEFAULT_COUNT 个 —— 服务端换顺序 / 加币种，表上会跟着变。
    // 只要用户改过任意一项，就完全尊重属性值，不再套默认。
    function isCoinEnabled(label as Lang.String) as Lang.Boolean {

        if (selectionUntouched()) {
            var at = indexOfString(catalog(), label);

            return at >= 0 && at < DEFAULT_COUNT;
        }

        var value = null;

        try {
            value = Application.Properties.getValue(PROP_PREFIX + label);
        } catch (e) {
            return true;                 // 属性系统异常：宁可多显示也不空白
        }

        return value instanceof Lang.Boolean && (value as Lang.Boolean);
    }

    // 判断用户是否从未改过任何勾选：逐一对比"当前属性值"与"编译期初始值"。
    // 没有对应属性项的新币种，getValue 返回 null（个别固件会抛异常），
    // 两种情况都按 false 处理 —— 和 BUILTIN_ON 里"不在名单 = 关"的口径一致，
    // 所以服务端加了新币种也不会被误判成"用户改过设置"。
    function selectionUntouched() as Lang.Boolean {

        var order = catalog();

        for (var i = 0; i < order.size(); i++) {

            var label = order[i] as Lang.String;

            var actual = false;

            try {
                var raw = Application.Properties.getValue(PROP_PREFIX + label);

                actual = raw instanceof Lang.Boolean && (raw as Lang.Boolean);
            } catch (e) {
                actual = false;
            }

            if (actual != arrayHasString(BUILTIN_ON, label)) {
                return false;
            }
        }

        return true;
    }

    // 手表菜单勾选/取消一个币种
    function toggleCoin(label as Lang.String) as Void {
        try {
            Application.Properties.setValue(
                PROP_PREFIX + label,
                !isCoinEnabled(label)
            );
        } catch (e) {
            // 写失败保持原状即可
        }
    }

    // 归一化的完整顺序表：包含全部候选币种，无重复。
    // 用户排过序就用排过的；没排过就用**接口顺序**（不是编译期常量表）。
    function normalizedOrder() as Lang.Array {

        var order = catalog();

        var stored = null;

        try {
            stored = Storage.getValue(ORDER_KEY);
        } catch (e) {
            stored = null;
        }

        var list = [] as Lang.Array;

        if (stored instanceof Lang.Array) {

            var saved = stored as Lang.Array;

            for (var i = 0; i < saved.size(); i++) {

                var label = saved[i];

                if (label instanceof Lang.String && arrayHasString(order, label)
                    && !arrayHasString(list, label)) {
                    list.add(label);
                }
            }
        }

        // 顺序表里没有的（新加的币种 / 首次运行）按接口顺序补到末尾
        for (var j = 0; j < order.size(); j++) {

            var label = order[j] as Lang.String;

            if (!arrayHasString(list, label)) {
                list.add(label);
            }
        }

        return list;
    }

    function saveOrder(list as Lang.Array) as Void {
        try {
            Storage.setValue(ORDER_KEY, list);
        } catch (e) {
            // 存储不可用：排序是体验项，静默失败
        }
    }

    // 排序：把 label 在完整顺序表里上移(delta=-1)或下移(delta=1)一位。
    // Array.remove() 按对象删、没有按索引插入的 API，所以删除后用 slice 重组。
    function moveCoin(label as Lang.String, delta as Lang.Number) as Void {

        var list = normalizedOrder();
        var at = list.indexOf(label);

        if (!(at instanceof Lang.Number) || (at as Lang.Number) < 0) {
            return;                          // 不在候选表里
        }

        var from = at as Lang.Number;

        list.remove(label);

        // 删除后：上移插到 at-1，下移插到 at+1（原 at+1 的元素删除后落位在 at）
        var insertAt = delta < 0 ? from - 1 : from + 1;

        if (insertAt < 0 || insertAt >= list.size()) {
            return;                          // 已在顶/底，无可移动
        }

        var rebuilt = [] as Lang.Array;

        rebuilt.addAll(list.slice(0, insertAt));
        rebuilt.add(label);
        rebuilt.addAll(list.slice(insertAt, list.size()));

        saveOrder(rebuilt);
    }

    // 实际要显示的币种列表 = 完整顺序表 过滤掉未启用的。
    // 用户把所有币种都取消勾选时，回退到"接口顺序前 N 个"，
    // 避免白屏让用户以为坏了（与默认勾选口径一致）。
    function effectiveCoins() as Lang.Array {

        var order = normalizedOrder();
        var result = [] as Lang.Array;

        for (var i = 0; i < order.size(); i++) {

            var label = order[i] as Lang.String;

            if (isCoinEnabled(label)) {
                result.add(label);
            }
        }

        if (result.size() == 0) {
            for (var j = 0; j < order.size() && j < DEFAULT_COUNT; j++) {
                result.add(order[j] as Lang.String);
            }
        }

        return result;
    }

    // ---------------- 绘制 ----------------

    function onUpdate(dc) as Void {

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // 灯孔里的 TT 标跟数据无关，先画，保证任何状态下都在
        drawBadge(dc);

        // 时钟同理：与副标题共轴、画在它上方，Loading / No Net 时也照样走时
        dc.drawText(
            dc.getWidth() * TITLE_CX / REF_WIDTH,
            dc.getHeight() * CLOCK_Y / REF_HEIGHT,
            Graphics.FONT_TINY,
            clockText(),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // 记下这一帧画的是哪一分钟，走时定时器据此判断要不要重绘
        lastMinute = minuteKey();

        var blocks = buildBlocks();

        blockCount = blocks.size();

        // 标题位：副标题（形态 / 缓存状态）
        var head = subtitle;

        if (blockCount == 0) {

            // 有数据但全部不合法/未启用 → No Data；从未拿到过数据 → No Net；否则仍在加载
            var message = "Loading...";

            if (state == STATE_ERROR) {
                message = "No Net" + codeSuffix();   // 带失败码，便于回头看日志定位
            } else if (state == STATE_OK) {
                message = "No Data";
            }

            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_SMALL,
                message,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        var w  = dc.getWidth();        var h  = dc.getHeight();
        var cx = w / 2;

        // 按页切片：币种超过一屏时只画当前页，页码附在副标题后
        var pages = (blockCount + PAGE_ROWS - 1) / PAGE_ROWS;

        if (pageIndex >= pages) {
            pageIndex = 0;                   // 币种减少后页码越界，回到首页
        }

        var start = pageIndex * PAGE_ROWS;
        var end = start + PAGE_ROWS;

        if (end > blockCount) {
            end = blockCount;
        }

        var shown = end - start;

        // 价格字体：整页最宽的一行放得下才用，放不下就整体降一档，
        // 保证 "BTC 756078.49" 这种长价格不会溢出屏幕两侧。
        var priceFont = choosePriceFont(dc, blocks, start, end);

        // 标题区：副标题画在"左斜边 → 灯孔外环"这段空档的中间，
        // 页码单独一行放在下面（并进标题会顶到灯孔边缘，翻页时长度还会变）。
        var titleX = w * TITLE_CX / REF_WIDTH;
        var titleY = h * TITLE_Y / REF_HEIGHT;

        dc.drawText(titleX, titleY,
            Graphics.FONT_TINY,
            head,
            Graphics.TEXT_JUSTIFY_CENTER);

        if (pages > 1) {
            dc.drawText(titleX, titleY + h * PAGE_DY / REF_HEIGHT,
                Graphics.FONT_TINY,
                (pageIndex + 1).toString() + "/" + pages.toString(),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // 一屏没满时整体下移，价格块保持视觉居中
        var pitch = h * BLOCK_PITCH / REF_HEIGHT;
        var gap   = h * PRICE_TO_CHANGE / REF_HEIGHT;
        var top   = h * CONTENT_TOP / REF_HEIGHT + (PAGE_ROWS - shown) * pitch / 2;

        for (var i = start; i < end; i++) {

            var row = top + (i - start) * pitch;

            drawRow(dc, cx, row, priceFont, blocks[i] as Lang.Dictionary, gap);
        }
    }

    // 在右上角灯孔里画 TT 标。
    // 那块圆是手电筒的物理窗口，横竖都只有 50 多像素，只能放两个字母；
    // 竖直居中靠 JUSTIFY_VCENTER，不写死像素。
    function drawBadge(dc as Graphics.Dc) as Void {

        dc.drawText(
            dc.getWidth() * BADGE_CX / REF_WIDTH,
            dc.getHeight() * BADGE_CY / REF_HEIGHT,
            Graphics.FONT_SMALL,
            "TT",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    // 画一个币种：价格一行，涨跌组（手绘三角 + 百分比）居中一行。
    function drawRow(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cellY as Lang.Number,
        priceFont as Graphics.FontType,
        block as Lang.Dictionary,
        gap as Lang.Number
    ) as Void {

        dc.drawText(cx, cellY, priceFont, priceLine(block), Graphics.TEXT_JUSTIFY_CENTER);

        var percent = changePercent(block["change"]);

        if (percent == null) {
            return;                          // 平盘/无数据：不画涨跌行
        }

        var sx = dc.getWidth() / REF_WIDTH;
        var sy = dc.getHeight() / REF_HEIGHT;

        var arrowW = ARROW_W * sx;
        var arrowH = ARROW_H * sy;
        var arrowGap = ARROW_GAP * sx;

        if (arrowW < 3 || arrowH < 3) {
            arrowW = 3;                      // 极小屏兜底，保证三角还能看见
            arrowH = 3;
        }

        var textW = dc.getTextWidthInPixels(percent, Graphics.FONT_TINY);
        var left  = cx - (arrowW + arrowGap + textW) / 2;
        var chgY  = cellY + gap;

        drawArrow(dc, left, chgY + ARROW_TOP * sy, arrowW, arrowH, isUp(block["change"]));

        dc.drawText(left + arrowW + arrowGap, chgY,
            Graphics.FONT_TINY, percent, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // 价格行的完整文本（币种 + 两个空格 + 价格字符串）
    function priceLine(block as Lang.Dictionary) as Lang.String {
        return (block["symbol"] as Lang.String) + "  " + (block["price"] as Lang.String);
    }

    // 选一档能放下的价格字体：MEDIUM → SMALL → TINY。
    // 整页共用同一档，避免同一屏里字号忽大忽小；实在都放不下才落到 TINY。
    // 只量价格这一行：涨跌是独立一行、居中画的小字，不会把宽度撑爆。
    function choosePriceFont(
        dc as Graphics.Dc,
        blocks as Lang.Array,
        start as Lang.Number,
        end as Lang.Number
    ) as Graphics.FontType {

        var fonts = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY];
        var limit = dc.getWidth() * MAX_TEXT_W / REF_WIDTH;

        for (var f = 0; f < fonts.size(); f++) {

            var font = fonts[f] as Graphics.FontType;
            var fits = true;

            for (var i = start; i < end; i++) {

                var text = priceLine(blocks[i] as Lang.Dictionary);

                if (dc.getTextWidthInPixels(text, font) > limit) {
                    fits = false;
                    break;
                }
            }

            if (fits) {
                return font;
            }
        }

        return Graphics.FONT_TINY;
    }

    // 手动翻页（Up/Down 键，由 TTCoinDelegate 调用）
    function page(step as Lang.Number) as Void {

        if (blockCount <= PAGE_ROWS) {
            return;                          // 一屏装得下，无需翻页
        }

        var pages = (blockCount + PAGE_ROWS - 1) / PAGE_ROWS;

        pageIndex = (pageIndex + step + pages) % pages;

        WatchUi.requestUpdate();
    }

    // 待绘制的币种块列表：按用户配置的顺序，只含已启用且当前有行情的币种。
    // 每个块是 {symbol, price, change}，结构与市场数据一致。
    function buildBlocks() as Lang.Array {

        var blocks = [] as Lang.Array;

        if (!(marketData instanceof Lang.Array)) {
            return blocks;
        }

        var coins = effectiveCoins();

        for (var i = 0; i < coins.size(); i++) {

            var quote = findQuote(coins[i] as Lang.String);

            if (quote != null) {
                blocks.add(quote);
            }
        }

        return blocks;
    }

    // 币种名匹配。
    //
    // 服务端对小额价格会做放大（0.00001826 → 0.01826），并把倍数写进显示名：
    // symbol = "1000*SHIB"，同时给出 base = "SHIB"。匹配一律看 base；
    // 旧缓存里没有 base 字段，就退化成"去掉 NNN* 前缀再比"，
    // 这样缓存态、以及只更新了服务端没更新表端的组合都不会丢数据。
    function matchesLabel(dict as Lang.Dictionary, label as Lang.String) as Lang.Boolean {

        var base = dict["base"];

        if (base instanceof Lang.String) {
            return (base as Lang.String).equals(label);
        }

        var symbol = dict["symbol"];

        if (!(symbol instanceof Lang.String)) {
            return false;
        }

        var text = symbol as Lang.String;

        if (text.equals(label)) {
            return true;
        }

        var star = text.find("*");

        if (!(star instanceof Lang.Number)) {
            return false;
        }

        return (text.substring((star as Lang.Number) + 1, text.length()) as Lang.String).equals(label);
    }

    // 从市场数据里找某币种的报价；字段全部过 instanceof 校验，
    // 结构不对的条目直接跳过，避免硬编码索引越界崩溃。
    function findQuote(label as Lang.String) as Lang.Dictionary? {

        var list = marketData as Lang.Array;

        for (var i = 0; i < list.size(); i++) {

            var item = list[i];

            if (!(item instanceof Lang.Dictionary)) {
                continue;
            }

            var dict = item as Lang.Dictionary;

            var symbol = dict["symbol"];

            if (!(symbol instanceof Lang.String)) {
                continue;
            }

            if (!matchesLabel(dict, label)) {
                continue;
            }

            var text = priceText(dict["price"]);

            if (text == null) {
                continue;                    // 价格既不是字符串也不是数字
            }

            return {
                "symbol" => symbol as Lang.String,
                "price"  => text,
                "change" => dict["change"]
            };
        }

        return null;
    }

    // 涨跌文本：服务端给的是带符号字符串（"2.3" / "-1.23" / "0"）。
    // 返回去掉负号的百分比文本（"2.3%" / "1.23%"），零或缺失返回 null（平盘不画）。
    // 全程字符串处理，不经过 Float。
    function changePercent(change as Lang.Object?) as Lang.String? {

        if (!(change instanceof Lang.String)) {
            return null;
        }

        var text = change as Lang.String;

        if (text.length() == 0 || text.equals("0")) {
            return null;
        }

        var at = text.find("-");

        if (at instanceof Lang.Number && (at as Lang.Number) == 0) {
            return (text.substring(1, text.length()) as Lang.String) + "%";
        }

        return text + "%";
    }

    // 涨跌方向：负号开头算跌，其余算涨
    function isUp(change as Lang.Object?) as Lang.Boolean {

        if (!(change instanceof Lang.String)) {
            return true;
        }

        var at = (change as Lang.String).find("-");

        return !(at instanceof Lang.Number && (at as Lang.Number) == 0);
    }

    // 画一个实心三角表示涨/跌。
    //
    // ⚠️ 不能直接用 "▲"/"▼"：Garmin 内置字体里并没有这两个字符，
    //    运行时会被替换成"缺字占位符"（一个空心菱形），屏幕上就只剩个 ◇，
    //    看不出涨还是跌 —— 第一版截图里那个菱形就是这么来的。
    //    自己用 fillPolygon 画三角形，任何设备任何字体都不会缺。
    function drawArrow(
        dc as Graphics.Dc,
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        up as Lang.Boolean
    ) as Void {

        if (up) {
            dc.fillPolygon([
                [x, y + h],
                [x + w, y + h],
                [x + w / 2, y]
            ]);
        } else {
            dc.fillPolygon([
                [x, y],
                [x + w, y],
                [x + w / 2, y + h]
            ]);
        }
    }

    // 行情文本直接取服务端下发的字符串：
    // 小数位数由服务端按上游 API 的原始位数决定（超过 4 位才四舍五入），
    // 客户端只做拼接，不做任何数值格式化。
    //
    // ⚠️ 为什么不在客户端格式化：Monkey C 的 Float 是 32 位，75678.78 存进去
    //    实际是 75678.78125，format("%0.4f") 会画出 75678.7812 —— 后两位是
    //    精度噪声，跟真实价格无关，去掉尾部 0 也救不回来。Double 是 64 位，
    //    下面这条分支只为兼容"服务端还是旧版、返回数字"的情况。
    function priceText(price as Lang.Object?) as Lang.String? {

        if (price instanceof Lang.String) {

            var text = price as Lang.String;

            return text.length() > 0 ? text : null;
        }

        if (price instanceof Lang.Double) {
            return trimZeros((price as Lang.Double).format("%0.4f"));
        }

        if (price instanceof Lang.Long) {
            return (price as Lang.Long).format("%d");
        }

        if (price instanceof Lang.Number) {
            return (price as Lang.Number).format("%d");
        }

        return null;
    }

    // 去掉小数末尾多余的 0；整数（没有小数点）原样返回，避免 "67000" → "67"
    function trimZeros(text as Lang.String) as Lang.String {

        var dot = text.find(".");

        if (!(dot instanceof Lang.Number)) {
            return text;
        }

        var at  = dot as Lang.Number;
        var end = text.length();

        while (end > at + 1) {

            var ch = text.substring(end - 1, end) as Lang.String;

            if (!ch.equals("0")) {
                break;
            }

            end--;
        }

        if (end == at + 1) {
            return text.substring(0, at) as Lang.String;   // 只剩小数点，一起丢掉
        }

        return text.substring(0, end) as Lang.String;
    }

    // ---------------- 定时器 ----------------

    function startTimer() as Void {
        if (timer != null) {
            return;                          // 已在跑，避免重复创建
        }
        timer = new Timer.Timer();
        timer.start(method(:onTimer), PAGE_MS, true);
    }

    function stopTimer() as Void {
        if (timer != null) {
            timer.stop();
            timer = null;
        }
    }

    // 一拍 = PAGE_MS（8s）：多数拍只翻页，
    // 每 FETCH_TICKS 拍才真正发一次行情请求，维持约 1 分钟的刷新节奏。
    function onTimer() as Void {

        tickCount++;

        // 回调迟迟不来（断网 / DNS 卡住）：别让界面一直停在 "- Cache -"，
        // 用 -1 表示"本机等超时"，和 SDK 真实的响应码区分开。
        if (pendingSince > 0 && Time.now().value() - pendingSince > REQUEST_TIMEOUT_MS) {
            pendingSince = 0;
            lastCode = -1;
            handleFailure();
        }

        if (tickCount % FETCH_TICKS == 0) {
            fetchPrice();
        }

        if (blockCount > PAGE_ROWS) {

            var pages = (blockCount + PAGE_ROWS - 1) / PAGE_ROWS;

            pageIndex = (pageIndex + 1) % pages;

            WatchUi.requestUpdate();
        }
    }

    // ---------------- 走时 ----------------

    // 1 秒一拍，但**只有分钟变了才重绘**。界面只显示 HH:MM，秒数不画，
    // 每分钟一次 requestUpdate 对电量几乎没有影响；而如果靠行情那个 8 秒
    // 定时器顺带刷新，分钟跳变最多要晚 8 秒才看得见。
    function startClock() as Void {
        if (clockTimer != null) {
            return;
        }
        clockTimer = new Timer.Timer();
        clockTimer.start(method(:onClockTimer), 1000, true);
    }

    function stopClock() as Void {
        if (clockTimer != null) {
            clockTimer.stop();
            clockTimer = null;
        }
    }

    function onClockTimer() as Void {
        // 换分钟了才请求重绘；onUpdate 画完会把 lastMinute 更新成本帧的分钟
        if (minuteKey() != lastMinute) {
            WatchUi.requestUpdate();
        }
    }

    // "距零点多少分钟"，只用来比较是否换分钟，不参与显示
    function minuteKey() as Lang.Number {
        var clock = System.getClockTime();
        return clock.hour * 60 + clock.min;
    }

    // 固定 24 小时制、两位补零：宽度恒定，不会因为 "9:05" / "10:05" 抖动
    function clockText() as Lang.String {

        var clock = System.getClockTime();

        var hh = clock.hour;
        var mm = clock.min;

        var hs = hh < 10 ? "0" + hh.toString() : hh.toString();
        var ms = mm < 10 ? "0" + mm.toString() : mm.toString();

        return hs + ":" + ms;
    }

    // ---------------- 网络 ----------------

    // 手输地址是否可用：必须是 https:// 开头的完整 URL。
    // makeWebRequest 在多数设备上只接受 https，http 会在运行时直接失败，
    // 所以宁可提前挡掉，也不要让用户以为"保存成功但一直 No Net"。
    function isValidApi(text as Lang.String) as Lang.Boolean {

        if (text.length() < 12) {
            return false;
        }

        var at = text.find("https://");

        return at instanceof Lang.Number && (at as Lang.Number) == 0;
    }

    // 实际使用的接口地址，优先级：
    //   1) 手机端设置 / 编译期的属性 apiUrl（但被标记为失效的地址会跳过）
    //   2) 编译期 DEFAULT_API
    // 每次抓取前现读现用。地址不再支持手表菜单修改（2026-11 移除，
    // 原手输入口见 docs/CODE_REVIEW.md 第十六节）。
    function apiEndpoint() as Lang.String {

        var url = null;

        try {
            url = Application.Properties.getValue("apiUrl");
        } catch (e) {
            url = null;                       // 资源里没有这个属性时别抛出去
        }

        if (!(url instanceof Lang.String) || !isValidApi(url as Lang.String)) {
            return DEFAULT_API;
        }

        // 属性值是**跨安装保留**的：早期版本在手表菜单里存过的地址、
        // 或首次安装时写进去的旧默认值，都会一直盖住 properties.xml 的新值。
        // 上一次实测这条地址连不通就记下来，之后直接用 DEFAULT_API，
        // 免得每轮刷新都白失败一次。属性值一旦被改掉（变成另一个 URL），
        // 标记自动失配，新值会被重新尝试。
        var bad = null;

        try {
            bad = Storage.getValue(BAD_URL_KEY);
        } catch (e) {
            bad = null;
        }

        if (bad instanceof Lang.String && (bad as Lang.String).equals(url as Lang.String)) {
            return DEFAULT_API;
        }

        return url as Lang.String;
    }

    // 记住一条实测连不通的地址（只记非默认地址）
    function markBadUrl(url as Lang.String) as Void {

        if (url.equals(DEFAULT_API)) {
            return;
        }

        try {
            Storage.setValue(BAD_URL_KEY, url);
        } catch (e) {
            // 存储不可用时忽略：大不了下一轮再失败一次
        }
    }

    function fetchPrice() as Void {

        // 上一轮还没回来就别叠加请求：慢线路下越堆越慢
        if (pendingSince > 0 && Time.now().value() - pendingSince < REQUEST_TIMEOUT_MS) {
            return;
        }

        // 每次刷新重置回退标记：先按配置地址请求，
        // 失败再试一次编译期默认地址（见 failWith）。
        retriedFallback = false;

        requestPrice(apiEndpoint());
    }

    function requestPrice(url as Lang.String) as Void {

        requestUrl = url;
        pendingSince = Time.now().value();

        // 带上设备唯一标识（可选参数）：服务端用它区分设备做统计 / 限流。
        // 取不到就不带这个参数，服务端把它当可选值处理。
        var params = {};

        var uid = deviceUid();

        if (uid != null) {
            params.put("uid", uid);
        }

        // 应用形态标记：服务端日志里区分同一块表上的 Widget 版与 APP 版
        params.put("type", "app");

        Communications.makeWebRequest(
            url,
            params,
            requestOptions,
            method(:onReceive)
        );
    }

    // 设备唯一标识：System.getDeviceSettings().uniqueIdentifier（API 2.4.1+）。
    //   · 同一设备 + 本应用取值恒定，卸载重装不变；
    //   · 不同应用之间取值不同，不会和其他应用的数据关联；
    //   · 官方注明"用于追踪用户须符合隐私法规"，只作为匿名的设备区分符使用。
    // 出错 / 为空时返回 null，请求就不带 uid 参数。
    function deviceUid() as Lang.String? {

        var id = null;

        try {
            id = System.getDeviceSettings().uniqueIdentifier;
        } catch (e) {
            id = null;
        }

        if (!(id instanceof Lang.String)) {
            return null;
        }

        return (id as Lang.String).length() > 0 ? id : null;
    }

    // ⚠️ SDK 对 makeWebRequest 回调的类型声明是：
    //    data as Null or Dictionary or String or PersistedContent.Iterator
    //    里面并没有 Array。但 responseType=JSON 且服务端返回 JSON 数组时，
    //    运行时实际传进来的是 Array —— 这就是 signature 与实际数据不符的根源。
    //    直接把参数声明成 Lang.Object 会让 makeWebRequest 的实参校验失败
    //    （-l 1 起直接编译报错），所以签名只能留在 SDK 允许的类型内，
    //    进入函数后立刻宽化为 Object，再用 instanceof 判断真实类型。
    function onReceive(
        responseCode as Lang.Number,
        data as Lang.Dictionary?
    ) as Void {

        pendingSince = 0;                    // 回调到了，不管成败都算这一轮结束

        // 先排除 null：错误响应时 SDK 会传 null，避免下面 as Object 时踩空
        if (responseCode != 200 || data == null) {
            failWith(responseCode);
            return;
        }

        // 宽化到 Object，后续判断不再受 Dictionary 这个"名义类型"约束
        var payload = data as Lang.Object;

        if (!(payload instanceof Lang.Array)) {
            failWith(responseCode);          // 服务端回了错误体（Dictionary），按失败处理
            return;
        }

        var list = payload as Lang.Array;

        if (list.size() == 0) {
            failWith(responseCode);
            return;
        }

        marketData = list;
        state = STATE_OK;
        subtitle = "- Coin -";               // 实时数据，恢复正常副标题

        saveCache(list);

        WatchUi.requestUpdate();
    }

    // 失败先尝试回退到编译期默认地址，再放弃。
    //
    // 为什么需要这一层：属性 apiUrl 可能是**旧版本存下来的值**（早期的手表菜单
    // 里改过地址会写进 Properties，跨安装保留）。那种情况下改 properties.xml
    // 重新编译也不生效，表上会一直请求一条已经死掉的地址。用 DEFAULT_API
    // 补一次，既救回这种"历史残留"，也能在单个节点抽风时自愈。
    function failWith(code as Lang.Number) as Void {

        lastCode = code;

        if (!retriedFallback && !requestUrl.equals(DEFAULT_API)) {
            retriedFallback = true;
            requestPrice(DEFAULT_API);
            return;
        }

        // 两条地址都失败：如果用的是属性里的地址，就把它标记掉，
        // 下一轮直接走 DEFAULT_API（属性值不变时不再白试）
        if (!requestUrl.equals(DEFAULT_API)) {
            markBadUrl(requestUrl);
        }

        handleFailure();
    }

    // 请求失败的统一出口：有旧数据就降级展示并标注离线，没有才显示 No Net
    function handleFailure() as Void {

        var suffix = codeSuffix();

        if (marketData == null) {
            state = STATE_ERROR;
        } else {
            subtitle = "- Offline" + suffix + " -";
        }

        WatchUi.requestUpdate();
    }

    // 失败码后缀：0 表示 SDK 没给码，就不显示，保持原来的 "- Offline -"
    function codeSuffix() as Lang.String {

        return lastCode == 0 ? "" : " " + lastCode.toString();
    }

    // ---------------- 本地缓存 ----------------
    // 存储结构：{ "time" => 秒级时间戳,
    //             "symbols" => [String...], "prices" => [String...],
    //             "changes" => [String...] }   三个平行数组
    // 拆成平行数组而不是嵌套字典，是为了避免不同设备对嵌套结构的存储差异。
    // 价格/涨跌存的是**已格式化的字符串**，不是数值：一是位数信息不会在存取
    // 中丢，二是 Storage 对 Float/Double 的还原精度没有保证。

    function saveCache(list as Lang.Array) as Void {

        var names   = [] as Lang.Array;
        var values  = [] as Lang.Array;
        var changes = [] as Lang.Array;

        for (var i = 0; i < list.size(); i++) {

            var item = list[i];

            if (!(item instanceof Lang.Dictionary)) {
                continue;
            }

            var dict = item as Lang.Dictionary;
            var name = dict["symbol"];

            if (!(name instanceof Lang.String)) {
                continue;
            }

            var text = priceText(dict["price"]);

            if (text == null) {
                continue;
            }

            var change = dict["change"];

            names.add(name);
            values.add(text);
            changes.add(change instanceof Lang.String ? change : "");
        }

        if (names.size() == 0) {
            return;
        }

        try {
            Application.Storage.setValue(CACHE_KEY, {
                "time"    => Time.now().value(),
                "symbols" => names,
                "prices"  => values,
                "changes" => changes
            });
        } catch (e) {
            // 存储不可用或配额不足时静默失败：缓存只是锦上添花，不该影响主流程
        }
    }

    function loadCache() as Void {

        var raw = null;

        try {
            raw = Storage.getValue(CACHE_KEY);
        } catch (e) {
            return;                          // 存储不可用：当作没有缓存即可
        }

        if (!(raw instanceof Lang.Dictionary)) {
            return;                          // 首次安装，没有缓存
        }

        var cache = raw as Lang.Dictionary;

        var symbols = cache["symbols"];
        var prices  = cache["prices"];
        var changes = cache["changes"];

        if (!(symbols instanceof Lang.Array) || !(prices instanceof Lang.Array)) {
            return;
        }

        var names  = symbols as Lang.Array;
        var values = prices as Lang.Array;
        var chgs   = changes instanceof Lang.Array ? changes as Lang.Array : null;

        var count = names.size();
        if (values.size() < count) {
            count = values.size();           // 数组长度不一致时取短的
        }

        var items = [] as Lang.Array;

        for (var i = 0; i < count; i++) {

            var name = names[i];
            var price = values[i];

            if (name instanceof Lang.String && price instanceof Lang.String) {

                var change = "";

                if (chgs != null && i < chgs.size() && chgs[i] instanceof Lang.String) {
                    change = chgs[i] as Lang.String;
                }

                items.add({
                    "symbol" => name,
                    "price"  => price,
                    "change" => change
                });
            }
        }

        if (items.size() == 0) {
            return;
        }

        marketData = items;
        state = STATE_OK;
        subtitle = "- Cache -";              // 明确告诉用户这是旧数据
    }
}
