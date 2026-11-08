# 代码审查与发布前 Checklist

> 📁 **路径说明**：本文写作时服务端代码还在本仓库 `api/` 目录下；现已整体迁至同级独立目录 **`https://github.com/hh1949tt/TTCoin_API`**。文中出现的 `api/xxx.php` 一律对应现在的 `https://github.com/hh1949tt/TTCoin_API`，内容不再重复修订。


审查对象：`TTCoin` 全部源码（Monkey C + PHP）。
结论：功能可用。**公开前只剩 #1（私人接口域名）一项**。原始共 15 项，已修复 14 项： #2 #3 #4 #5 #6 #7 #8 #9 #10 #11 #12 #13 #14 #15。

## 一、总览

| # | 位置 | 问题 | 严重度 |
| --- | --- | --- | --- |
| 1 | `TTCoinView.mc:10` | 硬编码接口域名（发布版已改为占位地址） | 🔴 高 |
| 2 | `TTCoinView.mc:193-227` | `onReceive` 类型标注与实际 Array 数据不符 | ✅ 已修复 |
| 3 | 仓库根目录 | 缺少 `README` / `.gitignore` / `LICENSE` | ✅ 已修复 |
| 4 | `TTCoinView.mc:107-141` | 硬编码数组索引，返回条数不足即崩溃 | ✅ 已修复 |
| 5 | `TTCoinView.mc:13-26` + `onUpdate` | 像素坐标写死，仅适配 176×176 | ✅ 已修复 |
| 6 | `TTCoinView.mc:52-105` | 失败时永久停留 `Loading...`，无错误状态 | ✅ 已修复 |
| 7 | `TTCoinView.mc:42-50` | Timer 未在 `onHide()` 释放 | ✅ 已修复 |
| 8 | `TTCoinView.mc:244-326` | 无本地缓存，离线/断网时全黑屏 | ✅ 已修复 |
| 9 | `lib.php` `TTCOIN_CACHE_TTL` | 缓存 TTL 1 秒，缓存形同虚设 | ✅ 已修复 |
| 10 | `api/lib.php` | `coin.php` / `update_price.php` 约 90% 逻辑重复 | ✅ 已修复 |
| 11 | `lib.php` `ttcoin_cache_file()` | 缓存文件落在 Web 根目录，可被直接访问 | ✅ 已修复 |
| 12 | `TTCoinView.mc:198` | `data == null` 在非空类型上永远为假 | ✅ 随 #2 修复 |
| 13 | `TTCoinView.mc:23-26` | 变量无类型声明 | ✅ 已修复 |
| 14 | `resources/layouts/` | 空模板残留 | ✅ 已修复 |
| 15 | `lib.php` `ttcoin_fetch()` | 未校验 `price` 是否为数字 | ✅ 已修复 |

---

## 二、详细说明

### 1. 🔴 私人接口地址硬编码

```monkey-c
// TTCoinView.mc:10
const PRICE_API = "https://api.example.com/coin.php";
```

公开仓库后，任何人下载代码都会打到你的服务器上：带宽、流量、被滥用的风险都由你承担，而对方一旦断网或你的域名过期，会认为"这个插件是坏的"。

**建议**

- 地址挪进**属性系统**（`resources/properties.xml` 的 `apiUrl`，默认值是占位地址），并暴露到手机端 Garmin Connect 的应用设置里——用户不改代码、不重新编译，填自己的地址即可。客户端 `apiEndpoint()` 现读现用：不是 `https://` 开头或为空时回退编译期默认值 `DEFAULT_API`，避免把非法配置原样发出去。
- README 中显著标注"必须自建后端"（已完成）。
- 若确实想提供公共服务，单独在 Issue 中说明可用性无承诺，不要写死在代码里。

### 2. ✅ 类型标注与实际数据不符（已修复）

```monkey-c
// 修复前：签名写 Dictionary
function onReceive(responseCode as Lang.Number, data as Lang.Dictionary) as Void {
    ...
    marketData = data; // 注释：实际运行时是 Array
}
```

`coin.php` 返回的是 JSON 数组，Monkey C 会解码成 `Lang.Array`。作者注释已经说明了这一点，说明当时遇到过问题，靠运行时类型检查不严格才跑通。

**调查结论（SDK 9.2.0 实测）**：`makeWebRequest` 的回调类型在 SDK 里被声明为

```
Method(responseCode as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void
```

**这个联合类型里没有 Array** —— 这才是"签名与实际数据不符"的真正根源，属于 SDK 声明本身的缺口，不是写法问题。

因此**不能**把参数直接改成 `Lang.Object`，实测会在 `-l 1`（渐进模式，VS Code 默认）下编译失败：

```
ERROR: TTCoinView.mc:79: Invalid 'Method(responseCode as Number, data as Null or Object) as Void'
       passed as parameter 4 of type 'PolyType<(Method(... data as Null or Dictionary or String or ...)'
```

**最终采用的写法**——签名留在 SDK 允许的类型内，进函数后立即宽化为 `Object` 再用 `instanceof` 收敛：

```monkey-c
function onReceive(
    responseCode as Lang.Number,
    data as Lang.Dictionary?      // ① 满足 SDK 的回调签名约束
) as Void {

    if (responseCode != 200 || data == null) {   // ② 先排除 null
        hasData = false;
        WatchUi.requestUpdate();
        return;
    }

    var payload = data as Lang.Object;           // ③ 宽化，摆脱名义类型

    if (payload instanceof Lang.Array) {         // ④ 按真实类型判断
        marketData = payload as Lang.Array;
        hasData = true;
    } else {
        hasData = false;                         // 非数组结构（错误体）按无数据处理
    }

    WatchUi.requestUpdate();
}
```

四点改进：

| 改动 | 作用 |
| --- | --- |
| `Lang.Dictionary` → `Lang.Dictionary?` | 如实反映"错误响应时 SDK 会传 null" |
| 先判 null 再 `as Object` | 避免 `null as Object` 在运行时踩空（Monkey C 不允许局部变量显式标注类型，只能靠顺序保证） |
| `instanceof Lang.Array` | 服务端若返回 `{"error": ...}` 且 HTTP 200，以前会直接赋给 `marketData` 然后在 `marketData[0]` 崩溃，现在能拦住 |
| 去掉误导性注释 | 原注释"data 必须写成 Dictionary"是结论而非原因，会带偏后来的人 |

**编译验证**（SDK 9.2.0，临时密钥）：`-l 0/1/2` 均 `BUILD SUCCESSFUL`，0 error，警告数不高于改动前。

> 遗留风险：若某天 Garmin 真的在回调边界对 `Dictionary` 做强制校验，客户端无法自救——因为合法的联合类型里根本没有 Array。只能等 SDK 侧把 Array 补进去。

### 3. ✅ 仓库缺少基础设施文件（已修复）

三件套已齐：

- `README.md` —— 项目说明、部署、接口约定、排错；
- `.gitignore` —— 重点排除 `bin/`（其中的 `TTCoin.prg.debug.xml` 会写入**本机绝对路径与源码行号映射**，属于不该公开的本地信息）、`*.der`、缓存文件；
- `LICENSE` —— **MIT**，版权行署名 `TTCoin contributors`（通用署名，后续维护者可继续分发，不必追着原作者改授权）。

### 4. ✅ 硬编码索引（已修复）

```monkey-c
// 修复前
var coin1 = marketData[0]["symbol"] + ": " + marketData[0]["price"].format("%0.2f");
var coin2 = marketData[1]["symbol"] + ...
var coin3 = marketData[2]["symbol"] + ...
```

服务端虽然做了完整性校验（`coin.php:131`），但客户端不该信任远端一定返回 3 条。只要返回 2 条就是数组越界，Widget 直接异常退出；返回 4 条则第 4 条永远看不到。

**修复方式**：把"按下标取三条"改成"遍历 + 逐条校验 + 最多 3 行"，渲染逻辑与数据结构解耦。

```monkey-c
const MAX_ROWS = 3;      // 一屏最多显示几行行情
const REF_ROW = 30;      // 参考行距（按屏幕高度等比缩放）

function buildRows() as Lang.Array {
    var rows = [] as Lang.Array;

    if (!(marketData instanceof Lang.Array)) {
        return rows;
    }

    var list = marketData as Lang.Array;

    for (var i = 0; i < list.size() && rows.size() < MAX_ROWS; i++) {

        var item = list[i];
        if (!(item instanceof Lang.Dictionary)) { continue; }   // 不是 {symbol, price} 结构

        var dict   = item as Lang.Dictionary;
        var symbol = dict["symbol"];
        var price  = dict["price"];

        if (!(symbol instanceof Lang.String)) {
            continue;                                            // 字段缺失或类型不符
        }

        var text = priceText(price);                             // 服务端已定好小数位
        if (text == null) {
            continue;                                            // 价格既不是字符串也不是数字
        }

        rows.add((symbol as Lang.String) + ": " + text);
    }

    return rows;
}
```

配套的三处改动：

| 改动 | 作用 |
| --- | --- |
| `onUpdate()` 改为遍历 `rows` 逐行 `drawText` | 行数 1~3 都能正确渲染，不再有 `[0]/[1]/[2]` |
| 价格改为服务端下发**字符串**，客户端只拼接 | 原来靠"第 3 个币种用 4 位"这种位置约定，加一个币种就全乱；后来发现在客户端格式化本身有精度问题（见第六节） |
| `rows.size() == 0` 时显示 `No Data` | 数据到了但结构不对，不再画一片空白 |

> 这段代码后来改过两次：先是 `price instanceof Lang.Number` 判类型，编译期零警告但真机一直 `No Data`（第五节）；再之后客户端彻底不再做数值格式化，改为直接显示服务端下发的字符串（第六节）。上面的写法是最终形态。

**两个附带收益**：

- 行数不足 3 时整体下移半个行高，价格块保持垂直居中；
- 编译器警告从 14 条降到 5 条——因为 `drawText` 的实参不再是 `Any`，`Cannot determine if container access is using container type` 一类推断警告随之消失。

> 注意：这只解决了"结构异常不崩溃"。网络失败仍会停在 `Loading...`（见第 6 条），因为 `hasData` 与"是否超时"没有区分。

### 5. ✅ 坐标写死（已修复）

```monkey-c
// 修复前
dc.drawText(dc.getWidth()/2 + 56, dc.getHeight()/2 - 68, ...)  // "TT"
dc.drawText(dc.getWidth()/2 - 16, dc.getHeight()/2 - 50, ...)  // "- Coin -"
var top = dc.getHeight()/2 - 20 + (MAX_ROWS - rows.size()) * ROW_HEIGHT / 2;
```

`+56 / -16 / -68 / -50 / 30` 全部是按 176×176 试出来的，换机型（如 240×240 的 fenix 系列）会明显偏位。

**修复**：以 176×176 为设计基准（`REF_WIDTH` / `REF_HEIGHT`），所有偏移改成常量语义值，绘制时按实际屏幕宽高**等比例缩放**：

```monkey-c
const REF_WIDTH = 176;
const REF_HEIGHT = 176;

const TT_DX = 56;      // "TT" 角标相对水平中心的偏移
const TT_UP = 68;      // "TT" 角标相对垂直中心的偏移
const SUB_DX = 16;     // 副标题相对水平中心的偏移
const SUB_UP = 50;     // 副标题相对垂直中心的偏移
const BLOCK_UP = 20;   // 价格块首行相对垂直中心的偏移
const REF_ROW = 30;    // 参考行距

// onUpdate 里
var rowH = h * REF_ROW / REF_HEIGHT;
dc.drawText(cx + w * TT_DX / REF_WIDTH, cy - h * TT_UP / REF_HEIGHT, ...);
```

要点：

- `w * n / REF_WIDTH` 从左到右结合（先乘后除），整数运算不丢精度；176×176 上所有换算结果与旧版**逐像素一致**，真机看不出任何变化；
- 240×240 换算后角标 (196, 28)、行距 40、首行 y=93，比例关系与 176 完全相同；
- 行距跟随屏幕高度缩放后，`MAX_ROWS` 行文本在 taller/wider 的屏上依然保持原有密度。

**遗留**：这只是矩形屏的比例适配。圆屏（弧边会裁掉左上角）需要 `resources-round/` 资源目录留白，或改用 layout.xml + Drawable 的标准做法——见方案对比（本节上方）。

> **后续（第九节）**：上面的 `TT_DX / SUB_DX / REF_ROW` 这套"相对中心偏移"的写法后来被推翻了。Instinct 2X 的屏幕带右上角挖孔，`cy - n` 这种对称布局必然把第一行塞进挖孔里；现在改成以"挖孔下沿"为基准的绝对纵向排布，比例缩放只保留在 176 基准的横纵换算上。`TT` 角标已随 Watch App 改版移除。

### 6. ✅ 无错误状态（已修复）

```monkey-c
// 修复前
if (!hasData || marketData == null) {
    dc.drawText(..., "Loading...", ...);
    return;
}
```

请求失败后 `hasData = false`，界面回到 `Loading...` 并**永远停在那里**，用户无法区分"正在加载"和"已经失败"。

**修复方式**：把布尔量 `hasData` 换成显式状态常量 + 一句副标题文案，绘制时按"有无可显示数据 × 当前状态"两个维度分支：

```monkey-c
const STATE_LOADING = 0;
const STATE_OK = 1;
const STATE_ERROR = 2;

var state as Lang.Number = STATE_LOADING;
var subtitle as Lang.String = "- Coin -";
```

| 显示 | 触发条件 |
| --- | --- |
| `Loading...` | 无数据 + `STATE_LOADING` |
| `No Net` | 无数据 + `STATE_ERROR`（请求失败且无缓存） |
| `No Data` | 无数据 + `STATE_OK`（响应到了但结构不对） |
| `- Coin -` | 有数据且是实时数据 |
| `- Cache -` | 有数据但来自本地缓存 |
| `- Offline -` | 有数据但本次请求失败 |

比"加三个状态枚举"更省事的地方在于：状态只决定文案，绘制逻辑仍然是一条 `rows.size() == 0 ?` 分支，没有把 UI 拆成三套。

### 7. ✅ Timer 未释放（已修复）

```monkey-c
// 修复前：initialize 里起表，从不停止
timer = new Timer.Timer();
timer.start(method(:onTimer), 60000, true);
```

Widget 被反复进出时，旧定时器可能仍在运行并回调已失效的 View。

**修复方式**：把定时器的生命周期交给 `onShow` / `onHide`，并用 `null` 判断防重入：

```monkey-c
function initialize() {
    View.initialize();
    loadCache();          // 只做缓存恢复，不再发请求
}

function onShow() as Void {
    startTimer();
    fetchPrice();
}

function onHide() as Void {
    stopTimer();
}

function startTimer() as Void {
    if (timer != null) { return; }        // 已在跑，避免重复创建
    timer = new Timer.Timer();
    timer.start(method(:onTimer), REFRESH_MS, true);
}

function stopTimer() as Void {
    if (timer != null) {
        timer.stop();
        timer = null;
    }
}
```

顺带解决了原方案里"首刷放在 `initialize`"的语义问题：Widget 里 `onShow` 才是"被用户看到"的时机，`initialize` 只跑一次，反复进出不会重新拉数据。现在每次进入都会刷新。

### 8. ✅ 无离线缓存（已修复）

断网 / 请求失败时界面完全空白。手表最需要"最后已知价格"。

**修复方式**：成功响应时写入 `Application.Storage`，初始化时先读缓存再发请求。

存储结构刻意用了**两个平行数组**而不是嵌套字典：

```monkey-c
{ "time" => 秒级时间戳, "symbols" => ["BTC", "ETH", ...], "prices" => [101234.5, ...] }
```

原因是 `Application.Storage` 在不同设备 / 固件上对嵌套 Dictionary 的支持存在差异（`ValueType` 白名单），扁平结构最稳，也省空间——三币种大约 120 字节。

写入套了 `try/catch`：

```monkey-c
try {
    Application.Storage.setValue(CACHE_KEY, { ... });
} catch (e) {
    // 存储不可用或配额不足时静默失败：缓存只是锦上添花，不该影响主流程
}
```

否则一旦遇到存储配额满的设备，每次成功抓价都会抛异常，反而把主流程搞崩。

**遗留取舍**：缓存没有过期判断（见 README「已知限制」第 3 条），几天后打开仍会先显示旧价，只能靠副标题 `- Cache -` 区分。加时间戳成本很低，但"过期后显示什么"需要产品决策，暂不处理。

### 9. ✅ `$cacheTime = 1`（已修复）

```php
// 修复前
$cacheTime = 1;
```

1 秒的 TTL 意味着几乎每次手表请求都会穿透到 Binance，缓存只剩"并发去重"作用。

**修复**：改为 10 秒，并补上取值依据的注释（重构后挪到了 `lib.php`，成为常量 `TTCOIN_CACHE_TTL`）。

```php
// 缓存有效期（秒）。
// 手表 60 秒才请求一次，10 秒足够吸收多设备并发与突发重试；
// 若用 cron 预热（update_price.php），cron 间隔应 <= 此值，
// 让手表请求基本都命中缓存、完全不触发上游调用。
define('TTCOIN_CACHE_TTL', 10);
```

原先遗留的 `json_encode()` 失败问题已在第 15 条一并解决：`ttcoin_encode()` 检查返回值，失败时两个入口各自报错，不会再把空内容写进缓存。

### 10. ✅ 两个 PHP 文件逻辑重复（已修复）

`coin.php`（191 行）与 `update_price.php`（104 行）的抓取、解析、校验、写缓存几乎逐行相同，唯一的差异是"读不读缓存"和"输出 JSON 还是日志"。改一次币种要同步动三处：`$symbols`、完整性校验、`$result`。

**修复方式**：抽出 `api/lib.php`，两个入口变成薄壳。

| 函数 | 职责 |
| --- | --- |
| `ttcoin_symbols()` | 币种表（Binance 符号 → 显示简称），**唯一需要改的地方** |
| `ttcoin_fetch($t, $ct)` | 请求 + 解析 + 校验，返回 `['ok'=>bool,'data'=>array,'error'=>string]` |
| `ttcoin_cache_file()` | 缓存路径解析（含不可写时的回退） |
| `ttcoin_cache_read($maxAge)` | 读缓存；`$maxAge = null` 表示不检查年龄 |
| `ttcoin_cache_write($json)` | 写缓存，失败静默 |
| `ttcoin_encode($data)` | 统一 `json_encode` 参数，失败返回 `null` |

行数变化：

```
coin.php           191 → 53
update_price.php   104 → 33
lib.php             —  → 201
```

总量减少了约 8 行，但**重复的 90% 消失了**——两个入口现在只剩下"缓存策略 + 输出方式"的差异，读一遍就能看出各自在做什么。以后加币种只改 `ttcoin_symbols()` 一处，`$result` 的拼装由 `foreach` 自动完成，不再需要三处同步。

顺带把 `update_price.php` 的失败路径改成 `exit(1)`：原来只是 `echo` 一行日志就 `exit`（退出码 0），cron 邮件和监控都看不出失败。

### 11. ✅ 缓存文件在 Web 根目录（已修复）

`coin_cache.json` 与 `coin.php` 同级，可被外网直接 `GET`：虽无敏感信息，但绕过了接口逻辑，还把抓取节奏变成了公开信息。

**修复**：默认写 `<站点目录>/../cache/coin.json`，加三层防护：

```php
$dir = dirname(__DIR__) . '/cache';

if (!is_dir($dir)) {
    @mkdir($dir, 0755, true);
}

if (is_dir($dir) && is_writable($dir)) {
    $file = $dir . '/coin.json';
} else {
    $file = __DIR__ . '/coin_cache.json';   // 父目录不可写时回退
}
```

1. **位置**：移出站点目录，直接 `GET /coin.php` 的兄弟路径访问不到；
2. **`cache/.htaccess`**：`Require all denied`，兼带 Apache 2.2 的 `Order allow,deny` 分支；
3. **`api/.htaccess`**：`FilesMatch` 拒绝 `coin_cache.json` 与 `lib.php`，覆盖"回退到站点目录"的情况。

为什么保留回退而不是硬失败：不少虚拟主机的站点目录就是用户家目录根（`~/public_html`），父目录 `~` 未必可写。这种情况下让插件继续能跑，比坚持一个更好的目录结构更重要——`.htaccess` 已经把这个折衷的风险压到最低。

`.gitignore` 相应改成 `cache/*` + `!cache/.htaccess`，缓存内容不会进仓库，但目录和防护规则会。

### 12. ✅ `data == null` 无效判断

`data as Lang.Dictionary` 非空标注下 `data == null` 恒为假，异常永远不会命中这个分支。已在第 2 条中改为 `Lang.Dictionary?` 并保留 null 判断（此时它才真的可能成立）。

### 13. ✅ 变量无类型声明

`var timer; var marketData = null; var hasData = false;` 全部补上类型：`var timer as Timer.Timer?`、`var marketData as Lang.Array?`、`var state as Lang.Number`、`var subtitle as Lang.String`。成员类型确定后，`-l 1/-l 2` 的警告从 15 条降到 0 / 2。

### 14. ✅ `layout.xml` 空模板残留（已修复）

```xml
<layout id="MainLayout">

</layout>
```

全项目没有一处引用 `MainLayout`——视图是纯 `drawText` 画的。留着只会让读代码的人以为有 XML 布局参与渲染，每次改界面都得先去确认一遍"这个到底用不用"。

已删除 `resources/layouts/layout.xml` 及空目录 `resources/layouts/`，编译验证仍然 `BUILD SUCCESSFUL`。

### 15. ✅ 未校验 `price` 是否为数字（已修复）

```php
// 修复前：上游给什么就转什么
$prices[$item['symbol']] = (float)$item['price'];
```

`(float)` 对 `'abc'` 得到 `0.0`、对 `'1e400'` 得到 `INF`、对 `'NaN'` 得到 `NAN`。后面两个会让 `json_encode()` 返回 `false`（旧代码没检查返回值），最终把**空内容写进缓存文件**，手表端则表现为一直 `No Data`。

**修复**：不再转 `float`，改成"能格式化成可显示文本才收"，非法值直接跳过该条：

```php
$display = ttcoin_format_price($item['price']);

if ($display === null) {
    continue;                       // 'NaN' / 'INF' / '' / 'abc' / 对象
}

$prices[$item['symbol']] = $display;
```

`ttcoin_format_price()` 内部先用 `/^-?\d+(\.\d+)?$/` 匹配常规十进制字面量，按字符串逐位处理；不匹配的再走 `is_numeric()` + `is_finite()` 兜底（`'1e400'` 是合法数字字面量，但会溢出成 `INF`，用 `number_format` 之后仍得到有限值才会被接受）。

顺带完成的另一件事：**`price` 从数字改成了字符串**。原来看起来只是"校验变严"，实际上顺手解决了客户端小数位失真——见第六节。同时 `ttcoin_encode()` 检查 `json_encode` 的返回值，编码失败返回 `null`，两个入口各自报错而不再写脏缓存（第 9 条里"`json_encode()` 失败"那个遗留项也就关了）。

---

## 三、发布前 Checklist

- [x] 补充 `README.md`（含部署、接口约定、排错）
- [x] 补充 `.gitignore`（排除 `bin/`、`*.der`、服务端缓存）
- [ ] **把 `apiUrl` 的默认值换成占位符（或发布前改成你自己的地址），并确认仓库中没有你的真实域名**
- [x] 修掉 `onReceive` 的类型标注（第 2 条）
- [x] 修掉硬编码数组索引，改为遍历 + 逐条校验（第 4 条）
- [x] 补错误状态提示（第 6 条）
- [x] Timer 改由 onShow/onHide 管理（第 7 条）
- [x] 加 Application.Storage 本地缓存（第 8 条）
- [x] 服务端缓存 TTL 1s → 10s（第 9 条）
- [x] 抽出 `api/lib.php`，消除两个入口的重复逻辑（第 10 条）
- [x] 缓存移出 Web 根目录 + `.htaccess` 兜底（第 11 条）
- [x] 删除空的 `layout.xml` 模板（第 14 条）
- [x] 校验 `price` 为数字且有限（第 15 条）
- [x] 布局坐标改为按屏幕比例缩放，176×176 上逐像素一致（第 5 条）
- [ ] 确认 `git status` 里没有 `bin/`、`*.der`、`cache/coin.json`
- [ ] 确认 `cache/.htaccess` 与 `api/.htaccess` 已随提交进入仓库（`.gitignore` 里有 `!cache/.htaccess` 例外）
- [x] 补 `LICENSE`（MIT，署名 TTCoin contributors）
- [ ] 加真机截图到 `docs/screenshot.png`（README 已预留注释位）
- [ ] 仓库 About 填一句描述 + Topics：`garmin` `connect-iq` `monkey-c` `crypto` `widget`

```bash
# 建议的首次提交
git init
git add .
git status          # ← 先看这里，确认没有敏感文件
git commit -m "feat: TTCoin widget for Garmin Instinct 2X"
git branch -M main
git remote add origin https://github.com/<your-name>/TTCoin.git
git push -u origin main
```

## 四、可以做的后续增强

1. **Glance 支持**：实现 `WatchUi.GlanceView`，让价格出现在小工具列表中，不用点进去。
2. **24h 涨跌**：把接口换成 `/api/v3/ticker/24hr`，多返回一个 `changePercent` 字段，用 `▲/▼` 表示（注意 MIP 屏无彩色，需用符号而非颜色）。
3. **多币种配置**：设备端用 `Properties` 存币种列表，通过 Garmin Connect 的 App Settings 修改。显示层已就绪：超过 3 个币种自动按页轮播（`PAGE_MS` 8 秒/页，副标题带页码），加币种仍只需改 `ttcoin_symbols()` 一处。
4. **多源容灾**：`coin.php` 里 Binance 失败时回退 OKX / Coinbase。

---

## 五、踩坑记录：Monkey C 的数值类型不是继承关系

这一条是实测踩出来的，`-l 1` 编译期**完全不会报错**，只在真机上表现为"一直 No Data"。

**错误写法**（曾经出现在 `buildRows()` / `saveCache()` / `loadCache()` 里）：

```monkey-c
if (!(price instanceof Lang.Number)) { continue; }   // ← 恒为 true，全部被跳过
```

**原因**：Monkey C 里 `Number` / `Float` / `Double` / `Long` 是四个**平级**类型，全部直接继承 `Lang.Object`，彼此没有任何继承关系。查 SDK 文档的 Inherits 字段即可确认：

| 类型 | 文档中的 Inherits | 含义 |
| --- | --- | --- |
| `Lang.Number` | `Toybox.Lang.Object` | 32 位有符号整数 |
| `Lang.Float` | `Toybox.Lang.Object` | 32 位浮点 |
| `Lang.Double` | `Toybox.Lang.Object` | 64 位浮点 |
| `Lang.Long` | `Toybox.Lang.Object` | 64 位整数 |

而 JSON 解码出来的价格是 `Float` / `Double`（32 位的 `Number` 存不下 `0.2311` 这种小数），所以 `instanceof Lang.Number` 永远为 `false`，每一条行情都被判为"非法"跳过 → `rows` 恒为空 → 状态却是 `STATE_OK` → 界面显示 `No Data`。

**正确写法**：显式覆盖四种类型，再统一转 `Float`：

```monkey-c
function isNumeric(value as Lang.Object?) as Lang.Boolean {
    return value instanceof Lang.Number
        || value instanceof Lang.Float
        || value instanceof Lang.Double
        || value instanceof Lang.Long;
}

function numericToFloat(value as Lang.Object?) as Lang.Float? {
    if (value instanceof Lang.Double) { return (value as Lang.Double).toFloat(); }
    if (value instanceof Lang.Float)  { return value as Lang.Float; }
    if (value instanceof Lang.Long)   { return (value as Lang.Long).toFloat(); }
    if (value instanceof Lang.Number) { return (value as Lang.Number).toFloat(); }
    return null;
}
```

**同类陷阱**：`Lang.String` 与 `Lang.Char` 也是平级关系，用 `instanceof Lang.String` 判断"是不是文本"时，`Char` 会漏掉；`Lang.Dictionary` 与 `Lang.Array` 同理（这也是 SDK 把 `makeWebRequest` 回调声明成 `Dictionary or String or Iterator` 却永远匹配不上 Array 的根源）。

---

## 六、踩坑记录：Float 是 32 位，价格不要在手表端格式化

现象：BTC 实际 `75678.78`，表上画出 `75678.7812`；ETH 实际 `2235.51`，画出 `2235.51`（正常）；DOGE 实际 `0.07161`，画出 `0.0716`（正常）。看起来像"只有大数字出错"。

**原因不是四舍五入，是存储精度。** Monkey C 的 `Float` 是 32 位 IEEE-754，尾数 24 位，大约只有 7 位有效数字。`75678.78` 需要 9 位有效数字，落进 float32 会变成：

```
75678.78  →  float32  →  75678.78125
```

可以手算验证：`75678.78` 落在 `[2^16, 2^17)` 区间，该区间 float32 的间隔是 `2^16 × 2^-23 = 0.0078125`；`75678.78 / 0.0078125 ≈ 9686883.84`，取最近的整数得到 `9686884 × 0.0078125 = 75678.78125`。再 `format("%0.4f")` 自然输出 `75678.7812`——后两位是纯噪声，跟真实价格无关，靠"去掉末尾 0"是去不掉的（它们不是 0）。

`-l 0/1/2` 全程不会报任何警告：类型正确、语法正确，只是数值本身已经被截断。

**修复：小数位在服务端定，客户端只显示字符串。**

`api/lib.php` 的 `ttcoin_format_price()` 全程用字符串 / 整数运算：

| 步骤 | 例子 |
| --- | --- |
| 拆成符号、整数、小数三段 | `0.07161000` → `''`, `0`, `07161000` |
| 去掉小数尾部 0 | `07161000` → `07161` |
| 超过 4 位才四舍五入：看第 5 位 | `07161` 第 5 位是 `1` → 不进位 |
| 截到 4 位，再清一次尾零 | `0716` → `0.0716` |

需要进位时把"整数部分 + 前 4 位小数"拼成一个整数串，末位 `+1` 处理连续进位（`9.99999 → 10`、`0.99995 → 1`），最后按固定宽度切回整数与小数。整数位数加 4 位小数最多 12 位，`int` 完全够用。

客户端 `TTCoinView.mc` 的 `priceText()` 只做三件事：是 `String` 就直接返回；是 `Double`（64 位，精度足够）才 `format("%0.4f")` 兜底；其余返回 `null` 让该行被跳过。`Float` 分支故意不提供——它正是问题的来源。

**通用结论**：Monkey C 里凡是"必须精确显示"的数值（价格、距离、金额），一律以字符串传递。`Float` 只适合做比较、做进度条这类允许误差的场合。

---

## 七、多交易对的显示：自动轮播

Widget **不支持按键输入**（这是 Connect IQ 的形态限制，不是代码问题），所以"手动翻页"在 Widget 里做不到，只有两条路：压缩行距塞满一屏，或定时轮播。本项目选择后者，保持每屏 2 组（每组两行）的字号与呼吸感。

### 实现

| 常量 | 值 | 作用 |
| --- | --- | --- |
| `PAGE_ROWS` | 2 | 每屏币种数（每组两行：价格 + 涨跌） |
| `PAGE_MS` | 8000 | 每页停留时长 |
| `FETCH_TICKS` | 8 | 每 N 拍抓一次行情（8 × 8s ≈ 64s） |

关键取舍：**轮播和抓取共用一个 Timer**。Timer 每 8 秒走一拍，多数拍只翻页 + `requestUpdate()`，每逢第 8 拍才发 HTTP 请求——避免了第二个定时器实例，也把刷新节奏从固定 60 秒变成约 64 秒（对行情场景无感知差异）。

行为矩阵：

| 币种数 | 页数 | 显示 |
| --- | --- | --- |
| 1~2 | 1 | 副标题无页码 |
| 3~4 | 2 | 每 8 秒翻页，副标题 `- Coin - 1/2` |
| 5~6 | 3 | 同上，`1/3` |
| N | ⌈N/2⌉ | 页码 = `(pageIndex + 1) % ⌈N/2⌉` |

`buildBlocks()` 不再截断（返回全部合法行），截断职责移到 `onUpdate()` 的按页切片。币种减少导致页码越界时，`pageIndex >= pages` 分支回卷到首页，不会画出空页。

### 已知代价（如实记录）

1. **Widget 生命周期短**：进入小工具页几秒后就被系统回收，8 秒/页的轮播多数时候翻不到第二页。轮播对"停留较久"的场景（抬腕不放下）才真正有意义。
2. **翻页瞬间会整屏重绘**：`requestUpdate()` 触发的 `onUpdate` 会重画全部元素，MIP 屏上可能看到轻微闪烁。若介意，可改成只请求局部更新（`requestUpdate()` 无局部参数，需用 `WatchUi.requestUpdate` 之外的低层 API，收益不大）。
3. 需要**按键手动翻页 / 菜单选币种**时，唯一出路是把项目改成 Watch App（`manifest` 的 `type` 从 `widget` 改 `app`，生命周期与入口全部重做）。

---

## 八、改成 Watch App：选币 / 排序 / 涨跌

应用从 Widget 转为 Watch App（`manifest.xml` 的 `type="watch-app"`），换来按键输入能力，三个新功能全部落在这上面。

### 结构

| 文件 | 职责 |
| --- | --- |
| `TTCoinApp.mc` | `getInitialView()` 返回 `[View, Delegate]` 二元组 |
| `TTCoinDelegate.mc` | `BehaviorDelegate`：Start→菜单、Up/Down→翻页、Back→系统默认退出 |
| `TTCoinMenu.mc` | 三层 `Menu2`：主菜单 → 勾选（`ToggleMenuItem`）/ 排序（上移下移） |
| `TTCoinView.mc` | 选币/排序的持久化逻辑 + 涨跌渲染 + 缓存 v3 |

**配置模型**：启用开关用 `Properties`（`enabledBTC` 等布尔项），手机端设置与手表菜单写同一批键，天然同步；显示顺序用 `Application.Storage` 存完整候选表数组（手机端不暴露排序，只有手表能调）。实际显示 = 顺序表过滤掉未启用项；全没启用时回退默认三币种。

**涨跌**：服务端换 `ticker/24hr` 端点，多返回 `change` 字符串（复用 `ttcoin_format_price()` 去尾零）；客户端 `changePercent()` 只去掉负号拼 `%`，`isUp()` 判方向，方向由 `fillPolygon()` 画的小三角表达（为什么不用 `▲/▼` 见第九节）。每个币种占两行（价格 `FONT_MEDIUM` + 涨跌 `FONT_TINY`），行距用第九节那套布局常量控制。

### 两个编译期踩坑（都实测过）

1. **manifest 的 type 名**是 `watch-app` 而不是 `app`（后者报 `Unknown app type`）。
2. **settings.xml 的 propertyKey** 必须写 `@Properties.<id>`，编译器把前缀之后的内容与 properties.xml 里的 id **严格相等匹配**——写成文档里常见的 `@Properties.Persisted.enabledBTC` 会报 `Property not found for the property key 'Persisted.enabledBTC'`，因为这个 SDK 的编译器没有任何 `Persisted.` 前缀处理逻辑（反编译 SettingsProcessor/Setting 确认）。另外 properties.xml 必须能被 `base.resourcePath` 覆盖到，且 `settings.xml` 的位置在 `resources/` 根（与官方样例一致）。

### Menu2 / BehaviorDelegate API 要点（SDK 9.2.0 实测）

- `MenuItem(label, subLabel, identifier, options)` —— identifier 在 options 之前；
- `ToggleMenuItem(label, subLabel, identifier, enabled, options)` —— 勾选状态由 Menu2 自动翻转，`onSelect` 只管持久化；
- `WatchUi.popView()` 必须传过渡参数（`WatchUi.SLIDE_IMMEDIATE`），无参调用编译报错；
- `Array` 没有 `contains()`，`remove()` 按对象删而非按索引，插入用 `slice` 重组；
- `BehaviorDelegate` 的 `onSelect/onNextPage/onPreviousPage` 返回 `true` 表示消费按键。

---

## 九、真机截图暴露的三个排版问题

模拟器跑起来后的第一屏是这样的：标题只剩 `- Coi-`，第一行变成 `BTC 7560___.49`，最后一行涨跌被屏幕下沿切掉一半，涨跌前面还有个说不清的菱形。三个问题是三种不同的原因。

### 1. 屏幕不是矩形：八边形 + 手电筒挖孔

不是"坐标算错"，是**画到了显示不出来的地方**。SDK 的界面参考文件 `resources/device-reference/instinct2x/layout0.svg` 里写着这张屏的真实遮罩：

```svg
<path d="M 39.6,0 L 136.4,0 L 176,39.6 L 176,136.4 L 136.4,176 L 39.6,176 L 0,136.4 L 0,39.6 Z"/>
<circle cx="144" cy="31" r="31"/>
```

- 八边形：四角各切掉 39.6px，左上斜边是 `x + y = 39.6`；
- 圆：右上角手电筒，圆心 `(144,31)`、`r=31` 是**灯孔内径**。

逐像素扫描模拟器截图量出来的真实结构（第三轮修正，前面两版都判断错了）：

| 范围 | 性质 |
| --- | --- |
| 灯孔内部：`x 113..175`、`y 0..62`（就是 `r=31` 那个圆） | **可以画**。第一版截图里 `75607.49` 的尾数 `.49` 在环带后面又出现了，说明圆内是屏幕而不是机身 |
| 环带：内径 31 → 外径 37（约 6px 宽） | 机身金属环，盖住屏幕；左沿 `x 107..113`、下沿 `y 62..68` |
| 环外左上方的机身 | `y<68` 且 `x>107` 的一圈灰色，只是环的余量，不影响文字 |

所以「头顶上那团不能画」是错的：**只有 6px 的环带挡住屏幕**，价格被吃掉是因为它正好压在环带上（`y 43..58`、`x 107..113` 那一段），而不是因为整块圆都不可绘。

可用高度划分（176px 总高）：

| 区域 | 约束 | 现在的取值 |
| --- | --- | --- |
| 标题 | 左上斜边与灯孔之间，`x 2..107` 居中 | `TITLE_CX=55`、`TITLE_Y=26`（字面 31..44） |
| 页码 | 标题下面单独一行（并进标题会顶到环带） | `PAGE_DY=18`（字面 50..62） |
| 灯孔标 | 圆心，`TT` 两个字母 | `BADGE_CX/CY=144/31` |
| 全宽内容 | 必须从环带下沿 `y≈68` 之后 | `CONTENT_TOP=69`（字面从 76 开始） |
| 底部 | 八边形下半斜角：`x_min = y − 136.4` | 最宽的一行不超过 `y≈163` |
| 每组内容 | 价格 16px + 涨跌 13px | `PRICE_TO_CHANGE=25`、`BLOCK_PITCH=50` |

### 2. 三组两行排不下：`getFontHeight()` 的 cell 比字面高得多

实测这台设备的字体度量：`FONT_SMALL=23`、`FONT_MEDIUM=31`、`FONT_TINY=19`（cell 高，不是字面高），字面高度分别约 15 / 16 / 13。

旧代码用 `stride = priceH + chgH + 2 = 31 + 19 + 2 = 52`，三组 156px，加上标题 23px 和顶部留白，总高 191px —— 比屏幕还高 15px，第三行涨跌必然被切。

**结论**：`getFontHeight()` 返回的是行盒高度，含上下留白，不能直接当行距用。两行文字要"负重叠"排：价格 cell 顶部到涨跌 cell 顶部只走 25px，靠字体自带的下留白容纳涨跌行的字面（字面之间仍有 3px 空隙）。

**为什么最后是每屏 2 个币种**：环带下方能放整行宽文本的只剩 `y 76..163`，一共 88px。价格 16px + 可读的涨跌 13px，一组 29px 纯字面 + 组内 8px 间隙 = 37px，两组 74px，组间还剩 13px；三组就是 111px，必然粘连。

中途试过把涨跌降到 `FONT_XTINY` 来硬塞三组，结果截图放大后发现 **XTINY 的数字只有 6px 高**（`FONT_TINY` 是 13px，两者断崖式差一档），远看是一排模糊的小点，不可用。也试过把涨跌并到价格同一行：`BTC 75713.04` 本身就占 127px，再加三角和 `0.355%` 要 190px，176px 的屏放不下。

所以定稿是 `PAGE_ROWS = 2`：每屏两组、每组两行，`BLOCK_PITCH=50`（组内 8px、组间 13px）。更多币种靠 8 秒轮播 + Up/Down 翻页。

### 3. `▲` / `▼` 在 Garmin 内置字体里不存在

截图里涨跌前的那个 `◇` 不是设计，是**缺字占位符**。Garmin 的位图字体只有拉丁字母、数字和少量符号，`U+25B2/U+25BC` 不在其中，`drawText` 遇到就画一个空心菱形。

改法：不依赖字体，用 `dc.fillPolygon()` 直接画 7×6 的实心三角，文本只留百分比：

```monkeyc
if (up) {
    dc.fillPolygon([
        [left, arrowY + ARROW_H],
        [left + arrowW, arrowY + ARROW_H],
        [left + arrowW / 2, arrowY]
    ]);
}
```

### 4. 顺带解决：长价格溢出

`FONT_MEDIUM` 下一行 `BTC  75607.49` 已经占 127px，再接一位小数就会顶到屏幕边。`choosePriceFont()` 用 `dc.getTextWidthInPixels()` 逐行量宽，整页统一取能放下的最大档（MEDIUM → SMALL → TINY），不会再出现"数字被屏幕边缘切一半"。

### 验证方式（没有真机也能做）

1. 编译矩阵：SDK 8.1.0 / 9.2.0 × `-l 0/1/2` 全部 `BUILD SUCCESSFUL`；
2. 排版预演：把旧截图里的字形位图裁出来，按新常量重新拼一张 176×176 图，再叠上 `layout0.svg` 的遮罩（八边形 + 圆），就能在改动之前看到"哪一行会被吃掉"。这轮的三处遮挡都是这样先定位、再改代码的；
3. 最后仍以真机截图为准——字体的字面偏移（ascent）只能实测。

---

## 十、手机端设置为什么看不到：侧载应用不参与账号同步

真机装好后打开 Garmin Connect，路径 `设备 → 我的应用` 里只有从商店装的两三个应用，TTCoin 不在其中，`我的小工具` 也是空的；自然也就没有 `settings.xml` 定义的那一页设置。这不是 `settings.xml` 写错，而是**分发方式决定的结果**：

| 安装方式 | 是否出现在 Garmin Connect 的「我的应用」 | 有没有应用设置页 |
| --- | --- | --- |
| Connect IQ 商店 / Beta App | 在（账号里能查到记录） | 有，Garmin Connect 按 `settings.json` 渲染 |
| 数据线拷 `.prg` 到 `GARMIN\APPS`（侧载） | 不在 | **没有** |

设置界面本质上是「服务器上的应用元数据 + 手机端 UI」，侧载的 `.prg` 在服务器上没有记录，手机端就无从渲染，也没有条目可点。`bin/TTCoin-settings.json` 只是编译产物，装到表上并不等于注册了这个应用。所以之前"在 Garmin Connect 里改接口地址"的说法只对商店安装有效。

### 处理方式

1. **把配置搬到表上（已实现）**。官方文档明确写着「Device applications, widgets, and audio content providers all accept user input」（API 3.2.0 起），而 `WatchUi.TextPicker` 从 1.1.0 就有、且支持 Instinct 2X。于是在 Start 菜单里加了第三项：

   ```
   Start → 接口地址 → [系统文本输入框，预填当前地址] → 确认
   ```

   值写进 `Storage["ttcoin_api_url"]`（同时也 `Properties.setValue("apiUrl", ...)` 备份一份），`apiEndpoint()` 的优先级变成 **Storage → 属性 apiUrl → `DEFAULT_API`**，每次抓取前现读，保存后立刻重拉一次。留空保存 = `Storage.deleteValue` 清除覆盖，回到 `properties.xml` 的默认值。结果用标题位显示 4 秒：`- Saved -` / `- Bad URL -` / `- Reset -` / `- Save Fail -`。

2. **确实要手机端改，就把应用上传成 Beta App**。`manifest.xml` 换一个 UUID 的 app id，Connect IQ 后台勾选 Beta 上传；Beta 应用会进账号的应用列表，下载后 Garmin Connect 里就能看到设置页（官方文档 `Beta_Apps.html`：「Once downloaded you can edit app settings in Garmin Connect and Garmin Express」）。代价是要开发者账号 + 审核流程，自己用不必走这条。

3. **调试期想验证设置项**：Connect IQ 模拟器 `File → Edit Persistent Storage → Edit Application.Properties data`，改完直接下发到模拟器，不需要真机。

### 一个顺带的结论

`WatchUi has :TextPicker` 这种编译期判断挡不住"设备不支持"，但它在 SDK 里是模块成员判断，用来兜住老 SDK 编译即可；真正运行时若机型没有原生输入，`pushView` 会静默失败（菜单还在，点了没反应），这比抛异常好——所以这里没有再加设备白名单。

> **2026-11 更新**：手表端手输接口地址的功能已按需求整体移除（见第十六节），本节保留作为历史记录与方案取舍的依据。

---

## 十一、请求带上设备唯一标识（`?uid=`）

需求：服务端要能区分是哪块表在请求。Garmin 官方给的标识是 `System.getDeviceSettings().uniqueIdentifier`（API 2.4.1+），三个关键性质都写在文档里：

1. 同一设备 + **本应用**恒定，卸载重装不变；
2. **不同应用之间取值不同**——它不是整机序列号，关联不到其他应用或 Garmin 账号，天然是匿名区分符；
3. 出错时返回 `null`，且文档提醒"用于追踪用户须符合隐私法规"。

### 客户端（两个形态都改了）

`fetchPrice()` 里给 `makeWebRequest` 的参数字典带上 `uid`（取不到就整个省略参数，不是发空串）：

```monkey-c
var params = {};
var uid = deviceUid();          // getDeviceSettings().uniqueIdentifier，null 兜底
if (uid != null) {
    params.put("uid", uid);
}
```

makeWebRequest 会把参数字典编成 query string，最终请求 `GET /coin.php?uid=ac915d...`。

### 服务端

`lib.php` 新增 `ttcoin_client_uid()`：只留 `[A-Za-z0-9]`、截断到 64（`uniqueIdentifier` 本身就是十六进制样式的字母数字串，白名单清洗足够）。`coin.php` 当前只把它回显到响应头 `X-TTCoin-Uid`，方便浏览器里 `curl -I 'coin.php?uid=test123'` 端到端验证；**不参与缓存键**——服务端缓存是全体设备共享的，按 uid 分缓存会把中转层的省流量意义抵消掉。将来做按设备统计 / 限流时，直接取 `ttcoin_client_uid()` 的返回值。

### 顺带的坑

模拟器里 `uniqueIdentifier` 返回的是模拟器固定值，多开几个模拟器实例 uid 相同——按设备区分的统计在模拟器上验证不了，要真机。

## 十二、按设备记请求日志

需求：服务端每次请求落一行日志，能看出是哪块表、什么时候、结果如何。

### 实现

`lib.php` 新增两个函数，与缓存同一套目录策略：

- `ttcoin_log_file()`：`<数据目录>/logs/coin.log`，数据目录默认是站点目录的上一级，可用常量 / 环境变量 `TTCOIN_DATA_DIR` 覆盖（见 `TTCoin_API/README.md` 的「数据目录：缓存与日志放哪」）；子目录建不出来才退回与 `coin.php` 同级的 `coin.log`（`.htaccess` 的 `FilesMatch` 已加 `coin\.log(\.old)?` 兜底拒绝外网访问）；
- `ttcoin_log_request($type, $uid, $event, $detail)`：追加一行制表符分隔 6 列——`时间 \t 形态 \t uid \t REMOTE_ADDR \t 事件 \t 备注`。`$detail` 来自上游报错文本，先压掉 `\r\n\t` 保证一行一条；写入失败静默（日志不能影响接口）。

`coin.php` 四个出口各埋一点：`hit`（命中缓存）/ `fresh`（重拉成功）/ `stale`（上游失败返回旧缓存）/ `error`（502/500，备注带原因）。

### 设计取舍

- **命中缓存也记**：不然日志只能看到上游调用，看不出每块表的活跃节奏——这正是 uid 的主要用途；
- **2MB 自动滚动**为 `coin.log.old`（覆盖上一代）：手表 60 秒一请求，一行约 80 字节，2MB 约 7 个月的量，滚动只是防被刷时的保险，不值得上按天轮转；
- **uid 不做哈希/脱敏**：它本身已是匿名标识（见第十一节），存原文反而方便 grep；
- **形态标记 `?type=app|widget`**：两个客户端各带一个固定值，`ttcoin_client_type()` 白名单只认这两个值（其他按未提供处理，日志记 `-`）。同一块表装两种形态时，`uid` 相同、`type` 不同——想看"某块表"用 uid 过滤，想看"某种形态的活跃度"用 type 过滤；
- **IP 只排障用**：REMOTE_ADDR 在有 CDN 时是节点 IP 而非真实用户 IP，别拿它做统计，真实用户分析看 uid。

### 验证

```bash
curl -s 'https://your-domain.com/coin.php?uid=test123' > /dev/null
tail -1 ../logs/coin.log
# 2026-11-08 07:05:49  test123  203.0.113.7  fresh
```

### 一个把日志写成一行的 bug

最初把整行 `sprintf` 拼好后再统一 `str_replace(["\r", "\n"], ' ', $line)`，结果行尾那个 `\n` 一起被换成空格——日志文件里所有记录首尾相接，`tail -1` 只能看到"整个文件"。正确顺序是**先清洗字段再拼行**：`detail` 单独压掉 `\r\n\t`，`sprintf` 里的 `\n` 保持着落。

配套两个细节：

- 增量兼容：旧文件末尾没有换行，直接追加会让第一条新记录粘在旧内容后面，故写入前 `fseek(-1, SEEK_END)` 探一个字节，不是 `\n` 就补一个前缀换行（顺序为先进 `rb` 句柄、读到就关，不影响 `FILE_APPEND | LOCK_EX`）；
- 滚动后 `$size` 要重取：`rename` 成功后原文件已不存在，若沿用旧 `$size` 会误判"文件非空"。

## 十三、小额价格放大：显示名带倍数，匹配仍用简称

### 问题

SHIB 的原始价格是 `0.00001826`，服务端按 4 位小数四舍五入后变成 `"0"`——屏幕上这一行等于没有信息。单纯把 `TTCOIN_MAX_DECIMALS` 调到 8 只能救急：`0.00001826` 在 176px 宽的表盘上又长又难读，而且不同币种位数不一致，观感很乱。

### 服务端的做法

按小数部分前导 0 的个数 n 放大，倍数写进币种名（`lib.php` 的 `ttcoin_scale_price()`）：

| n | 原始值 | 倍数 | 输出 | 显示名 |
| --- | --- | --- | --- | --- |
| 3 | `0.000123` | ×100 | `0.0123` | `100*XXX` |
| 4 | `0.00001826` | ×1000 | `0.01826` | `1000*XXX` |
| 5 | `0.00000715` | ×10000 | `0.0715` | `10000*XXX` |

倍数 `10^(n-1)` 的效果是"第一个有效数字落到小数点后第 2 位"，放大后的数字量级统一在 `0.0x`，读起来和 `0.07`、`0.18` 这些常规币种一致。实现是**移位小数串**（`"0.0" + "1826"`），不经过 float，避免 `0.018260000000000002`。

响应因此变成三件事分开：

```json
{ "symbol": "1000*SHIB", "base": "SHIB", "price": "0.01826", "change": "-1.32" }
```

- `symbol` —— 显示成什么（可能带倍数前缀）；
- `base` —— 原始简称，永远等于 `ttcoin_symbols()` 里的名字；
- `price` —— 已格式化好的字符串。

### 表端必须跟着改的地方

`findQuote()` 原来直接拿 `symbol` 和菜单标签比：

```monkey
if (!(symbol as Lang.String).equals(label)) { continue; }   // ❌ 1000*SHIB ≠ SHIB
```

不改的话，一旦服务端开始下发 `1000*SHIB`，APP 里勾选的 SHIB 会**整块消失**（`findQuote` 找不到 → `buildBlocks()` 少一条）。

现在抽了 `matchesLabel()`：

1. 有 `base` 字段就比 `base`（新数据走这条）；
2. 没有 `base` 就退化成"去掉 `NNN*` 前缀再比"——本地缓存里只存了显示名，这条保证缓存态也能选中；
3. 顺便兼容"只更新了服务端、还没重编表端"的组合。

Widget 版不按标签筛选（`buildRows()` 直接把服务端返回的每一行都画出来），所以它**不需要改代码**，显示名带前缀会自动生效。

### 版式影响

`1000*SHIB: 0.01826` 比 `LINK: 10.81` 长一倍，两边原有的"最宽一行放不下就整页降字号"逻辑会自动处理：APP 版 `choosePriceFont()` 从 MEDIUM 降到 SMALL/TINY，Widget 版 `chooseRowFont()` 同理。代价是含 SHIB 的那一页整体字号偏小，这是刻意接受的——总比显示成 `0` 或把字顶出八边形好。

### 验证

- 服务端：`lib.php` / `coin.php` 经 php-parser 解析通过；`ttcoin_scale_price()` 的阈值与进位逻辑用等价 Python 实现跑了 19 组样本（含 `0.00001826` → `0.01826/1000`、`0.0001` 不放大、`0.00000123` → `0.0123/10000`）；
- 表端：`monkeyc -l 2` 类型检查通过，告警数与改动前一致（8 条，均为既有的 `Any`/字典多态提示）。

## 十四、默认顺序 / 默认勾选改成跟接口走

### 问题

原来客户端有两处写死的真相：

- `TTCoinView.COINS` 是候选表，也是"默认顺序"；
- `properties.xml` 里 `enabledBTC/ETH/DOGE = true`，其余 false，是"默认勾选"。

服务端 `ttcoin_symbols()` 才是真正的候选池和顺序（而且加了 SHIB 之后是 11 个），两边一不一致就出问题：`COINS` 里没有 SHIB，所以 **APP 版永远显示不出 SHIB**，哪怕服务端已经下发了；服务端调整顺序，表上也纹丝不动。

### 做法

把"顺序"和"默认勾选"都改成从接口推导，客户端只留一份兜底：

1. `apiOrder()`：按 `marketData` 的原始顺序取币种简称（优先 `base`，旧缓存没有就剥掉 `10000*` 这类倍数前缀）。`catalog()` 直接返回它 —— 菜单和行情列表用的是同一个顺序。没拿到过任何数据（首启离线）时才退回 `COINS` 兜底表。
2. `normalizedOrder()`：用户排过序就用存储的顺序；没排过就用 `apiOrder()`。原来这里补的是 `COINS`，现在补接口顺序。
3. `isCoinEnabled()`：新增 `selectionUntouched()` 判断用户到底动没动过勾选 —— 逐一对比属性和 `BUILTIN_ON = [BTC, ETH, DOGE]`（即 properties.xml 的编译期初始值）。**全程一致 → 认为没动过 → 按接口顺序取前 `DEFAULT_COUNT = 3` 个**；只要有一项不一致 → 完全按属性来。这样"前 3 个"是位置概念，服务端换顺序表上也跟着换，不需要再改表端代码。
4. `effectiveCoins()`：一个都没勾（用户主动全关）时，回退到"接口顺序前 3 个"，和默认口径保持一致。

### 为什么不落库

没有采用"首启时按接口顺序写一遍属性"的种子方案：那会覆盖用户在手机端已经配好的勾选，而且写一次之后就固化了。现在纯读时推导，不动任何持久化数据，行为完全由"属性是否还是初始值"决定。用户改回初始组合（比如取消又勾回 BTC）会被重新当作未配置，但结果一样，没有副作用。

### 顺带修掉

- `properties.xml` / `settings.xml` 补了 `enabledSHIB`，手机端设置里能看到 SHIB 开关（之前属性都没有，勾了也没地方存）；
- `COINS` 兜底表补上 SHIB，注释改成"只在首启离线时撑菜单"；
- README 的"加币种要改四处"改成"正常只改服务端一处"。

### 验证

- 8.1.0 / 9.2.0 两个 SDK `-l 2` 编译通过，告警仍是既有的 `Any`/多态提示；
- 用等价 JS 实现跑了 6 组场景，输出符合预期：
  | 场景 | 期望 | 实际 |
  | --- | --- | --- |
  | 全新安装，接口顺序 BTC ETH DOGE SHIB SOL | 前 3 个 | `BTC, ETH, DOGE` |
  | 服务端把 SHIB 调到第一个 | 跟着变 | `SHIB, BTC, ETH` |
  | 用户改过勾选（只开 SOL） | 尊重属性 | `BTC, ETH, DOGE, SOL` |
  | 用户全关 | 回退前 3 | `BTC, ETH, DOGE` |
  | 用户排过序（DOGE 提前） | 用排过的 | `DOGE, BTC, ETH` |
  | 首启无数据无网 | 兜底表前 3 | `BTC, ETH, DOGE` |
- 模拟器本轮连不上（1234 loopback 被拒，同 WinNAT 问题），未做界面截图。

## 十五、服务端按形态裁剪：Widget 只回前 3 项

### 由来

Widget 版一屏 3 行（`PAGE_ROWS = 3`），而候选池已经涨到 11 个币种。给 Widget 回 11 项时：

- 响应体积是必要的 3~4 倍，全部经手机蓝牙转发；
- 手表端要解析 11 个对象、算页数，再画 3 行——大部分工作白做；
- Widget 显示几秒就被系统回收，8 秒/页的轮播基本翻不到第二页，多出来的条目根本没有机会被看到。

### 做法

在服务端加一个开关，按 `?type=` 决定出口条数：

```php
// lib.php
define('TTCOIN_WIDGET_LIMIT', true);   // 默认开
define('TTCOIN_WIDGET_TOP_N', 3);      // 与 Widget 的 PAGE_ROWS 对齐

function ttcoin_filter_output($json, $type) { ... }   // 只裁出口，不动缓存
```

`coin.php` 的三个出口（`hit` / `stale` / `fresh`）都过一遍 `ttcoin_filter_output()`；`error` 出口本来就没有列表，不处理。

**关键设计：缓存里始终是完整列表。** 裁剪发生在 `echo` 之前，而不是写缓存之前。如果按形态写缓存，会出现两个问题：

1. 谁先请求谁决定缓存内容——Widget 先来，App 随后就只能拿到 3 项，得等 TTL 过期才恢复；
2. 开关切换后必须手工删缓存才生效。

现在缓存是"全量、形态无关"的，App / Widget 共用；开关随时切换，下一次请求就生效，一次上游都不用多抓。代价是命中缓存时要 `json_decode` + `array_slice` + `json_encode` 一次，11 个对象量级可以忽略。

### 开关的三种写法

| 方式 | 写法 | 适用 |
| --- | --- | --- |
| 默认 | 什么都不做 | 开（推荐） |
| `config.php` | `define('TTCOIN_WIDGET_LIMIT', false);` | 站点目录已有 config.php |
| 环境变量 | `TTCOIN_WIDGET_LIMIT=0` | 容器部署，改环境变量重启即可 |

常量用 `if (!defined(...))` 包住，所以 config.php 的值优先；环境变量只认 `0` / `false` / `off` / `no` 为关闭，其余（含未设置）都算开启——避免 `=off` 这种写法被当成"非空字符串 = 真"。

### 顺带的可观测性

命中精简模式时，请求日志第 6 列写 `top3`：

```text
2026-11-08 10:20:11	widget	ac915d42…	203.0.113.7	hit	top3
2026-11-08 10:20:12	app	ac915d42…	203.0.113.7	hit
```

一眼能看出"Widget 这次是被裁过的"，不用去猜返回值为什么只有 3 项。

### 验证

- 四个 PHP 文件 php-parser 静态校验通过（本机无 PHP，`php -l` 跑不了）；
- 用 node 按 `ttcoin_filter_output()` 的逻辑做等价模拟，11 组断言全过：
  | 场景 | 期望 | 实际 |
  | --- | --- | --- |
  | widget + 开关开 + 11 项 | 前 3 项，顺序不变 | `BTC, ETH, DOGE` |
  | app + 开关开 | 原样返回（连字符串都没重新编码） | 一致 |
  | widget + 开关关 | 原样返回 | 一致 |
  | 未带 `type` | 原样返回 | 一致 |
  | widget + 只有 3 项 | 不重新编码，返回原串 | 一致 |
  | 坏 JSON | 原样返回，不抛错 | 一致 |
  | 环境变量 `0` / `false` / `1` / 未设置 | 关 / 关 / 开 / 开 | 一致 |
- 未做真机验证：手表端不用改，`type=widget` 本来就在发，服务端上传即生效。

### 注意

裁剪取的是**候选池的前 N 项**，不是"涨幅前 3"。想让 Widget 固定显示某 3 个币种，调 `ttcoin_symbols()` 的数组顺序即可；App 版仍按接口顺序显示全部（受各自勾选控制）。

---

## 十六、移除手表端修改接口地址的功能

### 由来

第十节的背景是"侧载应用在 Garmin Connect 里没有设置页"，于是把接口地址搬到了手表菜单（`WatchUi.TextPicker` 手输，存 `Storage["ttcoin_api_url"]`）。实际用下来这套输入并不好用：URL 是一长串小写字母数字，用手表滚轮逐字符选完整条地址的交互成本极高，而且真正换地址的场景（换域名、换服务器）本来就要重新部署服务端，顺手改一次 `properties.xml` 重编译并不额外费事。按需求把这条入口整个撤掉。

### 删了什么

| 位置 | 内容 |
| --- | --- |
| `TTCoinDelegate.mc` | 主菜单第三项「接口地址」（副标题显示当前地址的 `apiUrlShort()` 一并失去用途） |
| `TTCoinMenu.mc` | `pushApiPicker()`、`TTCoinApiDelegate` 整段，`onSelect()` 的 `"api"` 分支 |
| `TTCoinView.mc` | `API_KEY`、`NOTICE_MS` 常量；`notice` / `noticeUntil` 状态；`apiUrlShort()`、`applyApiUrl()`、`activeNotice()`；`onUpdate()` 里"提示优先于副标题"的分支 |

`apiEndpoint()` 从三级优先级（Storage → 属性 → `DEFAULT_API`）简化为两级（属性 `apiUrl` → `DEFAULT_API`），`isValidApi()` 保留继续校验属性值。

### 保留了什么

- `properties.xml` 的 `apiUrl` 属性与 `settings.xml` 的「行情接口地址」设置项：**商店 / Beta 安装的版本仍可在手机端改**，侧载版本改 `properties.xml` 重编译；
- `isValidApi()` 与 `DEFAULT_API` 兜底：属性非法时照旧回退编译期默认值；
- 旧机器上已存进 `Storage["ttcoin_api_url"]` 的覆盖值**自然失效**（不再被读取），不会报错，也不需要清理。

### 减掉的东西

`notice` 机制是为"保存结果要给个反馈"存在的（`- Saved -` / `- Bad URL -` / `- Reset -` / `- Save Fail -`，占标题位 4 秒，`onUpdate` 两个分支配合），随功能一起删掉。`.prg` 从 112,604 字节降到 109,868 字节（−2.7KB，TextPicker 相关代码与字符串资源）。

### 验证

- 9.2.0 / 8.1.0 两个 SDK `-l 2` 编译均 `BUILD SUCCESSFUL`，告警仍是既有 8 条 poly type 提示；
- 全源码 `grep` 确认 `applyApiUrl` / `apiUrlShort` / `activeNotice` / `API_KEY` / `NOTICE_MS` / `TextPicker` 仅剩注释中的历史说明；
- 手表菜单现在是「选择币种 / 排序币种」两项，Start 键行为不变，Up/Down 翻页不受影响。

---

## 十七、换地址后仍 `- Offline -`：属性值跨安装保留，改了资源也不生效

### 现象

服务端迁到 `https://api.example.com/ttcoin/api/coin.php` 后，把 `properties.xml` 与 `DEFAULT_API` 都改了、重新编译、重新侧载，表上仍然是 `- Offline -`（有旧缓存时），底部价格是上一次成功抓到的旧值。

### 服务端先排除

```bash
curl -s -o /tmp/b -w "%{http_code} %{size_download}B %{time_total}s\n" \
  "https://api.example.com/ttcoin/api/coin.php?uid=t&type=app"
# 200 726B   -> 返回 11 项合法 JSON，无 BOM、无前导空白、字段齐全
```

同一路径换 `Garmin Connect IQ` 的 UA、换 HTTP/1.1、换 TLS 1.2 都是 200，说明不是 Cloudflare 拦 UA，也不是响应体格式问题。**故障在手表端。**

### 根因

`Application.Properties` 的值是**持久化**的：`resources/properties.xml` 只是"首次安装时的初值"，一旦属性库里有值（手机端设置写过、早期手表菜单 `applyApiUrl()` 写过、或首次安装时写入的旧默认值），之后改资源里的 `apiUrl` 都不会覆盖它。

这条路径上还叠了一个更早的坑：第十六节删掉手输地址之前，`applyApiUrl()` 里有一句 `Application.Properties.setValue("apiUrl", text)`——只要当时在表上存过一次地址，那个旧 URL 就永久钉在属性库里，之后任何重编译都改不动。表现就是"代码里明明是新地址，抓包却是旧地址"，且**没有任何报错**。

### 修复（三层，逐层兜底）

1. **显式回退**：`failWith(code)` 收到失败时，如果本次用的不是 `DEFAULT_API`，就用编译期默认地址再请求一次。旧属性值 / 单节点抽风都能自愈；
2. **记住死地址**：两次都失败且本次用的是属性地址，写 `Storage["ttcoin_api_bad"]`；`apiEndpoint()` 下一次直接跳过这条地址。属性值一旦被改成别的 URL，标记自动失配，新值重新参与尝试——不会把用户的手机端配置永久锁死；
3. **显示失败码**：`- Offline 403 -` / `No Net -104`。之前只显示 `- Offline -`，无法区分"连不上"和"被服务端拒绝"，排障全靠猜。

### 失败码怎么读

| 显示 | 含义 | 处理方向 |
| --- | --- | --- |
| `-104` 等负数 | 连接失败 / 超时 / TLS 握手失败 | 手机网络、DNS、线路 |
| `403` | 被 CDN / WAF 拒绝（域名在 Cloudflare 后面时常见） | 该子域名关掉代理（DNS only）或加放行规则 |
| `503` / `502` | 服务端或源站不可用 | 看 PHP / 容器状态 |
| `200` 但仍失败 | 返回体不是 JSON 数组 | `coin.php` 输出被前置告警污染 |

### 验证

- 8.1.0 / 9.2.0 两个 SDK `-l 2` 编译 `BUILD SUCCESSFUL`，告警仍是既有 8 条；
- 逻辑推演：属性=旧地址 → 第一次失败 → 自动用 `DEFAULT_API` 重试成功 → 正常出价，`Storage` 里留下旧地址标记 → 之后每轮只发一次请求；
- 属性=新地址（正常）时 `retriedFallback` 全程为 false，行为与旧版一致，没有额外请求。

### 遗留

真机复验依赖侧载，本轮只能保证"旧地址不会再卡住"。若装上后仍失败，屏幕上的响应码就是下一步的线索。

---

## 十八、`- Cache -` 一直不变：上游慢，接口在阻塞等

### 现象

装上修好地址的版本后，副标题停在 `- Cache -`，价格是十几分钟前的。既不是 `- Coin -`（成功）也不是 `- Offline xxx -`（失败），就这样卡着。

### 判断

`- Cache -` 只在 `loadCache()` 里设置，之后只有两种结局：`onReceive` 成功 → `- Coin -`，失败 → `- Offline <code> -`。停在 `- Cache -` 说明**响应还没回来**——请求在飞，或者干脆不会回调。

### 服务端实测

```bash
for i in 1 2 3; do curl -s -o /dev/null -w \
  "code=%{http_code} tls=%{time_appconnect}s first=%{time_starttransfer}s total=%{time_total}s\n" \
  "https://api.example.com/ttcoin/api/coin.php?uid=lat$i&type=app"; done
```

```
code=200 tls=4.16s first=14.88s total=20.71s
code=200 tls=0.57s first=1.79s total=5.10s
code=200 tls=0.55s first=30.76s total=30.76s
```

三次都 200，但**首字节 1.8s ~ 30.8s 随机**。第三次握手只花 0.55s，之后 30 秒全在等 PHP —— 卡在 `ttcoin_fetch()` 拉 Binance。手表侧的请求超时远小于这个抖动，于是"有时能出、多数时候一直等"。

根因不是地址错了，而是**接口把"取数据"和"给数据"绑定在一起**：缓存 TTL 只有 10 秒，几乎每次请求都要同步等上游；上游一慢，客户端就饿死。

### 修复（服务端为主）

1. **旧值先走 + 后台刷新**（`coin.php`）：缓存年龄在 `TTCOIN_STALE_SERVE`（默认 600s）以内时，先 `echo` 旧 JSON，再 `fastcgi_finish_request()` 把响应推给客户端，之后才在同一个进程里抓上游并写缓存。手表侧永远秒回，日志记为 `async`，备注写 `age=N`；
2. **单飞锁**（`lib.php` `ttcoin_refresh_background()`）：`flock` 非阻塞加锁，并发请求只有一个真去拉上游，其余直接放弃；
3. **锁文件不外露**：`.htaccess` 的 `FilesMatch` 加 `coin_cache\.json(\.lock)?`。

### 手表端配套

- **45 秒看门狗**（`REQUEST_TIMEOUT_MS`）：`onTimer` 里检查 `pendingSince`，超时就把 `lastCode` 置 `-1` 并 `handleFailure()`，界面不会永远停在 `- Cache -`；
- **不叠加请求**：上一轮还在飞时 `fetchPrice()` 直接返回，避免慢线路下请求越堆越多；
- `onReceive` 第一行清 `pendingSince`，成败都算这一轮结束。

### 验证

- 9.2.0 / 8.1.0 编译 `BUILD SUCCESSFUL`，告警仍 8 条；四个 PHP 文件 php-parser 通过；
- 服务端改动上线后，`curl` 应稳定在百毫秒级（命中 `hit` 或 `async`），不再出现 30 秒的 `fresh`；
- 非 PHP-FPM（Apache mod_php）没有 `fastcgi_finish_request()`，自动退回原来的阻塞流程，行为与上一版一致。

### 遗留

Cloudflare 到国内的线路本身也在抖（tls 0.5s ~ 4.2s）。若仍偏慢，可考虑给 `ba-api-home` 这个子域名关掉 CF 代理（DNS only）直连源站，或用 cron 每 10 秒预热让缓存始终新鲜。

## 十九、菜单文案双语资源化：把"硬编码中文"换成资源限定符

### 现象

模拟器里 Start 菜单的标题 `TTCoin` 正常，条目全是一排方块。不是编码问题，也不是字体没加载，
而是**文案写死在源码里 + 固件没有中文字形**：

```monkey-c
menu.addItem(new WatchUi.MenuItem("选择币种", "设置显示哪些交易对", "select", null));
```

Instinct 2X 有两个固件 SKU：

| SKU | 字体集 | 中文 |
| --- | --- | --- |
| 国际版 `006-B4394-00` | Roboto（拉丁） | 缺字 → 方块 |
| 中文版 | 额外带 `Noto Sans SC` | 正常 |

模拟器加载的是国际版字体集，所以一定方块；真机则取决于用户买的是哪个 SKU。
用户实测自己的表是中文固件（显示正常），但**上架给国际用户仍是坏体验**，故做资源化。

### 改法

1. 文案全部搬进资源表，英文放**基础语言**（兜底），中文放语言限定符目录：

   ```
   resources/strings/strings.xml        # 英文，纯 ASCII
   resources-zhs/strings/strings.xml    # 简体中文，id 一一对应
   ```

2. 新增 `source/TTCoinText.mc` 作为唯一取用入口：

   ```monkey-c
   static function get(id as Lang.ResourceId, fallback as Lang.String) as Lang.String {
       var value = WatchUi.loadResource(id);
       ...
       return fallback;
   }
   ```

   - 形参类型是 `Lang.ResourceId` 而**不是** `Lang.Symbol`：`Rez.Strings.Xxx` 的类型是
     `$.Toybox.Lang.ResourceId`，写成 `Symbol` 在 `-l 2` 下直接报
     `Invalid 'ResourceId' passed as parameter 1 of type 'Symbol'`（本轮实际踩到）；
   - 保留 `fallback`：资源漏了/取不到时 `loadResource` 返回 `null`，strict 模式下当字符串用会抛类型错误。

3. `manifest.xml` 的 `<iq:languages>` 补成 `eng` + `zhs`。注意它只是**商店元数据**，
   运行时选择完全由资源目录后缀决定（改它不会改变表上显示的语言）。

### 顺带修掉的一处缺字

「上移 ↑」「下移 ↓」里的箭头同样不在内建字体里（`U+2191`/`U+2193`），运行时是空心菱形，
两个条目长得一模一样，排序菜单基本没法用。菜单只能画文字、不能像行情箭头那样
`fillPolygon`，所以直接去掉箭头 → `上移` / `下移`、`Move Up` / `Move Down`。

### 验证

| 手段 | 结果 |
| --- | --- |
| `monkeyc -l 2` | 0 error / 8 warning（与前一轮同数量，无新增） |
| 产物字节校验 | `Choose pairs`×2、`Current order`×2、`Move Up`×2；`选择币种`/`排序（当前顺序）`/`上移` 各 ×1；旧 `↑` **0 命中** |
| 运行时（模拟器，语言=英文） | 菜单显示 `Coins` / `Choose pairs`，无方块 → 资源取用链路通 |
| 中文分支 | 模拟器无语言切换入口、字体也没有中文，无法构造 `zhs` 环境 → 留真机（`docs/RELEASE.md` §6 第 4 步） |

### 遗留

- 行情页状态词 `- Coin -` / `- Cache -` / `No Net` 仍是英文：它们的宽度是逐像素量着
  八边形可用宽度定的，翻译要重新量版，收益只有几个词；
- 菜单语言跟随系统语言，没有独立开关。若以后要"中文手表也显示英文"，得在
  `properties/settings` 加一个语言选项，再在 `TTCoinText` 里做"强制语言"分支。
