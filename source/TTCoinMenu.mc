import Toybox.Lang;
import Toybox.WatchUi;

// ======================================================================
// TTCoin 设置菜单（Start 键呼出）
//
// 两层 Menu2：
//   主菜单    选择币种 / 排序币种
//   选择币种  ToggleMenuItem 勾选，写 Properties（与手机端设置共享）
//   排序币种  列出已启用币种 → 选中一个 → 上移/下移 → 存 Storage 顺序表
//
// 接口地址原来有第三层（WatchUi.TextPicker 手输，存 Storage 覆盖值），
// 2026-11 按需求移除——地址只从属性 apiUrl / DEFAULT_API 读。
//
// 选择与排序的持久化逻辑都在 TTCoinView 里（isCoinEnabled / toggleCoin /
// moveCoin），菜单只负责交互。
// ======================================================================

// ---------------- 主菜单 ----------------

class TTCoinMainMenuDelegate extends WatchUi.Menu2InputDelegate {

    var viewRef as TTCoinView;

    function initialize(view as TTCoinView) {
        Menu2InputDelegate.initialize();

        viewRef = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {

        var id = item.getId();

        if (!(id instanceof Lang.String)) {
            return;
        }

        if ((id as Lang.String).equals("select")) {
            pushToggleMenu();
        } else if ((id as Lang.String).equals("sort")) {
            pushSortMenu(viewRef);
        }
    }

    function pushToggleMenu() as Void {

        var menu = new WatchUi.Menu2({
            :title => TTCoinText.get(Rez.Strings.MenuCoins, "Coins")
        });

        var coins = viewRef.catalog();

        for (var i = 0; i < coins.size(); i++) {

            var label = coins[i] as Lang.String;

            menu.addItem(new WatchUi.ToggleMenuItem(
                label,
                null,
                label,
                viewRef.isCoinEnabled(label),
                null
            ));
        }

        WatchUi.pushView(menu, new TTCoinToggleDelegate(viewRef), WatchUi.SLIDE_IMMEDIATE);
    }
}

// ---------------- 选择币种（勾选） ----------------

class TTCoinToggleDelegate extends WatchUi.Menu2InputDelegate {

    var viewRef as TTCoinView;

    function initialize(view as TTCoinView) {
        Menu2InputDelegate.initialize();

        viewRef = view;
    }

    // ToggleMenuItem 的勾选状态由 Menu2 自动翻转，这里只负责持久化
    function onSelect(item as WatchUi.MenuItem) as Void {

        var id = item.getId();

        if (id instanceof Lang.String) {
            viewRef.toggleCoin(id as Lang.String);
        }
    }
}

// ---------------- 排序币种（列表） ----------------

// 排序菜单需要反复重建（移动一位后顺序变了），抽成文件级函数供复用。
// Monkey C 文件顶层的函数属于本文件的隐式模块，同一文件内直接可见。
function pushSortMenu(view as TTCoinView) as Void {

    var menu = new WatchUi.Menu2({
        :title => TTCoinText.get(Rez.Strings.MenuSortList, "Current order")
    });

    var coins = view.effectiveCoins();

    for (var i = 0; i < coins.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(
            (i + 1) + "  " + (coins[i] as Lang.String),
            null,
            coins[i],
            null
        ));
    }

    WatchUi.pushView(menu, new TTCoinSortDelegate(view), WatchUi.SLIDE_IMMEDIATE);
}

class TTCoinSortDelegate extends WatchUi.Menu2InputDelegate {

    var viewRef as TTCoinView;

    function initialize(view as TTCoinView) {
        Menu2InputDelegate.initialize();

        viewRef = view;
    }

    // 选中某个币种后，弹"上移/下移"二级菜单
    function onSelect(item as WatchUi.MenuItem) as Void {

        var id = item.getId();

        if (!(id instanceof Lang.String)) {
            return;
        }

        var label = id as Lang.String;

        var menu = new WatchUi.Menu2({
            :title => label
        });

        // 条目文案来自资源表；这里不带箭头字符（内建字体缺 ↑/↓，会画成菱形）
        menu.addItem(new WatchUi.MenuItem(
            TTCoinText.get(Rez.Strings.MenuMoveUp, "Move Up"), null, label + "|up", null));
        menu.addItem(new WatchUi.MenuItem(
            TTCoinText.get(Rez.Strings.MenuMoveDown, "Move Down"), null, label + "|down", null));

        WatchUi.pushView(menu, new TTCoinMoveDelegate(viewRef), WatchUi.SLIDE_IMMEDIATE);
    }
}

class TTCoinMoveDelegate extends WatchUi.Menu2InputDelegate {

    var viewRef as TTCoinView;

    function initialize(view as TTCoinView) {
        Menu2InputDelegate.initialize();

        viewRef = view;
    }

    // identifier 是 "LABEL|up" / "LABEL|down"，| 后是方向
    function onSelect(item as WatchUi.MenuItem) as Void {

        var id = item.getId();

        if (!(id instanceof Lang.String)) {
            return;
        }

        var text  = id as Lang.String;
        var sep   = text.find("|");

        if (!(sep instanceof Lang.Number)) {
            return;
        }

        var at     = sep as Lang.Number;
        var label  = text.substring(0, at) as Lang.String;
        var action = text.substring(at + 1, text.length()) as Lang.String;

        viewRef.moveCoin(label, action.equals("up") ? -1 : 1);

        // 顺序变了，原排序菜单上的位置编号已过期：
        // 连退两层回到主视图，再重推一份新的排序菜单
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        pushSortMenu(viewRef);
    }
}
