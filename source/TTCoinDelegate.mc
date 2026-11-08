import Toybox.Lang;
import Toybox.WatchUi;

// 主视图按键代理（BehaviorDelegate 会把实体按键映射成行为事件）：
//   Start/Enter (KEY_ENTER) → onSelect()       打开设置菜单
//   Up          (KEY_UP)    → onPreviousPage() 上一页
//   Down        (KEY_DOWN)  → onNextPage()     下一页
//   Back        (KEY_ESC)   → onBack() 不覆写，走系统默认（退出 App）
// 各方法返回 true 表示事件已消费；返回 false 会继续传给系统默认行为。
class TTCoinDelegate extends WatchUi.BehaviorDelegate {

    var viewRef as TTCoinView;

    function initialize(view as TTCoinView) {
        BehaviorDelegate.initialize();

        viewRef = view;
    }

    function onSelect() as Lang.Boolean {
        pushMainMenu();
        return true;
    }

    function onNextPage() as Lang.Boolean {
        viewRef.page(1);
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        viewRef.page(-1);
        return true;
    }

    function pushMainMenu() as Void {
        var menu = new WatchUi.Menu2({
            :title => "TTCoin"
        });

        // 文案来自资源表（中文 / 英文由设备系统语言决定），见 TTCoinText.mc
        menu.addItem(new WatchUi.MenuItem(
            TTCoinText.get(Rez.Strings.MenuCoins, "Coins"),
            TTCoinText.get(Rez.Strings.MenuCoinsDesc, "Choose pairs"),
            "select",
            null
        ));

        menu.addItem(new WatchUi.MenuItem(
            TTCoinText.get(Rez.Strings.MenuSort, "Reorder"),
            TTCoinText.get(Rez.Strings.MenuSortDesc, "Change order"),
            "sort",
            null
        ));

        // 接口地址不再支持手表端修改（原第三层 TextPicker 已移除），
        // 地址由编译期 DEFAULT_API / 手机端属性 apiUrl 决定

        WatchUi.pushView(menu, new TTCoinMainMenuDelegate(viewRef), WatchUi.SLIDE_IMMEDIATE);
    }
}
